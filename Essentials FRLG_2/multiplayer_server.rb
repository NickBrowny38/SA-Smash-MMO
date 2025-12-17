#!/usr/bin/env ruby
#===============================================================================
# Pokemon Essentials Multiplayer Server
# Standalone TCP server for handling multiplayer connections
# Pterodactyl Panel Compatible
#===============================================================================

require 'socket'
require 'json'
require 'logger'
require 'optparse'
require 'sqlite3'
require 'digest'
require 'time'  # For Time.parse in cmd_playtime

# Load server configuration
require_relative 'server_config'
require_relative 'server_trade_v2'

#===============================================================================
# SERVER-SIDE ANTI-CHEAT (Cannot be modified by clients!)
#===============================================================================
module ServerAntiCheat
  MAX_POKEMON_LEVEL = 100
  MAX_STAT_VALUE = 999
  MAX_MONEY = 999999999

  # Rate limiting (seconds between actions)
  RATE_LIMITS = {
    move: 0.03,    # 33 updates/sec - relaxed for smoother gameplay (no movement validation)
    battle: 0.5,
    item: 0.3,
    trade: 5.0,
    spawn: 10.0
  }

  def validate_pokemon_data(pokemon_data)
    return {valid: false, error: "Pokemon data is nil"} unless pokemon_data

    # Validate level
    level = pokemon_data[:level].to_i
    if level < 1 || level > MAX_POKEMON_LEVEL
      return {valid: false, error: "Invalid level: #{level} (must be 1-#{MAX_POKEMON_LEVEL})"}
    end

    # Validate stats aren't impossibly high
    [:hp, :attack, :defense, :speed, :sp_atk, :sp_def].each do |stat|
      stat_value = pokemon_data[stat].to_i
      if stat_value > MAX_STAT_VALUE
        return {valid: false, error: "Invalid #{stat}: #{stat_value} (max: #{MAX_STAT_VALUE})"}
      end
    end

    {valid: true}
  end

  def validate_money(money)
    money.to_i.between?(0, MAX_MONEY)
  end

  def check_rate_limit(client_id, action_type)
    @rate_limit_tracker ||= {}
    @rate_limit_tracker[client_id] ||= {}

    last_time = @rate_limit_tracker[client_id][action_type] || 0
    current_time = Time.now.to_f
    min_interval = RATE_LIMITS[action_type] || 0.1

    if (current_time - last_time) < min_interval
      return false  # Rate limited!
    end

    @rate_limit_tracker[client_id][action_type] = current_time
    true
  end

  def ban_cheater(client_id, reason)
    # Get username BEFORE disconnecting (disconnect removes from @clients)
    username = @clients[client_id] ? @clients[client_id][:username] : "Unknown"

    @logger.error "[ANTI-CHEAT] Client #{client_id} (#{username}) BANNED: #{reason}"
    send_error(client_id, "You have been banned for cheating: #{reason}")

    # Add to ban list in database BEFORE disconnecting
    db_ban_player(username, reason) if username && username != "Unknown"

    disconnect_client(client_id)
  end
end

class MultiplayerServer
  include ServerAntiCheat  # Include anti-cheat validation

  # Server version using Semantic Versioning (MAJOR.MINOR.PATCH)
  VERSION = "0.1.7"
  # Minimum client version required to connect (reject older clients)
  MIN_CLIENT_VERSION = "0.1.0"
  # Expected game ID (must match client's GAME_ID)
  EXPECTED_GAME_ID = "essentials_frlg_v1.0"

  DEFAULT_PORT = ServerConfig::PORT
  DEFAULT_MAX_PLAYERS = ServerConfig::MAX_PLAYERS

  attr_reader :port, :max_players, :running

  def initialize(port: DEFAULT_PORT, max_players: DEFAULT_MAX_PLAYERS, log_level: ServerConfig.log_level_constant, db_path: ServerConfig::DATABASE_PATH)
    @port = port
    @max_players = max_players
    @clients = {}           # client_id => client_info
    @player_data = {}       # client_id => player_state
    @server = nil
    @running = false
    @next_client_id = 1
    @db_path = db_path
    @active_battles = {}    # battle_id => battle session data
    @next_battle_id = 1
    @last_pm_sender = {}    # client_id => last sender username (for /reply)
    @tp_requests = {}       # client_id => {requester_id: id, requester_username: name, expires_at: time}
    @maintenance_mode = false

    # Force STDOUT to flush immediately (no buffering)
    STDOUT.sync = true
    STDERR.sync = true

    # Setup logger
    @logger = Logger.new(STDOUT)
    @logger.level = log_level
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
    end

    @logger.info "Pokemon Essentials Multiplayer Server v#{VERSION}"
    @logger.info "Minimum client version required: v#{MIN_CLIENT_VERSION}"

    # Initialize database
    initialize_database

    # Initialize modern trade system v2
    initialize_trade_v2_system
  end

  def start
    begin
      @server = TCPServer.new(@port)
      @running = true
      @logger.info "Server started on port #{@port}"
      @logger.info "Max players: #{@max_players}"
      @logger.info "Waiting for connections..."

      Thread.new { heartbeat_loop }
      Thread.new { start_http_server }

      loop do
        Thread.start(@server.accept) do |client|
          handle_client(client)
        end
      end
    rescue Interrupt
      @logger.info "Server shutting down gracefully..."
      shutdown
    rescue => e
      @logger.error "Server error: #{e.message}"
      @logger.error e.backtrace.join("\n")
      shutdown
    end
  end

  def shutdown
    @running = false
    @clients.each do |id, info|
      info[:socket].close rescue nil
    end
    @server.close if @server
    @logger.info "Server stopped"
    exit
  end

  private

  #===============================================================================
  # Version Checking (Semantic Versioning Support)
  #===============================================================================

  # Parse version string into components
  def parse_version(version_string)
    parts = version_string.to_s.split('.').map(&:to_i)
    # Pad with zeros if needed
    while parts.length < 3
      parts << 0
    end
    {
      major: parts[0],
      minor: parts[1],
      patch: parts[2]
    }
  end

  # Compare versions: returns -1 if v1 < v2, 0 if equal, 1 if v1 > v2
  def compare_versions(version1, version2)
    v1 = parse_version(version1)
    v2 = parse_version(version2)

    # Compare major version
    return -1 if v1[:major] < v2[:major]
    return 1 if v1[:major] > v2[:major]

    # Compare minor version
    return -1 if v1[:minor] < v2[:minor]
    return 1 if v1[:minor] > v2[:minor]

    # Compare patch version
    return -1 if v1[:patch] < v2[:patch]
    return 1 if v1[:patch] > v2[:patch]

    # Equal
    return 0
  end

  # Check if versions are compatible (same major version)
  def versions_compatible?(client_version, server_version)
    client = parse_version(client_version)
    server = parse_version(server_version)

    return client[:major] == server[:major]
  end

  # Check if client meets minimum version requirement
  def meets_minimum_version?(client_version, min_required)
    return compare_versions(client_version, min_required) >= 0
  end

  # Send version-specific error message with enhanced data
  def send_version_error(client_id, error_type, client_version)
    case error_type
    when :version_mismatch
      send_error_enhanced(client_id, {
        error_type: "version_mismatch",
        message: "Incompatible game version. Please update your game.",
        server_version: VERSION,
        client_version: client_version
      })

    when :outdated_client
      send_error_enhanced(client_id, {
        error_type: "outdated_client",
        message: "Your game version is too old. Please update to continue playing.",
        server_version: VERSION,
        client_version: client_version,
        min_required_version: MIN_CLIENT_VERSION
      })
    end
  end

  # Send enhanced error with additional data fields
  def send_error_enhanced(client_id, data)
    send_to_client(client_id, {
      type: "error",
      data: data
    })
  end

  # Send update notification to client (newer version available but compatible)
  def send_update_notification(client_id, client_version)
    send_to_client(client_id, {
      type: "update_available",
      data: {
        new_version: VERSION,
        current_version: client_version,
        message: "A new game update is available! Update to v#{VERSION} for new features and bug fixes."
      }
    })

    @logger.info "[VERSION] Sent update notification to client ##{client_id} (#{client_version} -> #{VERSION})"
  end

  #===============================================================================

  def handle_client(socket)
    client_id = @next_client_id
    @next_client_id += 1

    client_info = {
      id: client_id,
      socket: socket,
      username: nil,
      connected_at: Time.now,
      last_heartbeat: Time.now
    }

    @clients[client_id] = client_info
    @logger.info "Client ##{client_id} connected from #{socket.peeraddr[3]}"

    begin
      loop do
        # Read line-delimited JSON messages
        message_str = socket.gets
        break if message_str.nil?

        message_str.strip!
        next if message_str.empty?

        process_message(client_id, message_str)
      end
    rescue => e
      @logger.error "Error handling client ##{client_id}: #{e.message}"
      @logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
    ensure
      disconnect_client(client_id)
    end
  end

  def process_message(client_id, message_str)
    begin
      message = JSON.parse(message_str, symbolize_names: true)
      client_info = @clients[client_id]

      # Debug log all non-position messages
      unless message[:type] == "position_update" || message[:type] == :position_update
        @logger.info "[SERVER DEBUG] Received message from client #{client_id}: type=#{message[:type]}"
        if message[:type] == :trade_offer || message[:type] == "trade_offer"
          @logger.info "[SERVER DEBUG] Message keys: #{message.keys.inspect}"
          @logger.info "[SERVER DEBUG] Message[:data]: #{message[:data].inspect}"
        end
      end

      case message[:type]
    when :connect, "connect"
      handle_connect(client_id, message[:data])

    when :position_update, "position_update"
      handle_position_update(client_id, message[:data])

    when :follower_update, "follower_update"
      handle_follower_update(client_id, message[:data])

    when :bag_update, "bag_update"
      handle_bag_update(client_id, message[:data])

    when :pokemon_update, "pokemon_update"
      handle_pokemon_update(client_id, message[:data])

    when :save_data, "save_data"
      handle_save_data(client_id, message[:data])

    when :daycare_update, "daycare_update"
      handle_daycare_update(client_id, message[:data])

    when :chat_message, "chat_message"
      handle_chat_message(client_id, message[:data])

    when :check_item, "check_item"
      handle_check_item(client_id, message[:data])

    when :collect_item, "collect_item"
      handle_collect_item(client_id, message[:data])

    when :get_collected_items, "get_collected_items"
      handle_get_collected_items(client_id, message[:data])

    when :battle_request, "battle_request"
      handle_battle_request(client_id, message[:data])

    when :battle_accept, "battle_accept"
      handle_battle_accept(client_id, message[:data])

    when :battle_decline, "battle_decline"
      handle_battle_decline(client_id, message[:data])

    when :battle_party_request, "battle_party_request"
      handle_battle_party_request(client_id, message[:data])

    when :battle_choice, "battle_choice"
      handle_battle_choice(client_id, message[:data])

    when :battle_state, "battle_state"
      handle_battle_state(client_id, message[:data])

    when :battle_complete, "battle_complete"
      handle_battle_complete(client_id, message[:data])

    when :get_social_data, "get_social_data"
      handle_get_social_data(client_id, message[:data])

    when :trade_offer, "trade_offer"
      handle_trade_offer(client_id, message[:data])

    when :trade_accept, "trade_accept"
      handle_trade_accept(client_id, message[:data])

    when :trade_decline, "trade_decline"
      handle_trade_decline(client_id, message[:data])

    when :trade_complete, "trade_complete"
      handle_trade_complete_confirmation(client_id, message[:data])

    # Modern Trade System V2
    when :trade_offer_v2, "trade_offer_v2"
      handle_trade_offer_v2(client_id, message[:data])

    when :trade_counter_offer_v2, "trade_counter_offer_v2"
      handle_trade_counter_offer_v2(client_id, message[:data])

    when :trade_confirm_v2, "trade_confirm_v2"
      handle_trade_confirm_v2(client_id, message[:data])

    when :trade_decline_v2, "trade_decline_v2"
      handle_trade_decline_v2(client_id, message[:data])

    when :trade_change_offer_v2, "trade_change_offer_v2"
      handle_trade_change_offer_v2(client_id, message[:data])

    when :trade_complete_ack_v2, "trade_complete_ack_v2"
      handle_trade_complete_ack_v2(client_id, message[:data])

    when :auction_list_item, "auction_list_item"
      handle_auction_list_item(client_id, message[:data])

    when :auction_list_pokemon, "auction_list_pokemon"
      handle_auction_list_pokemon(client_id, message[:data])

    when :auction_browse, "auction_browse"
      handle_auction_browse(client_id, message[:data])

    when :auction_buy, "auction_buy"
      handle_auction_buy(client_id, message[:data])

    when :auction_cancel, "auction_cancel"
      handle_auction_cancel(client_id, message[:data])

    when :auction_my_listings, "auction_my_listings"
      handle_auction_my_listings(client_id, message[:data])

    when :claim_starter, "claim_starter"
      handle_claim_starter(client_id, message[:data])

    when :heartbeat, "heartbeat"
      client_info[:last_heartbeat] = Time.now

    when :follower_update, "follower_update"
      handle_follower_update(client_id, message[:data])

    when :disconnect, "disconnect"
      disconnect_client(client_id)

    else
      @logger.warn "Unknown message type from client ##{client_id}: #{message[:type]}"
    end

    rescue StandardError => e
      @logger.error "Error processing message from client ##{client_id} (type: #{message[:type] rescue 'unknown'}): #{e.message}"
      @logger.error "Backtrace: #{e.backtrace.first(10).join("\n")}"
      send_error(client_id, "Server error processing request")
    rescue JSON::ParserError => e
      @logger.error "Invalid JSON from client ##{client_id}: #{e.message}"
      send_error(client_id, "Invalid message format")
    end
  end

  def handle_connect(client_id, data)
    username = data[:username]
    password = data[:password] || username  # Default password = username (basic)
    client_version = data[:version] || "0.0.0"  # Default for old clients without version
    client_game_id = data[:game_id]  # Game identifier (new field)
    client_info = @clients[client_id]

    @logger.info "[AUTH] Client ##{client_id} connecting: #{username} (version #{client_version}, game: #{client_game_id || 'unknown'})"

    # ========== GAME ID CHECKING (STEP 0) ==========
    # Verify the client is connecting with the correct game
    # This prevents users with different games from joining incompatible servers

    if client_game_id != EXPECTED_GAME_ID
      @logger.warn "[AUTH] REJECTED: Game mismatch - Client '#{client_game_id}' vs Server '#{EXPECTED_GAME_ID}'"
      send_to_client(client_id, {
        type: "error",
        data: {
          error_type: "game_mismatch",
          message: "Wrong game! This server is for #{EXPECTED_GAME_ID}",
          expected_game_id: EXPECTED_GAME_ID
        }
      })
      disconnect_client(client_id)
      return
    end

    # ========== VERSION CHECKING (STEP 1) ==========
    # Check version compatibility BEFORE authentication
    # This prevents incompatible clients from accessing the database

    # STEP 1A: Check major version compatibility
    unless versions_compatible?(client_version, VERSION)
      # Major version mismatch - incompatible client
      @logger.warn "[AUTH] REJECTED: Version incompatible - Client #{client_version} vs Server #{VERSION}"
      send_version_error(client_id, :version_mismatch, client_version)
      disconnect_client(client_id)
      return
    end

    # STEP 1B: Check minimum version requirement
    unless meets_minimum_version?(client_version, MIN_CLIENT_VERSION)
      # Client is too old - reject connection
      @logger.warn "[AUTH] REJECTED: Client outdated - #{client_version} < minimum #{MIN_CLIENT_VERSION}"
      send_version_error(client_id, :outdated_client, client_version)
      disconnect_client(client_id)
      return
    end

    # STEP 1C: Require exact version match
    if client_version != VERSION
      # Client version doesn't match server - reject to force update
      @logger.warn "[AUTH] REJECTED: Client version mismatch - #{client_version} != #{VERSION} (exact match required)"
      send_version_error(client_id, :outdated_client, client_version)
      disconnect_client(client_id)
      return
    end

    # ========== END VERSION CHECKING ==========

    # Check if username is already online
    if @clients.values.any? { |c| c[:username] == username && c[:id] != client_id }
      send_error(client_id, "Username already online")
      disconnect_client(client_id)
      return
    end

    # Check max players
    if @clients.count { |_, c| c[:username] } >= @max_players
      send_error(client_id, "Server full")
      disconnect_client(client_id)
      return
    end

    # Try to authenticate or register
    auth_result = authenticate_player(username, password)

    if auth_result == :wrong_password
      # User exists but password is wrong
      @logger.warn "Invalid password for #{username}"
      send_error(client_id, "Invalid password! Please check your password and try again.")
      disconnect_client(client_id)
      return
    elsif auth_result == :not_found
      # User doesn't exist, try to register
      @logger.info "New player detected, registering: #{username}"
      player_data = register_player(username, password)

      if player_data.nil?
        send_error(client_id, "Registration failed - please try a different username")
        disconnect_client(client_id)
        return
      end
    else
      # Successful authentication
      player_data = auth_result
    end

    # Load full player data from database
    full_data = load_player_data(player_data[:id])

    client_info[:username] = username
    client_info[:player_id] = player_data[:id]

    @player_data[client_id] = {
      id: client_id,
      player_id: player_data[:id],
      username: username,
      map_id: player_data[:map_id],
      x: player_data[:x],
      y: player_data[:y],
      real_x: player_data[:x] * 32,
      real_y: player_data[:y] * 32,
      direction: player_data[:direction],
      pattern: 0,
      move_speed: 3,
      movement_type: 0,
      charset: "trainer_POKEMONTRAINER_Red",
      bag: full_data ? full_data[:bag] : [],
      pokemon: full_data ? full_data[:pokemon] : [],
      pc_boxes: full_data ? full_data[:pc_boxes] : [],
      money: full_data ? (full_data[:money] || ServerConfig::STARTING_MONEY) : ServerConfig::STARTING_MONEY
    }

    @logger.info "Client ##{client_id} logged in as '#{username}' (Player ID: #{player_data[:id]})"

    # Send connection confirmation with client_id
    send_to_client(client_id, {
      type: "connected",
      data: {
        client_id: client_id,
        username: username
      }
    })

    # Send current player list to new player
    send_player_list(client_id)

    # Set session start time for playtime tracking
    db_playtime = SQLite3::Database.new(@db_path)
    db_playtime.execute("UPDATE players SET session_start = ? WHERE id = ?", [Time.now.to_i, player_data[:id]])
    db_playtime.close

    # Send player's saved position back
    send_to_client(client_id, {
      type: "player_data",
      data: {
        map_id: player_data[:map_id],
        x: player_data[:x],
        y: player_data[:y],
        direction: player_data[:direction],
        bag: @player_data[client_id][:bag],
        pokemon: @player_data[client_id][:pokemon],
        pc_boxes: full_data ? (full_data[:pc_boxes] || []) : [],
        has_running_shoes: player_data[:has_running_shoes] || 0,
        has_starter: player_data[:has_starter] || 0,
        money: full_data ? (full_data[:money] || 3000) : 3000,
        badge_count: full_data ? (full_data[:badge_count] || 0) : 0,
        trainer_id: full_data ? full_data[:trainer_id] : nil,
        badges: full_data ? (full_data[:badges] || [false] * 8) : [false] * 8,
        switches: full_data ? (full_data[:switches] || {}) : {},
        variables: full_data ? (full_data[:variables] || {}) : {},
        self_switches: full_data ? (full_data[:self_switches] || {}) : {},
        pokedex: full_data ? (full_data[:pokedex] || {}) : {},
        playtime_seconds: full_data ? (full_data[:playtime_seconds] || 0) : 0,
        created_at: full_data ? full_data[:created_at] : nil
      }
    })

    # Version is exact match - no need to notify (we reject mismatches earlier)

    # Broadcast new player to all other players
    broadcast_player_joined(client_id)
  end

  def handle_position_update(client_id, data)
    return unless @player_data[client_id]

    # Rate limiting to prevent network spam (no movement validation)
    unless check_rate_limit(client_id, :move)
      return  # Silently drop - too many updates
    end

    player = @player_data[client_id]
    old_map_id = player[:map_id]

    player[:map_id] = data[:map_id] if data[:map_id]
    player[:x] = data[:x] if data[:x]
    player[:y] = data[:y] if data[:y]
    player[:real_x] = data[:real_x] if data[:real_x]
    player[:real_y] = data[:real_y] if data[:real_y]
    player[:direction] = data[:direction] if data[:direction]
    player[:pattern] = data[:pattern] if data[:pattern]
    player[:move_speed] = data[:move_speed] if data[:move_speed]
    player[:movement_type] = data[:movement_type] if data[:movement_type]

    # Save position to database every 10 updates (reduced DB writes)
    player[:update_count] ||= 0
    player[:update_count] += 1

    if player[:update_count] >= 10 && player[:player_id]
      save_player_position(player[:player_id], player[:map_id], player[:x], player[:y], player[:direction])

      # Save money and badges if included in position update (every 10 updates)
      if data[:money] && data[:money].to_i >= 0 && data[:money].to_i <= ServerAntiCheat::MAX_MONEY
        current_money = player[:money] || 0
        new_money = data[:money].to_i
        if new_money != current_money
          update_player_money(player[:player_id], new_money)
          player[:money] = new_money
          @logger.info "[MONEY SYNC] #{@clients[client_id][:username]}: $#{current_money} -> $#{new_money}"
        end
      end

      if data[:badge_count] && data[:badge_count].to_i >= 0 && data[:badge_count].to_i <= 16
        current_badges = player[:badge_count] || 0
        new_badges = data[:badge_count].to_i
        if new_badges != current_badges
          update_player_badge_count(player[:player_id], new_badges)
          player[:badge_count] = new_badges
          @logger.info "[BADGE SYNC] #{@clients[client_id][:username]}: #{current_badges} -> #{new_badges} badges"
        end
      end

      player[:update_count] = 0
    end
    player[:charset] = data[:charset] if data[:charset]

    # Store follower data for Following Pokemon integration
    if data[:follower]
      player[:follower] = data[:follower]
      @logger.info "[FOLLOWER] Client #{client_id} has follower: #{data[:follower].inspect}"
    elsif data.has_key?(:follower) && data[:follower].nil?
      # Explicitly nil means follower was removed (toggled off)
      player[:follower] = nil
      @logger.info "[FOLLOWER] Client #{client_id} removed follower"
    else
      # Debug: log when no follower data is received
      unless @follower_debug_logged
        @logger.info "[FOLLOWER] Client #{client_id} position_update keys: #{data.keys.inspect}"
        @follower_debug_logged = true
      end
    end

    # If map changed, broadcast to BOTH old and new maps so sprites get removed properly
    if old_map_id && player[:map_id] && old_map_id != player[:map_id]
      @logger.info "Player #{client_id} warped from map #{old_map_id} to #{player[:map_id]}"
      broadcast_position_update(client_id, old_map_id)  # Tell old map they left
      broadcast_position_update(client_id, player[:map_id])  # Tell new map they arrived
    else
      # Normal update - broadcast to current map only
      broadcast_position_update(client_id)
    end
  end

  def handle_follower_update(client_id, data)
    return unless @player_data[client_id]

    player = @player_data[client_id]

    # Update follower data
    if data[:follower]
      player[:follower] = data[:follower]
      @logger.info "[FOLLOWER UPDATE] Client #{client_id} has follower: #{data[:follower].inspect}"
    elsif data.has_key?(:follower) && data[:follower].nil?
      # Explicitly nil means follower was removed (toggled off)
      player[:follower] = nil
      @logger.info "[FOLLOWER UPDATE] Client #{client_id} removed follower"
    end

    # Broadcast follower update to all players on the same map
    broadcast_follower_update(client_id)
  end

  def broadcast_follower_update(client_id, target_map_id = nil)
    player = @player_data[client_id]
    return unless player

    map_id = target_map_id || player[:map_id]
    return unless map_id

    # Build follower update message
    update_data = {
      id: client_id,
      follower: player[:follower]  # Can be nil if removed
    }

    # Broadcast to all players on the same map (except sender)
    @player_data.each do |other_client_id, other_player|
      next if other_client_id == client_id  # Don't send to self
      next unless other_player[:map_id] == map_id  # Only same map

      send_to_client(other_client_id, {
        type: "follower_update",
        data: update_data
      })
    end
  end

  def handle_bag_update(client_id, data)
    return unless @clients[client_id][:player_id]

    # ANTI-CHEAT: Rate limiting
    unless check_rate_limit(client_id, :item)
      @logger.warn "[ANTI-CHEAT] Client #{client_id} rate limited (bag update spam)"
      return
    end

    player_id = @clients[client_id][:player_id]
    bag_data = data[:bag]

    if bag_data
      # ANTI-CHEAT: Validate item quantities
      if bag_data.is_a?(Hash)
        bag_data.each do |pocket, items|
          if items.is_a?(Array)
            items.each do |item|
              if item.is_a?(Array) && item[1].to_i > 999
                ban_cheater(client_id, "Invalid item quantity (999+ items)")
                return
              end
            end
          end
        end
      end

      # ANTI-CHEAT: Validate money if included
      if data[:money] && !validate_money(data[:money])
        ban_cheater(client_id, "Invalid money amount detected")
        return
      end

      save_player_bag(player_id, bag_data)
      @player_data[client_id][:bag] = bag_data if @player_data[client_id]
    end
  end

  def handle_pokemon_update(client_id, data)
    return unless @clients[client_id][:player_id]

    player_id = @clients[client_id][:player_id]
    username = @clients[client_id][:username]
    pokemon_data = data[:pokemon]

    if pokemon_data
      # ANTI-CHEAT: Validate Pokemon data before accepting
      if pokemon_data.is_a?(Array)
        pokemon_data.each_with_index do |pkmn, index|
          validation = validate_pokemon_data(pkmn)
          unless validation[:valid]
            @logger.warn "[POKEMON-CHECK] #{username} - Pokemon ##{index + 1}: #{validation[:error]}"
            ban_cheater(client_id, "Invalid Pokemon data: #{validation[:error]}")
            return
          end
        end
      else
        validation = validate_pokemon_data(pokemon_data)
        unless validation[:valid]
          @logger.warn "[POKEMON-CHECK] #{username}: #{validation[:error]}"
          ban_cheater(client_id, "Invalid Pokemon data: #{validation[:error]}")
          return
        end
      end

      save_player_pokemon(player_id, pokemon_data)
      @player_data[client_id][:pokemon] = pokemon_data if @player_data[client_id]
      @logger.debug "[POKEMON-CHECK] #{username}: All Pokemon data valid"
    end
  end

  def handle_save_data(client_id, data)
    return unless @clients[client_id][:player_id]

    player_id = @clients[client_id][:player_id]
    username = @clients[client_id][:username]

    # Debug: Log what data fields are received
    received_fields = data.keys.map(&:to_s).join(', ')
    @logger.info "[SAVE DEBUG] Received save_data from #{username}: fields=[#{received_fields}]"
    if data.has_key?(:money) || data.has_key?('money')
      @logger.info "[SAVE DEBUG] Money field present: #{data[:money] || data['money']}"
    else
      @logger.info "[SAVE DEBUG] NO money field in save_data!"
    end

    # Save bag data
    if data[:bag]
      save_player_bag(player_id, data[:bag])
      @player_data[client_id][:bag] = data[:bag] if @player_data[client_id]
      @logger.info "Saved bag for #{username}: #{data[:bag].size} items"
    end

    # Save Pokemon data
    if data[:pokemon]
      save_player_pokemon(player_id, data[:pokemon])
      @player_data[client_id][:pokemon] = data[:pokemon] if @player_data[client_id]
      @logger.info "Saved Pokemon for #{username}: #{data[:pokemon].size} Pokemon"
    end

    # Save PC boxes data
    if data[:pc_boxes]
      save_player_pc_boxes(player_id, data[:pc_boxes])
      @player_data[client_id][:pc_boxes] = data[:pc_boxes] if @player_data[client_id]
      total_pc_pokemon = data[:pc_boxes].sum { |box| (box[:pokemon] || box['pokemon'] || []).size }
      @logger.info "Saved PC boxes for #{username}: #{data[:pc_boxes].size} boxes with #{total_pc_pokemon} Pokemon"
    end

    # Save money from client (with validation)
    if data.has_key?(:money) || data.has_key?('money')
      money = (data[:money] || data['money'] || 3000).to_i
      # Basic validation - money should be non-negative and not exceed max
      if money >= 0 && money <= ServerAntiCheat::MAX_MONEY
        # Only save if different from current value (prevents spam saves)
        current_money = @player_data[client_id] ? (@player_data[client_id][:money] || 0) : 0
        if money != current_money
          update_player_money(player_id, money)
          @player_data[client_id][:money] = money if @player_data[client_id]
          @logger.info "Saved money for #{username}: $#{money} (was $#{current_money})"
        end
      else
        @logger.warn "Invalid money value from #{username}: #{money}"
      end
    end

    # Save badge count from client
    if data.has_key?(:badge_count) || data.has_key?('badge_count')
      badge_count = (data[:badge_count] || data['badge_count'] || 0).to_i
      if badge_count >= 0 && badge_count <= 16  # Max 16 badges reasonable
        update_player_badge_count(player_id, badge_count)
        @player_data[client_id][:badge_count] = badge_count if @player_data[client_id]
        @logger.info "Saved badges for #{username}: #{badge_count}"
      end
    end

    # Save running shoes status
    if data.has_key?(:has_running_shoes) || data.has_key?('has_running_shoes')
      has_running_shoes = data[:has_running_shoes] || data['has_running_shoes'] || 0
      save_running_shoes(player_id, has_running_shoes)
      @logger.info "Saved running shoes for #{username}: #{has_running_shoes == 1 ? 'YES' : 'NO'}"
    end

    # Save game switches (event flags)
    if data.has_key?(:switches) || data.has_key?('switches')
      switches_data = data[:switches] || data['switches'] || {}
      save_switches(player_id, switches_data)
      @logger.info "Saved switches for #{username}: #{switches_data.size} switches"
    end

    # Save game variables
    if data.has_key?(:variables) || data.has_key?('variables')
      variables_data = data[:variables] || data['variables'] || {}
      save_variables(player_id, variables_data)
      @logger.info "Saved variables for #{username}: #{variables_data.size} variables"
    end

    # Save self switches (per-event flags)
    if data.has_key?(:self_switches) || data.has_key?('self_switches')
      self_switches_data = data[:self_switches] || data['self_switches'] || {}
      save_self_switches(player_id, self_switches_data)
      @logger.info "Saved self_switches for #{username}: #{self_switches_data.size} self switches"
    end

    # Save Pokedex data (for trainer card display)
    if data.has_key?(:pokedex) || data.has_key?('pokedex')
      pokedex_data = data[:pokedex] || data['pokedex'] || {}
      save_pokedex(player_id, pokedex_data)
      @player_data[client_id][:pokedex] = pokedex_data if @player_data[client_id]
      @logger.info "Saved Pokedex for #{username}: #{pokedex_data.size} entries"
    end
  end


  def handle_daycare_update(client_id, data)
    return unless @clients[client_id][:player_id]

    player_id = @clients[client_id][:player_id]
    username = @clients[client_id][:username]

    daycare_data = data[:daycare] || data['daycare']
    if daycare_data
      save_daycare(player_id, daycare_data)
      @player_data[client_id][:daycare] = daycare_data if @player_data[client_id]
      slots_count = (daycare_data[:slots] || daycare_data['slots'] || []).size
      @logger.info "Saved daycare for #{username}: #{slots_count} Pokemon"
    end
  end
  def handle_chat_message(client_id, data)
    return unless @clients[client_id][:username]

    username = @clients[client_id][:username]
    message = data[:message]
    player_id = @clients[client_id][:player_id]

    # Check if player is muted
    if is_muted?(player_id)
      send_server_message(client_id, "You are muted and cannot send messages.")
      return
    end

    # Check if message is a command (starts with /)
    if message.start_with?('/')
      handle_command(client_id, message)
      return
    end

    @logger.info "Chat from #{username}: #{message}"

    # Get player permission for chat prefix
    permission = get_player_permission(player_id)

    # Broadcast to all players with permission level
    broadcast({
      type: "chat_message",
      data: {
        username: username,
        message: message,
        timestamp: Time.now.to_f,
        permission: permission
      }
    })
  end

  def handle_follower_update(client_id, data)
    return unless @clients[client_id] && @player_data[client_id]

    player_id = @clients[client_id][:player_id]
    follower = data[:follower]

    # Store follower data for this player
    @player_data[client_id][:follower] = follower

    # Get current map
    current_map = @player_data[client_id][:map_id]

    # Broadcast to other players on the same map
    broadcast_to_map(current_map, {
      type: "follower_update",
      data: {
        player_id: player_id,
        follower: follower
      }
    }, except_client: client_id)

    @logger.info "Player #{player_id} follower updated: #{follower ? follower['species'] || follower[:species] : 'none'}" if follower
  end

  def handle_check_item(client_id, data)
    return unless @clients[client_id][:player_id]

    player_id = @clients[client_id][:player_id]
    map_id = data[:map_id]
    event_id = data[:event_id]

    collected = has_collected_item?(player_id, map_id, event_id)

    send_to_client(client_id, {
      type: "item_check_response",
      data: {
        map_id: map_id,
        event_id: event_id,
        collected: collected
      }
    })
  end

  def handle_collect_item(client_id, data)
    return unless @clients[client_id][:player_id]

    player_id = @clients[client_id][:player_id]
    username = @clients[client_id][:username]
    map_id = data[:map_id]
    event_id = data[:event_id]

    success = mark_item_collected(player_id, map_id, event_id)

    send_to_client(client_id, {
      type: "item_collected_response",
      data: {
        map_id: map_id,
        event_id: event_id,
        success: success
      }
    })

    @logger.info "#{username} collected item: Map #{map_id}, Event #{event_id}"
  end

  def handle_get_collected_items(client_id, data)
    return unless @clients[client_id][:player_id]

    player_id = @clients[client_id][:player_id]
    map_id = data[:map_id]

    collected_events = get_collected_items(player_id, map_id)

    send_to_client(client_id, {
      type: "collected_items_response",
      data: {
        map_id: map_id,
        event_ids: collected_events
      }
    })
  end

  def handle_battle_request(client_id, data)
    # CRITICAL: Store client references upfront to prevent race condition
    from_client = @clients[client_id]
    return unless from_client && from_client[:username]

    from_username = from_client[:username]
    target_id = data[:target_id]
    battle_format = data[:format] || "Single Battle"

    # Find target client (store reference to prevent race condition)
    target_client = @clients[target_id]
    unless target_client && target_client[:username]
      send_error(client_id, "Target player not found")
      return
    end

    @logger.info "Battle request: #{from_username} -> #{target_client[:username]} (#{battle_format})"

    # Send battle request to target player
    send_to_client(target_id, {
      type: "battle_request",
      data: {
        from_id: client_id,
        from_username: from_username,
        format: battle_format
      }
    })

    # Confirm to requester
    send_to_client(client_id, {
      type: "battle_request_sent",
      data: {
        target_id: target_id,
        target_username: target_client[:username]
      }
    })
  end

  def handle_battle_accept(client_id, data)
    return unless @clients[client_id][:username]
    return unless @player_data[client_id]

    accepter_username = @clients[client_id][:username]
    requester_id = data[:from_id]
    battle_format = data[:format] || :single

    requester_client = @clients[requester_id]
    unless requester_client && requester_client[:username]
      send_error(client_id, "Requester not found")
      return
    end

    @logger.info "[BATTLE SYNC] #{accepter_username} accepted #{requester_client[:username]}'s request"

    # Create battle session
    battle_id = @next_battle_id
    @next_battle_id += 1

    # Generate synchronized RNG seed
    rng_seed = Random.rand(1_000_000_000)

    # Store battle session
    @active_battles[battle_id] = {
      id: battle_id,
      player1_id: requester_id,
      player2_id: client_id,
      format: battle_format,
      rng_seed: rng_seed,
      choices: {},
      states: {},
      turn: 0,
      started_at: Time.now
    }

    @logger.info "[BATTLE SYNC] Created battle ##{battle_id}, seed: #{rng_seed}"

    # Send synchronized battle start to requester
    send_to_client(requester_id, {
      type: "battle_start_sync",
      data: {
        battle_id: battle_id,
        opponent_id: client_id,
        opponent_username: accepter_username,
        format: battle_format,
        opponent_party: @player_data[client_id][:pokemon] || [],
        rng_seed: rng_seed,
        is_host: true
      }
    })

    # Send synchronized battle start to accepter
    send_to_client(client_id, {
      type: "battle_start_sync",
      data: {
        battle_id: battle_id,
        opponent_id: requester_id,
        opponent_username: requester_client[:username],
        format: battle_format,
        opponent_party: @player_data[requester_id][:pokemon] || [],
        rng_seed: rng_seed,
        is_host: false
      }
    })
  end

  def handle_battle_decline(client_id, data)
    return unless @clients[client_id][:username]

    decliner_username = @clients[client_id][:username]
    requester_id = data[:from_id]

    requester_client = @clients[requester_id]
    unless requester_client
      return
    end

    @logger.info "Battle declined: #{decliner_username} declined #{requester_client[:username]}'s request"

    # Notify requester
    send_to_client(requester_id, {
      type: "battle_declined",
      data: {
        opponent_id: client_id,
        opponent_username: decliner_username
      }
    })
  end

  def handle_battle_party_request(client_id, data)
    return unless @player_data[client_id]

    target_id = data[:target_id]

    unless @player_data[target_id]
      send_error(client_id, "Target player not found")
      return
    end

    # Send target's party data to requester
    send_to_client(client_id, {
      type: "battle_party_response",
      data: {
        player_id: target_id,
        party: @player_data[target_id][:pokemon] || []
      }
    })
  end

  def handle_trade_offer(client_id, data)
    @logger.info "[SERVER DEBUG] handle_trade_offer ENTRY - client_id: #{client_id}, data: #{!data.nil?}"

    # CRITICAL: Validate data exists
    unless data
      @logger.warn "[SERVER DEBUG] handle_trade_offer - data is nil!"
      return
    end

    # CRITICAL: Store client references upfront to prevent race condition
    from_client = @clients[client_id]
    from_player = @player_data[client_id]

    @logger.info "[SERVER DEBUG] handle_trade_offer - from_client: #{!from_client.nil?}, from_player: #{!from_player.nil?}"

    # Check if sender client exists
    unless from_client && from_client[:username]
      @logger.warn "[SERVER DEBUG] handle_trade_offer - from_client invalid!"
      return
    end
    unless from_player
      @logger.warn "[SERVER DEBUG] handle_trade_offer - from_player is nil!"
      return
    end

    from_username = from_client[:username]
    target_id = data[:target_id] || data['target_id']
    offered_pokemon = data[:pokemon] || data['pokemon']

    @logger.info "[SERVER DEBUG] handle_trade_offer called"
    @logger.info "[SERVER DEBUG] from client_id: #{client_id}, username: #{from_username}"
    @logger.info "[SERVER DEBUG] target_id: #{target_id}"

    # Find target client (store reference to prevent race condition)
    target_client = @clients[target_id]
    unless target_client && target_client[:username]
      @logger.warn "[SERVER DEBUG] Target client not found or offline"
      send_error(client_id, "Target player not found or offline")
      return
    end

    trade_id = data[:trade_id] || data['trade_id']
    @logger.info "[SERVER DEBUG] Trade offer: #{from_username} -> #{target_client[:username]} (trade_id: #{trade_id})"

    # Send trade offer to target player
    @logger.info "[SERVER DEBUG] Sending trade_offer message to client #{target_id}"
    send_to_client(target_id, {
      type: "trade_offer",
      data: {
        from_id: client_id,
        from_username: from_username,
        pokemon: offered_pokemon,
        trade_id: trade_id
      }
    })
    @logger.info "[SERVER DEBUG] Trade offer message sent successfully"

    # Confirm to requester
    send_to_client(client_id, {
      type: "trade_offer_sent",
      data: {
        target_id: target_id,
        target_username: target_client[:username]
      }
    })
  end

  def handle_trade_accept(client_id, data)
    @logger.info "[TRADE ACCEPT] Received from client #{client_id}"
    @logger.info "[TRADE ACCEPT] Data present: #{!data.nil?}"

    # CRITICAL: Validate data exists
    unless data
      @logger.warn "[TRADE ACCEPT] Data is nil! Returning."
      return
    end

    @logger.info "[TRADE ACCEPT] Data keys: #{data.keys.inspect}"

    # CRITICAL: Store client references upfront to prevent race condition
    # (client might disconnect between checks and usage)
    accepter_client = @clients[client_id]
    accepter_player = @player_data[client_id]

    # Check if accepter client exists
    return unless accepter_client && accepter_client[:username]
    return unless accepter_player

    accepter_username = accepter_client[:username]
    @logger.info "[TRADE ACCEPT] Processing for #{accepter_username}"
    accepter_player_id = accepter_client[:player_id]
    return unless accepter_player_id  # Safety check

    requester_id = data[:from_id] || data['from_id']
    offered_pokemon = data[:their_pokemon] || data['their_pokemon']
    requested_pokemon = data[:my_pokemon] || data['my_pokemon']

    # Check if requester still exists (store reference to prevent race condition)
    requester_client = @clients[requester_id]
    requester_player = @player_data[requester_id]

    # Debug logging to identify missing data
    @logger.info "[TRADE ACCEPT] Requester ID: #{requester_id}"
    @logger.info "[TRADE ACCEPT] Requester client exists: #{!requester_client.nil?}"
    @logger.info "[TRADE ACCEPT] Requester client username: #{requester_client&.[](:username)}"
    @logger.info "[TRADE ACCEPT] Requester player data exists: #{!requester_player.nil?}"
    @logger.info "[TRADE ACCEPT] All clients: #{@clients.keys.inspect}"
    @logger.info "[TRADE ACCEPT] All player_data: #{@player_data.keys.inspect}"

    unless requester_client && requester_client[:username] && requester_player
      @logger.warn "[TRADE ACCEPT] Trade partner check failed!"
      send_error(client_id, "Trade partner disconnected")
      return
    end

    requester_player_id = requester_client[:player_id]
    return unless requester_player_id  # Safety check

    @logger.info "Trade accepted: #{accepter_username} <-> #{requester_client[:username]}"

    # Log Pokemon data for debugging
    @logger.info "[TRADE] P1 (#{requester_client[:username]}) offered pokemon keys: #{offered_pokemon&.keys&.inspect}"
    @logger.info "[TRADE] P2 (#{accepter_username}) offered pokemon keys: #{requested_pokemon&.keys&.inspect}"
    @logger.info "[TRADE] P1 offered pokemon personalID: #{offered_pokemon[:personalID] || offered_pokemon['personalID'] || 'MISSING'}"
    @logger.info "[TRADE] P2 offered pokemon personalID: #{requested_pokemon[:personalID] || requested_pokemon['personalID'] || 'MISSING'}"

    # Update both players' Pokemon in memory (use stored references)
    # Remove traded Pokemon from each player's party
    accepter_party = accepter_player[:pokemon] || []
    requester_party = requester_player[:pokemon] || []

    # Find and swap Pokemon (this is simplified - real implementation should verify positions)
    # For now, we'll trust the client data and just update the parties

    # Add traded Pokemon to each party
    # The client will handle removing from their own party before sending

    # Notify requester of successful trade
    @logger.info "[TRADE] Sending trade_accepted to P1 (client #{requester_id}, #{requester_client[:username]})"
    send_to_client(requester_id, {
      type: "trade_accepted",
      data: {
        opponent_id: client_id,
        opponent_username: accepter_username,
        received_pokemon: requested_pokemon,
        given_pokemon: offered_pokemon
      }
    })
    @logger.info "[TRADE] Sent trade_accepted to P1"

    # Notify accepter of successful trade
    @logger.info "[TRADE] Sending trade_complete to P2 (client #{client_id}, #{accepter_username})"
    send_to_client(client_id, {
      type: "trade_complete",
      data: {
        opponent_id: requester_id,
        opponent_username: requester_client[:username],
        received_pokemon: offered_pokemon,
        given_pokemon: requested_pokemon
      }
    })
    @logger.info "[TRADE] Sent trade_complete to P2"

    # Both players should now save their updated Pokemon data
    # This will happen automatically when they send pokemon_update
  end

  def handle_trade_decline(client_id, data)
    return unless @clients[client_id][:username]

    decliner_username = @clients[client_id][:username]
    requester_id = data[:from_id]

    requester_client = @clients[requester_id]
    unless requester_client
      return
    end

    @logger.info "Trade declined: #{decliner_username} declined #{requester_client[:username]}'s offer"

    # Notify requester
    send_to_client(requester_id, {
      type: "trade_declined",
      data: {
        opponent_id: client_id,
        opponent_username: decliner_username
      }
    })
  end

  def handle_trade_complete_confirmation(client_id, data)
    # Client is confirming their trade animation finished
    # We don't need to do anything server-side, just acknowledge it
    return unless data

    client = @clients[client_id]
    return unless client && client[:username]

    trade_id = data[:trade_id] || data['trade_id']
    @logger.info "Trade completion confirmed by #{client[:username]} (trade_id: #{trade_id})"
  end

  def send_player_list(client_id)
    players = @player_data.values.map do |p|
      p.dup
    end

    send_to_client(client_id, {
      type: "player_list",
      data: {
        players: players
      }
    })
  end

  def broadcast_player_joined(client_id)
    return unless @player_data[client_id]

    broadcast_except(client_id, {
      type: "player_joined",
      data: @player_data[client_id]
    })
  end

  def broadcast_position_update(client_id, target_map_id = nil)
    return unless @player_data[client_id]

    player = @player_data[client_id]
    # Use target_map_id if provided (for map changes), otherwise use player's current map
    map_id = target_map_id || player[:map_id]

    # Only send to players on the target map
    @clients.each do |other_id, other_info|
      next if other_id == client_id
      next unless @player_data[other_id]
      next unless @player_data[other_id][:map_id] == map_id

      send_to_client(other_id, {
        type: "position_update",
        data: player
      })
    end
  end

  def disconnect_client(client_id)
    client_info = @clients[client_id]
    return unless client_info

    username = client_info[:username] || "Anonymous"
    @logger.info "Client ##{client_id} (#{username}) disconnected"

    # CRITICAL: Handle active battles - auto-forfeit on disconnect
    @active_battles.each do |battle_id, battle|
      if battle[:player1_id] == client_id || battle[:player2_id] == client_id
        # Player disconnected during battle - they forfeit
        opponent_id = (battle[:player1_id] == client_id) ? battle[:player2_id] : battle[:player1_id]
        opponent_client = @clients[opponent_id]

        if opponent_client && opponent_client[:username]
          @logger.info "[BATTLE DISCONNECT] #{username} disconnected from battle ##{battle_id} - auto-forfeit"

          # Notify opponent that they won by forfeit
          send_to_client(opponent_id, {
            type: "battle_forfeit",
            data: {
              battle_id: battle_id,
              forfeiter_username: username,
              message: "#{username} disconnected - you win!"
            }
          })

          # Process battle result (opponent wins, disconnected player loses)
          if opponent_client[:player_id] && client_info[:player_id]
            begin
              penalty = ServerConfig::DISCONNECT_ELO_PENALTY
              update_battle_stats(opponent_client[:player_id], get_player_elo(opponent_client[:player_id]) + penalty, true)
              update_battle_stats(client_info[:player_id], get_player_elo(client_info[:player_id]) - penalty, false)
              @logger.info "[BATTLE DISCONNECT] Updated ELO: #{opponent_client[:username]} +#{penalty}, #{username} -#{penalty}"
            rescue => e
              @logger.error "[BATTLE DISCONNECT] Failed to update ELO: #{e.message}"
            end
          end
        end

        # Remove battle from active battles
        @active_battles.delete(battle_id)
        @logger.info "[BATTLE DISCONNECT] Removed battle ##{battle_id} from active battles"
      end
    end

    # CRITICAL: Clean up any active trades
    cleanup_player_trades_v2(client_id)

    # Save all player data to database
    if @player_data[client_id] && client_info[:player_id]
      player = @player_data[client_id]
      player_id = client_info[:player_id]

      # Save position
      save_player_position(
        player_id,
        player[:map_id],
        player[:x],
        player[:y],
        player[:direction]
      )
      @logger.info "Saved position for #{username} (#{player[:map_id]}, #{player[:x]}, #{player[:y]})"

      # Save bag
      if player[:bag] && player[:bag].any?
        save_player_bag(player_id, player[:bag])
      end

      # Save Pokemon
      if player[:pokemon] && player[:pokemon].any?
        save_player_pokemon(player_id, player[:pokemon])
      end

      # Save PC boxes
      if player[:pc_boxes] && player[:pc_boxes].any?
        save_player_pc_boxes(player_id, player[:pc_boxes])
        total_pc_pokemon = player[:pc_boxes].sum { |box| (box[:pokemon] || box['pokemon'] || []).size }
        @logger.info "Saved PC boxes for #{username} on disconnect: #{player[:pc_boxes].size} boxes with #{total_pc_pokemon} Pokemon"
      end

      # Update playtime
      update_player_playtime(player_id)
    end

    # Broadcast player left
    if client_info[:username]
      broadcast_except(client_id, {
        type: "player_left",
        data: {
          id: client_id,
          username: username
        }
      })
    end

    client_info[:socket].close rescue nil
    @clients.delete(client_id)
    @player_data.delete(client_id)
  end

  def send_to_client(client_id, message)
    client_info = @clients[client_id]
    unless client_info
      @logger.warn "[SERVER DEBUG] send_to_client: client #{client_id} not found in @clients"
      return
    end

    begin
      json = JSON.generate(message) + "\n"
      @logger.info "[SERVER DEBUG] Sending to client #{client_id} (#{client_info[:username]}): type=#{message[:type]}"
      client_info[:socket].puts(json)
      @logger.info "[SERVER DEBUG] Message sent successfully to client #{client_id}"
    rescue => e
      @logger.error "Failed to send to client ##{client_id}: #{e.message}"
      disconnect_client(client_id)
    end
  end

  def broadcast(message)
    @clients.keys.each do |client_id|
      send_to_client(client_id, message)
    end
  end

  def broadcast_except(excluded_client_id, message)
    @clients.keys.each do |client_id|
      next if client_id == excluded_client_id
      send_to_client(client_id, message)
    end
  end

  def send_error(client_id, error_message)
    send_to_client(client_id, {
      type: "error",
      data: {
        message: error_message
      }
    })
  end

  def heartbeat_loop
    loop do
      sleep 30

      now = Time.now
      @clients.each do |client_id, info|
        if now - info[:last_heartbeat] > ServerConfig::TIMEOUT_SECONDS
          @logger.warn "Client ##{client_id} timed out"
          disconnect_client(client_id)
        end
      end

      # Clean up expired trade sessions
      cleanup_expired_trade_sessions_v2
    end
  end

  def start_http_server
    require 'webrick'
    require 'zip'

    http_port = @port + 1
    @logger.info "Starting HTTP server on port #{http_port} for auto-updates"

    server = WEBrick::HTTPServer.new(
      Port: http_port,
      Logger: WEBrick::Log.new(File.open(File::NULL, 'w')),
      AccessLog: []
    )

    server.mount_proc '/version' do |req, res|
      res['Content-Type'] = 'application/json'
      # Include update info for enhanced auto-updater
      update_info = get_update_info rescue {}
      res.body = JSON.generate({
        version: VERSION,
        min_client_version: MIN_CLIENT_VERSION,
        update_info: update_info
      })
    end

    # Update manifest endpoint for detailed file list
    server.mount_proc '/update_manifest' do |req, res|
      res['Content-Type'] = 'application/json'
      begin
        manifest = generate_update_manifest
        res.body = JSON.generate(manifest)
      rescue => e
        @logger.error "Failed to generate update manifest: #{e.message}"
        res.status = 500
        res.body = JSON.generate({error: e.message})
      end
    end

    # Individual file download endpoint
    server.mount_proc '/download_file' do |req, res|
      begin
        file_path = req.query['path']
        if file_path && !file_path.include?('..') # Prevent directory traversal
          full_path = File.join(Dir.pwd, file_path)
          if File.exist?(full_path) && File.file?(full_path)
            res['Content-Type'] = 'application/octet-stream'
            res.body = File.read(full_path, mode: 'rb')
          else
            res.status = 404
            res.body = 'File not found'
          end
        else
          res.status = 400
          res.body = 'Invalid path'
        end
      rescue => e
        res.status = 500
        res.body = 'Internal Server Error'
      end
    end

    server.mount_proc '/download_plugin' do |req, res|
      begin
        zip_path = create_plugin_zip
        res['Content-Type'] = 'application/zip'
        res['Content-Disposition'] = 'attachment; filename="Multiplayer_Update.zip"'
        res.body = File.read(zip_path, mode: 'rb')
        File.delete(zip_path) if File.exist?(zip_path)
      rescue => e
        @logger.error "Failed to create plugin zip: #{e.message}"
        res.status = 500
        res.body = 'Internal Server Error'
      end
    end

    # Tarball download endpoint for client auto-updater
    server.mount_proc '/download_update' do |req, res|
      begin
        @logger.info "Client requested update tarball"
        tarball_path = create_plugin_tarball
        res['Content-Type'] = 'application/gzip'
        res['Content-Disposition'] = 'attachment; filename="multiplayer_update.tar.gz"'
        res.body = File.read(tarball_path, mode: 'rb')
        File.delete(tarball_path) if File.exist?(tarball_path)
        @logger.info "Sent update tarball (#{res.body.bytesize} bytes)"
      rescue => e
        @logger.error "Failed to create update tarball: #{e.message}"
        res.status = 500
        res.body = 'Internal Server Error'
      end
    end

    trap('INT') { server.shutdown }
    server.start
  rescue => e
    @logger.error "HTTP server error: #{e.message}"
    @logger.error e.backtrace.join("\n")
  end

  def create_plugin_zip
    require 'zip'
    require 'fileutils'

    zip_path = "/tmp/Multiplayer_Update_#{Time.now.to_i}.zip"

    plugin_dir = File.join(Dir.pwd, 'Plugins', 'Multiplayer')
    unless Dir.exist?(plugin_dir)
      plugin_dir = File.join(File.dirname(__FILE__), 'Plugins', 'Multiplayer')
    end

    Zip::File.open(zip_path, create: true) do |zipfile|
      Dir[File.join(plugin_dir, '**', '*')].each do |file|
        next if File.directory?(file)
        next if file.include?('_Backup_')

        relative_path = file.sub(plugin_dir + '/', '')
        zipfile.add("Multiplayer/#{relative_path}", file)
      end
    end

    @logger.info "Created plugin zip: #{zip_path}"
    return zip_path
  end

  def create_plugin_tarball
    require 'rubygems/package' # Standard Ruby library for Tar
    require 'zlib'             # Standard Ruby library for Gzip

    # 1. Create a local temp folder without using FileUtils or tmpdir
    local_temp_dir = File.join(Dir.pwd, "temp_downloads")
    Dir.mkdir(local_temp_dir) unless File.exist?(local_temp_dir)

    # 2. Generate unique filename
    timestamp = Time.now.to_i
    tarball_path = File.join(local_temp_dir, "multiplayer_update_#{timestamp}.tar.gz")

    @logger.info "Generating update tarball at: #{tarball_path}..."

    # 3. Create the Tar Gzip file
    File.open(tarball_path, 'wb') do |file|
      Zlib::GzipWriter.wrap(file) do |gzip|
        Gem::Package::TarWriter.new(gzip) do |tar|
          
          # Iterate through the directories defined in UPDATE_DIRECTORIES constant
          UPDATE_DIRECTORIES.each do |target_dir|
            full_target_path = File.join(Dir.pwd, target_dir)
            
            # Skip if the configured directory doesn't exist
            next unless Dir.exist?(full_target_path)

            # Recursive search using Dir.glob (Native Ruby)
            # This replaces Find.find and FileUtils
            files = Dir.glob(File.join(full_target_path, "**", "*"))

            files.each do |file_path|
              # Skip if it is a directory (tar entries handle paths implicitly)
              next if File.directory?(file_path)
              
              # Skip backup files
              next if file_path.include?('_Backup_')
              
              # Check for skipped extensions (executables, saves, etc.)
              ext = File.extname(file_path).downcase
              next if SKIP_EXTENSIONS.any? { |skip| ext == skip }
              next if SKIP_EXTENSIONS.any? { |skip| file_path.downcase.end_with?(skip) }

              # Calculate path relative to the server root
              # This ensures structure inside the zip is "Graphics/..." not "C:/Users/..."
              relative_path = file_path.sub(Dir.pwd + "/", "")
              
              # Read file stats and content
              stat = File.stat(file_path)
              content = File.read(file_path, mode: 'rb')

              # Add file to the tarball
              # 0o100644 is standard file permission, stat.mode keeps original permissions
              tar.add_file_simple(relative_path, stat.mode, content.bytesize) do |io|
                io.write(content)
              end
            end
          end
        end
      end
    end

    @logger.info "Created update tarball successfully: #{File.size(tarball_path)} bytes"
    return tarball_path

  rescue => e
    @logger.error "Failed to create plugin tarball: #{e.message}"
    @logger.error e.backtrace.join("\n")
    raise e # Re-raise so the HTTP handler knows it failed
  end
  # Get basic update info for /version endpoint
  def get_update_info
    changelog = "Bug fixes and performance improvements"

    # Try to read changelog from file
    changelog_path = File.join(Dir.pwd, 'CHANGELOG.txt')
    if File.exist?(changelog_path)
      changelog = File.read(changelog_path).lines.first(3).join.strip rescue changelog
    end

    # Calculate total update size
    total_size = calculate_update_size

    {
      changelog: changelog,
      file_size: total_size,
      file_count: count_update_files
    }
  end

  # Directories to include in auto-updates
  UPDATE_DIRECTORIES = [
    'Plugins/Multiplayer',   # Multiplayer plugin files
    'Scripts',               # Core game scripts
    'Graphics',              # Graphics assets (sprites, UI, etc.)
    'Audio',                 # Audio assets (BGM, SE, ME)
    'PBS',                   # Pokemon data files
    'Data'                   # Game data (maps, events, etc.)
  ]

  # File extensions to SKIP during updates (binary/compiled files)
  SKIP_EXTENSIONS = ['.rxdata', '.dat', '.dll', '.exe', '.so']

  # Generate detailed update manifest for individual file downloads
  def generate_update_manifest
    files = []
    total_size = 0
    # Use PUBLIC_HOST from config for download URLs (must be the server's public IP)
    public_host = defined?(ServerConfig::PUBLIC_HOST) ? ServerConfig::PUBLIC_HOST : "localhost"
    base_url = "http://#{public_host}:#{@port + 1}/download_file"

    UPDATE_DIRECTORIES.each do |dir|
      dir_path = File.join(Dir.pwd, dir)
      next unless Dir.exist?(dir_path)

      Dir[File.join(dir_path, '**', '*')].each do |file|
        next if File.directory?(file)
        next if file.include?('_Backup_')
        next if SKIP_EXTENSIONS.any? { |ext| file.downcase.end_with?(ext) }

        relative_path = file.sub(Dir.pwd + '/', '')
        file_size = File.size(file)
        total_size += file_size

        files << {
          path: relative_path,
          url: "#{base_url}?path=#{URI.encode_www_form_component(relative_path)}",
          size: file_size,
          md5: Digest::MD5.file(file).hexdigest
        }
      end
    end

    {
      version: VERSION,
      files: files,
      total_size: total_size
    }
  end

  def calculate_update_size
    total = 0
    UPDATE_DIRECTORIES.each do |dir|
      dir_path = File.join(Dir.pwd, dir)
      next unless Dir.exist?(dir_path)

      Dir[File.join(dir_path, '**', '*')].each do |file|
        next if File.directory?(file)
        next if file.include?('_Backup_')
        next if SKIP_EXTENSIONS.any? { |ext| file.downcase.end_with?(ext) }
        total += File.size(file) rescue 0
      end
    end
    total
  end

  def count_update_files
    count = 0
    UPDATE_DIRECTORIES.each do |dir|
      dir_path = File.join(Dir.pwd, dir)
      next unless Dir.exist?(dir_path)

      Dir[File.join(dir_path, '**', '*')].each do |file|
        next if File.directory?(file)
        next if file.include?('_Backup_')
        next if SKIP_EXTENSIONS.any? { |ext| file.downcase.end_with?(ext) }
        count += 1
      end
    end
    count
  end

  # ============================================================================
  # Synchronized Battle Methods
  # ============================================================================

  def handle_battle_choice(client_id, data)
    battle_id = data[:battle_id] || data['battle_id']
    opponent_id = data[:opponent_id] || data['opponent_id']
    turn = data[:turn] || data['turn']
    choice = data[:choice] || data['choice']

    battle = @active_battles[battle_id]
    unless battle
      @logger.warn "[BATTLE SYNC] Choice for unknown battle ##{battle_id}"
      return
    end

    # Store this player's choice
    battle[:choices][client_id] = {
      turn: turn,
      choice: choice,
      received_at: Time.now
    }

    @logger.info "[BATTLE SYNC] Battle ##{battle_id}: Player #{client_id} submitted choice for turn #{turn}"

    # Check if both players have submitted choices
    if battle[:choices][battle[:player1_id]] && battle[:choices][battle[:player2_id]]
      # Both choices received - broadcast to both players
      @logger.info "[BATTLE SYNC] Battle ##{battle_id}: Both choices received for turn #{turn}"

      send_to_client(battle[:player1_id], {
        type: "battle_opponent_choice",
        data: {
          battle_id: battle_id,
          turn: turn,
          choice: battle[:choices][battle[:player2_id]][:choice]
        }
      })

      send_to_client(battle[:player2_id], {
        type: "battle_opponent_choice",
        data: {
          battle_id: battle_id,
          turn: turn,
          choice: battle[:choices][battle[:player1_id]][:choice]
        }
      })

      # Clear choices for next turn
      battle[:choices] = {}
      battle[:turn] = turn + 1
    end
  end

  def handle_battle_state(client_id, data)
    battle_id = data[:battle_id] || data['battle_id']
    state = data[:state] || data['state']

    battle = @active_battles[battle_id]
    return unless battle

    # Store state from this player
    battle[:states][client_id] = state

    # If both players sent states, validate
    if battle[:states][battle[:player1_id]] && battle[:states][battle[:player2_id]]
      state1 = battle[:states][battle[:player1_id]]
      state2 = battle[:states][battle[:player2_id]]

      # Validate states match
      if states_match?(state1, state2)
        @logger.info "[BATTLE SYNC] Battle ##{battle_id} turn #{state1[:turn]}: States validated"
      else
        @logger.error "[BATTLE SYNC] Battle ##{battle_id}: STATE MISMATCH DETECTED!"
        @logger.error "State 1: #{state1.inspect}"
        @logger.error "State 2: #{state2.inspect}"

        # Disconnect both players - possible cheating
        send_error(battle[:player1_id], "Battle state desync - battle cancelled")
        send_error(battle[:player2_id], "Battle state desync - battle cancelled")
        end_battle(battle_id)
      end

      # Clear states
      battle[:states] = {}
    end
  end

  def states_match?(state1, state2)
    return false if state1[:turn] != state2[:turn]
    return false if state1[:battlers].length != state2[:battlers].length

    state1[:battlers].each do |b1|
      b2 = state2[:battlers].find { |b| b[:index] == b1[:index] }
      return false unless b2
      return false if b1[:hp] != b2[:hp]
      return false if b1[:status] != b2[:status]
    end

    true
  end

  def end_battle(battle_id)
    @active_battles.delete(battle_id)
    @logger.info "[BATTLE SYNC] Battle ##{battle_id} ended"
  end

  def handle_battle_complete(client_id, data)
    winner_id = data[:winner_id] || data['winner_id']
    loser_id = data[:loser_id] || data['loser_id']

    @logger.info "[BATTLE COMPLETE] Winner: ##{winner_id}, Loser: ##{loser_id}"

    # Find the battle between these two players
    battle_entry = @active_battles.find do |id, b|
      (b[:player1_id] == winner_id && b[:player2_id] == loser_id) ||
      (b[:player1_id] == loser_id && b[:player2_id] == winner_id)
    end

    # If battle doesn't exist in active_battles, it was already processed - skip!
    unless battle_entry
      @logger.info "[BATTLE COMPLETE] Battle already processed, skipping duplicate"
      return
    end

    battle_id = battle_entry[0]

    # Get player IDs from client IDs
    winner_info = @clients[winner_id]
    loser_info = @clients[loser_id]

    return unless winner_info && loser_info

    winner_player_id = winner_info[:player_id]
    loser_player_id = loser_info[:player_id]

    # Calculate ELO changes
    winner_elo = get_player_elo(winner_player_id)
    loser_elo = get_player_elo(loser_player_id)

    # ELO formula with K-factor from config
    k_factor = ServerConfig::ELO_K_FACTOR
    expected_winner = 1.0 / (1.0 + 10.0 ** ((loser_elo - winner_elo) / 400.0))
    expected_loser = 1.0 / (1.0 + 10.0 ** ((winner_elo - loser_elo) / 400.0))

    winner_change = (k_factor * (1.0 - expected_winner)).round
    loser_change = (k_factor * (0.0 - expected_loser)).round

    new_winner_elo = winner_elo + winner_change
    new_loser_elo = loser_elo + loser_change

    # Update database
    update_battle_stats(winner_player_id, new_winner_elo, true)
    update_battle_stats(loser_player_id, new_loser_elo, false)

    @logger.info "[ELO] #{winner_info[:username]}: #{winner_elo} -> #{new_winner_elo} (+#{winner_change})"
    @logger.info "[ELO] #{loser_info[:username]}: #{loser_elo} -> #{new_loser_elo} (#{loser_change})"

    # Send ELO updates to both players
    send_to_client(winner_id, {
      type: "elo_update",
      data: {
        old_elo: winner_elo,
        new_elo: new_winner_elo,
        change: winner_change,
        result: "win",
        opponent: loser_info[:username]
      }
    })

    send_to_client(loser_id, {
      type: "elo_update",
      data: {
        old_elo: loser_elo,
        new_elo: new_loser_elo,
        change: loser_change,
        result: "loss",
        opponent: winner_info[:username]
      }
    })

    # Remove battle from active battles (we already have battle_id from earlier)
    end_battle(battle_id)
  end

  def handle_get_social_data(client_id, data)
    @logger.info "[SOCIAL] Client ##{client_id} requesting social data"

    # Get ALL players from database with their stats (not just online ones)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    all_players = db.execute("SELECT id, username, total_trades, wins, losses, elo FROM players ORDER BY elo DESC")

    # Build player list with online status
    player_list = all_players.map do |player|
      # Check if player is online
      online_client = @clients.find { |_, c| c[:player_id] == player['id'] }
      is_online = !online_client.nil?

      # Debug logging for online players
      if is_online
        @logger.info "[SOCIAL] Player #{player['username']} (DB ID: #{player['id']}) -> Client ID: #{online_client[0]}"
      end

      # Check if in battle
      in_battle = false
      if online_client
        in_battle = @active_battles.any? do |_, battle|
          battle[:player1_id] == online_client[0] || battle[:player2_id] == online_client[0]
        end
      end

      {
        id: online_client ? online_client[0] : nil,  # Client ID (nil if offline)
        player_id: player['id'],
        username: player['username'],
        total_trades: player['total_trades'] || 0,
        wins: player['wins'] || 0,
        losses: player['losses'] || 0,
        elo: player['elo'] || 1000,
        online: is_online,
        in_battle: in_battle
      }
    end

    db.close

    # Send player list to client
    send_to_client(client_id, {
      type: "social_data",
      data: {
        players: player_list
      }
    })

    @logger.info "[SOCIAL] Sent data for #{player_list.length} players (#{player_list.count { |p| p[:online] }} online)"
  end

  # ============================================================================
  # Starter Claim Handler (Transaction-based to prevent double starter)
  # ============================================================================

  def handle_claim_starter(client_id, data)
    return unless @clients[client_id][:player_id]

    player_id = @clients[client_id][:player_id]
    username = @clients[client_id][:username]

    # Check if player already claimed starter (atomic check-and-set)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    begin
      # Use transaction to ensure atomicity
      db.transaction do
        # Check if player has starter flag set
        result = db.execute("SELECT has_starter FROM players WHERE id = ?", [player_id]).first

        if result && result['has_starter'] == 1
          # Player already claimed starter - reject
          @logger.warn "[STARTER] Player #{username} (ID: #{player_id}) attempted to claim starter twice!"
          send_to_client(client_id, {
            type: "starter_claim_rejected",
            data: {
              message: "You already have a starter Pokemon!"
            }
          })
          db.rollback
          return
        end

        # Set has_starter flag atomically
        db.execute("UPDATE players SET has_starter = 1 WHERE id = ?", [player_id])

        @logger.info "[STARTER] Player #{username} (ID: #{player_id}) claimed starter successfully"

        # Send success response
        send_to_client(client_id, {
          type: "starter_claim_success",
          data: {
            message: "Starter claimed!"
          }
        })
      end
    rescue => e
      @logger.error "[STARTER] Error claiming starter for player #{player_id}: #{e.message}"
      send_error(client_id, "Failed to claim starter")
    ensure
      db.close
    end
  end

  def get_player_has_starter(player_id)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    result = db.execute("SELECT has_starter FROM players WHERE id = ?", [player_id]).first
    db.close

    return result ? (result['has_starter'] == 1) : false
  rescue => e
    @logger.error "Failed to get has_starter for player #{player_id}: #{e.message}"
    db.close rescue nil
    return false
  end

  # ============================================================================
  # Database Methods
  # ============================================================================

  def initialize_database
    @logger.info "Initializing database: #{@db_path}"

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    # Create players table
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS players (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_login TIMESTAMP,
        map_id INTEGER DEFAULT 3,
        x INTEGER DEFAULT 10,
        y INTEGER DEFAULT 7,
        direction INTEGER DEFAULT 2,
        has_running_shoes INTEGER DEFAULT 0
      );
    SQL

    # Add running shoes column if it doesn't exist (for existing databases)
    begin
      db.execute("ALTER TABLE players ADD COLUMN has_running_shoes INTEGER DEFAULT 0")
      @logger.info "Added has_running_shoes column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    # Add has_starter column to track if player received their starter
    begin
      db.execute("ALTER TABLE players ADD COLUMN has_starter INTEGER DEFAULT 0")
      @logger.info "Added has_starter column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    # Add battle statistics columns if they don't exist
    begin
      db.execute("ALTER TABLE players ADD COLUMN wins INTEGER DEFAULT 0")
      @logger.info "Added wins column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    begin
      db.execute("ALTER TABLE players ADD COLUMN losses INTEGER DEFAULT 0")
      @logger.info "Added losses column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    begin
      db.execute("ALTER TABLE players ADD COLUMN elo INTEGER DEFAULT 1000")
      @logger.info "Added elo column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    begin
      db.execute("ALTER TABLE players ADD COLUMN total_trades INTEGER DEFAULT 0")
      @logger.info "Added total_trades column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    # Add event persistence columns (switches, variables, self_switches)
    begin
      db.execute("ALTER TABLE players ADD COLUMN switches TEXT DEFAULT '{}'")
      @logger.info "Added switches column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    begin
      db.execute("ALTER TABLE players ADD COLUMN variables TEXT DEFAULT '{}'")
      @logger.info "Added variables column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    begin
      db.execute("ALTER TABLE players ADD COLUMN self_switches TEXT DEFAULT '{}'")
      @logger.info "Added self_switches column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    # Create bag/items table
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS player_bag (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER NOT NULL,
        item_id TEXT NOT NULL,
        quantity INTEGER DEFAULT 1,
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
      );
    SQL

    # Create Pokemon table
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS player_pokemon (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER NOT NULL,
        species TEXT NOT NULL,
        level INTEGER DEFAULT 5,
        nickname TEXT,
        hp INTEGER,
        attack INTEGER,
        defense INTEGER,
        sp_attack INTEGER,
        sp_defense INTEGER,
        speed INTEGER,
        moves TEXT,
        ability TEXT,
        nature TEXT,
        gender INTEGER,
        shiny INTEGER DEFAULT 0,
        position INTEGER,
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
      );
    SQL

    # Create collected items table (for map items each player can collect once)
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS player_collected_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER NOT NULL,
        map_id INTEGER NOT NULL,
        event_id INTEGER NOT NULL,
        collected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(player_id, map_id, event_id),
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
      );
    SQL

    # Add money column to players if it doesn't exist
    begin
      db.execute("ALTER TABLE players ADD COLUMN money INTEGER DEFAULT 3000")
      @logger.info "Added money column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists
    end

    # Add badge_count column to players if it doesn't exist
    begin
      db.execute("ALTER TABLE players ADD COLUMN badge_count INTEGER DEFAULT 0")
      @logger.info "Added badge_count column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists
    end

    # Add trainer_id column to players if it doesn't exist
    begin
      db.execute("ALTER TABLE players ADD COLUMN trainer_id INTEGER")
      @logger.info "Added trainer_id column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists
    end

    # Add badges column to players if it doesn't exist
    begin
      db.execute("ALTER TABLE players ADD COLUMN badges TEXT DEFAULT '[]'")
      @logger.info "Added badges column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists
    end

    # Add permission column to players (player, moderator, admin)
    begin
      db.execute("ALTER TABLE players ADD COLUMN permission TEXT DEFAULT 'player'")
      @logger.info "Added permission column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists
    end

    # Add home coordinates columns
    begin
      db.execute("ALTER TABLE players ADD COLUMN home_map_id INTEGER")
      db.execute("ALTER TABLE players ADD COLUMN home_x INTEGER")
      db.execute("ALTER TABLE players ADD COLUMN home_y INTEGER")
      @logger.info "Added home location columns to players table"
    rescue SQLite3::SQLException => e
      # Columns already exist
    end

    # Add playtime tracking
    begin
      db.execute("ALTER TABLE players ADD COLUMN playtime_seconds INTEGER DEFAULT 0")
      db.execute("ALTER TABLE players ADD COLUMN session_start INTEGER")
      @logger.info "Added playtime tracking columns to players table"
    rescue SQLite3::SQLException => e
      # Columns already exist
    end

    # Create mutes table
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS player_mutes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER NOT NULL,
        username TEXT NOT NULL,
        muted_by TEXT NOT NULL,
        reason TEXT,
        muted_at INTEGER NOT NULL,
        muted_until INTEGER,
        active INTEGER DEFAULT 1,
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
      )
    SQL

    # Create bans table
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS player_bans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER NOT NULL,
        username TEXT NOT NULL,
        banned_by TEXT NOT NULL,
        reason TEXT,
        banned_at INTEGER NOT NULL,
        banned_until INTEGER,
        active INTEGER DEFAULT 1,
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
      )
    SQL

    # Create player ignores table
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS player_ignores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER NOT NULL,
        ignored_username TEXT NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        UNIQUE(player_id, ignored_username),
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
      )
    SQL

    # Create server settings table
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS server_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    SQL

    # Initialize default server spawn if not set
    begin
      spawn_data = db.execute("SELECT value FROM server_settings WHERE key = 'spawn_point'").first
      unless spawn_data
        default_spawn = {
          map_id: ServerConfig::DEFAULT_SPAWN_MAP,
          x: ServerConfig::DEFAULT_SPAWN_X,
          y: ServerConfig::DEFAULT_SPAWN_Y
        }
        db.execute("INSERT INTO server_settings (key, value) VALUES ('spawn_point', ?)", [default_spawn.to_json])
        @logger.info "Initialized default server spawn point"
      end
    rescue => e
      @logger.warn "Failed to initialize spawn point: #{e.message}"
    end

    # Create indexes for faster queries
    db.execute "CREATE INDEX IF NOT EXISTS idx_mutes_player ON player_mutes(player_id)"
    db.execute "CREATE INDEX IF NOT EXISTS idx_mutes_active ON player_mutes(active)"
    db.execute "CREATE INDEX IF NOT EXISTS idx_bans_player ON player_bans(player_id)"
    db.execute "CREATE INDEX IF NOT EXISTS idx_bans_active ON player_bans(active)"

    # Create auction house tables
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS auction_listings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seller_id INTEGER NOT NULL,
        seller_username TEXT NOT NULL,
        listing_type TEXT NOT NULL CHECK(listing_type IN ('ITEM', 'POKEMON')),
        item_id TEXT,
        item_quantity INTEGER,
        pokemon_data TEXT,
        price INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE', 'SOLD', 'CANCELLED')),
        buyer_id INTEGER,
        bought_at INTEGER
      )
    SQL

    # Create indexes for faster queries
    db.execute "CREATE INDEX IF NOT EXISTS idx_listings_status ON auction_listings(status)"
    db.execute "CREATE INDEX IF NOT EXISTS idx_listings_seller ON auction_listings(seller_id)"
    db.execute "CREATE INDEX IF NOT EXISTS idx_listings_type ON auction_listings(listing_type)"

    # Create Pokedex table for trainer card display
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS player_pokedex (
        player_id INTEGER NOT NULL,
        species TEXT NOT NULL,
        seen INTEGER DEFAULT 0,
        owned INTEGER DEFAULT 0,
        PRIMARY KEY (player_id, species),
        FOREIGN KEY (player_id) REFERENCES players (id) ON DELETE CASCADE
      )
    SQL

    db.close
    @logger.info "Database initialized successfully"
  end

  def authenticate_player(username, password)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    result = db.execute("SELECT * FROM players WHERE username = ?", [username]).first
    db.close

    # Return :not_found if user doesn't exist (allows registration)
    return :not_found unless result

    # Check password hash
    password_hash = Digest::SHA256.hexdigest(password + result['username'])
    if password_hash == result['password_hash']
      @logger.info "Player #{username} authenticated successfully"
      return {
        id: result['id'],
        username: result['username'],
        map_id: result['map_id'],
        x: result['x'],
        y: result['y'],
        direction: result['direction'],
        has_running_shoes: result['has_running_shoes'] || 0,
        has_starter: result['has_starter'] || 0
      }
    else
      @logger.warn "Failed authentication for #{username} - wrong password"
      # Return :wrong_password to indicate user exists but password doesn't match
      return :wrong_password
    end
  end

  def register_player(username, password)
    return nil if username.nil? || username.empty? || password.nil? || password.empty?

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    # Check if username already exists
    existing = db.execute("SELECT id FROM players WHERE username = ?", [username]).first
    if existing
      db.close
      @logger.warn "Registration failed: Username #{username} already exists"
      return nil
    end

    # Create password hash (using username as salt)
    password_hash = Digest::SHA256.hexdigest(password + username)

    begin
      db.execute(
        "INSERT INTO players (username, password_hash, last_login) VALUES (?, ?, ?)",
        [username, password_hash, Time.now.to_s]
      )

      player_id = db.last_insert_row_id
      db.close

      @logger.info "New player registered: #{username} (ID: #{player_id})"

      # Get spawn position from config
      spawn = ServerConfig.get_spawn_position

      return {
        id: player_id,
        username: username,
        map_id: spawn[:map_id],
        x: spawn[:x],
        y: spawn[:y],
        direction: spawn[:direction],
        has_running_shoes: 0,
        has_starter: 0
      }
    rescue SQLite3::Exception => e
      db.close
      @logger.error "Registration error: #{e.message}"
      return nil
    end
  end

  def save_player_position(player_id, map_id, x, y, direction)
    db = SQLite3::Database.new(@db_path)

    db.execute(
      "UPDATE players SET map_id = ?, x = ?, y = ?, direction = ?, last_login = ? WHERE id = ?",
      [map_id, x, y, direction, Time.now.to_s, player_id]
    )

    db.close
  rescue SQLite3::Exception => e
    @logger.error "Failed to save position for player #{player_id}: #{e.message}"
  end

  def save_running_shoes(player_id, has_running_shoes)
    db = SQLite3::Database.new(@db_path)

    db.execute(
      "UPDATE players SET has_running_shoes = ? WHERE id = ?",
      [has_running_shoes ? 1 : 0, player_id]
    )

    db.close
  rescue SQLite3::Exception => e
    @logger.error "Failed to save running shoes for player #{player_id}: #{e.message}"
  end

  def save_switches(player_id, switches_data)
    db = SQLite3::Database.new(@db_path)

    # Convert switches hash to JSON string for storage
    switches_json = JSON.generate(switches_data)

    db.execute(
      "UPDATE players SET switches = ? WHERE id = ?",
      [switches_json, player_id]
    )

    db.close
  rescue SQLite3::Exception => e
    @logger.error "Failed to save switches for player #{player_id}: #{e.message}"
    db.close rescue nil
  end

  def save_variables(player_id, variables_data)
    db = SQLite3::Database.new(@db_path)

    # Convert variables hash to JSON string for storage
    variables_json = JSON.generate(variables_data)

    db.execute(
      "UPDATE players SET variables = ? WHERE id = ?",
      [variables_json, player_id]
    )

    db.close
  rescue SQLite3::Exception => e
    @logger.error "Failed to save variables for player #{player_id}: #{e.message}"
    db.close rescue nil
  end

  def save_self_switches(player_id, self_switches_data)
    db = SQLite3::Database.new(@db_path)

    # Convert self_switches hash to JSON string for storage
    self_switches_json = JSON.generate(self_switches_data)

    db.execute(
      "UPDATE players SET self_switches = ? WHERE id = ?",
      [self_switches_json, player_id]
    )

    db.close
  rescue SQLite3::Exception => e
    @logger.error "Failed to save self_switches for player #{player_id}: #{e.message}"
    db.close rescue nil
  end

  def save_player_bag(player_id, bag_data)
    return unless bag_data && bag_data.is_a?(Array)

    db = SQLite3::Database.new(@db_path)

    # Clear existing bag items
    db.execute("DELETE FROM player_bag WHERE player_id = ?", [player_id])

    # Consolidate duplicate items (merge quantities)
    consolidated = {}
    bag_data.each do |item|
      item_id = (item[:item_id] || item['item_id']).to_s
      quantity = (item[:quantity] || item['quantity'] || 1).to_i

      if consolidated[item_id]
        consolidated[item_id] += quantity
      else
        consolidated[item_id] = quantity
      end
    end

    # Insert consolidated items
    consolidated.each do |item_id, quantity|
      db.execute(
        "INSERT INTO player_bag (player_id, item_id, quantity) VALUES (?, ?, ?)",
        [player_id, item_id, quantity]
      )
    end

    db.close
    @logger.info "Saved bag for player #{player_id}: #{consolidated.size} items (consolidated from #{bag_data.size})"
  rescue SQLite3::Exception => e
    @logger.error "Failed to save bag for player #{player_id}: #{e.message}"
    db.close rescue nil
  end

  def save_player_pokemon(player_id, pokemon_data)
    return unless pokemon_data && pokemon_data.is_a?(Array)

    db = SQLite3::Database.new(@db_path)

    # Add data column if it doesn't exist (for full Pokemon data as JSON)
    begin
      db.execute("ALTER TABLE player_pokemon ADD COLUMN data TEXT")
      @logger.info "Added data column to player_pokemon table"
    rescue SQLite3::SQLException => e
      # Column already exists, ignore
    end

    # Clear existing Pokemon
    db.execute("DELETE FROM player_pokemon WHERE player_id = ?", [player_id])

    # Insert new Pokemon with FULL data preserved as JSON
    pokemon_data.each_with_index do |pkmn, index|
      # Store basic fields for querying + full data as JSON for complete preservation
      db.execute(
        "INSERT INTO player_pokemon (player_id, species, level, nickname, position, moves, hp, attack, defense, sp_attack, sp_defense, speed, ability, nature, gender, shiny, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          player_id,
          pkmn[:species] || pkmn['species'],
          pkmn[:level] || pkmn['level'] || 5,
          pkmn[:nickname] || pkmn[:name] || pkmn['nickname'] || pkmn['name'],
          index,
          (pkmn[:moves] || pkmn['moves'] || []).to_json,
          pkmn[:hp] || pkmn['hp'],
          pkmn[:attack] || pkmn['attack'],
          pkmn[:defense] || pkmn['defense'],
          pkmn[:sp_attack] || pkmn['sp_attack'],
          pkmn[:sp_defense] || pkmn['sp_defense'],
          pkmn[:speed] || pkmn['speed'],
          pkmn[:ability] || pkmn['ability'],
          pkmn[:nature] || pkmn['nature'],
          pkmn[:gender] || pkmn['gender'],
          pkmn[:shiny] || pkmn['shiny'] ? 1 : 0,
          pkmn.to_json  # Store FULL Pokemon data as JSON to preserve everything
        ]
      )
    end

    db.close
    @logger.info "Saved Pokemon for player #{player_id}: #{pokemon_data.size} Pokemon (with full data)"
  rescue SQLite3::Exception => e
    @logger.error "Failed to save Pokemon for player #{player_id}: #{e.message}"
    @logger.error "Error: #{e.backtrace.first(3).join("\n")}"
    db.close rescue nil
  end

  def save_player_pc_boxes(player_id, pc_boxes_data)
    return unless pc_boxes_data && pc_boxes_data.is_a?(Array)

    db = SQLite3::Database.new(@db_path)

    # Create PC boxes table if it doesn't exist
    begin
      db.execute(<<-SQL)
        CREATE TABLE IF NOT EXISTS player_pc_boxes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          player_id INTEGER NOT NULL,
          box_number INTEGER NOT NULL,
          box_name TEXT,
          slot INTEGER NOT NULL,
          species TEXT,
          level INTEGER,
          nickname TEXT,
          data TEXT,
          FOREIGN KEY (player_id) REFERENCES players(id),
          UNIQUE(player_id, box_number, slot)
        )
      SQL
    rescue SQLite3::SQLException => e
      @logger.warn "PC boxes table might already exist: #{e.message}"
    end

    # Clear existing PC boxes for this player
    db.execute("DELETE FROM player_pc_boxes WHERE player_id = ?", [player_id])

    # Insert PC box Pokemon with FULL data preserved as JSON
    total_pokemon = 0
    pc_boxes_data.each do |box_data|
      box_number = box_data[:box_number] || box_data['box_number']
      box_name = box_data[:box_name] || box_data['box_name']
      pokemon_list = box_data[:pokemon] || box_data['pokemon'] || []

      pokemon_list.each do |pkmn_entry|
        slot = pkmn_entry[:slot] || pkmn_entry['slot']
        pkmn_data = pkmn_entry[:data] || pkmn_entry['data']
        next unless slot && pkmn_data

        # Extract basic info for querying
        species = pkmn_data[:species] || pkmn_data['species'] || 'UNKNOWN'
        level = pkmn_data[:level] || pkmn_data['level'] || 1
        nickname = pkmn_data[:nickname] || pkmn_data[:name] || pkmn_data['nickname'] || pkmn_data['name']

        db.execute(
          "INSERT INTO player_pc_boxes (player_id, box_number, box_name, slot, species, level, nickname, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          [
            player_id,
            box_number,
            box_name,
            slot,
            species,
            level,
            nickname,
            pkmn_data.to_json  # Store FULL Pokemon data as JSON
          ]
        )
        total_pokemon += 1
      end
    end

    db.close
    @logger.info "Saved PC boxes for player #{player_id}: #{pc_boxes_data.size} boxes with #{total_pokemon} Pokemon (with full data)"
  rescue SQLite3::Exception => e
    @logger.error "Failed to save PC boxes for player #{player_id}: #{e.message}"
    @logger.error "Error: #{e.backtrace.first(3).join("\n")}"
    db.close rescue nil
  end

  def save_pokedex(player_id, pokedex_data)
    return unless pokedex_data

    db = SQLite3::Database.new(@db_path)

    # Save Pokedex entries
    pokedex_data.each do |species, entry|
      seen = entry[:seen] || entry['seen'] || 0
      owned = entry[:owned] || entry['owned'] || 0

      # Convert species to string (handles both symbols and strings from client)
      species_str = species.to_s.upcase.gsub(':', '')  # Remove colon if symbol

      db.execute(
        "INSERT OR REPLACE INTO player_pokedex (player_id, species, seen, owned) VALUES (?, ?, ?, ?)",
        [player_id, species_str, seen, owned]
      )
    end

    db.close
    @logger.info "Saved Pokedex for player #{player_id}: #{pokedex_data.size} entries"
  rescue SQLite3::Exception => e
    @logger.error "Failed to save Pokedex for player #{player_id}: #{e.message}"
    db.close rescue nil
  end

  def save_daycare(player_id, daycare_data)
    return unless daycare_data

    db = SQLite3::Database.new(@db_path)

    # Create daycare table if it doesn't exist
    db.execute(<<-SQL)
      CREATE TABLE IF NOT EXISTS player_daycare (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER NOT NULL,
        slot_index INTEGER NOT NULL,
        initial_level INTEGER NOT NULL,
        pokemon_data TEXT NOT NULL,
        egg_generated INTEGER DEFAULT 0,
        step_counter INTEGER DEFAULT 0,
        UNIQUE(player_id, slot_index),
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
      )
    SQL

    # Clear existing daycare data
    db.execute("DELETE FROM player_daycare WHERE player_id = ?", [player_id])

    # Save egg status
    egg_generated = daycare_data[:egg_generated] || daycare_data['egg_generated'] || 0
    step_counter = daycare_data[:step_counter] || daycare_data['step_counter'] || 0

    # Save each slot
    slots = daycare_data[:slots] || daycare_data['slots'] || []
    slots.each do |slot|
      slot_index = slot[:slot_index] || slot['slot_index']
      initial_level = slot[:initial_level] || slot['initial_level']
      pokemon_data = slot[:pokemon] || slot['pokemon']

      next unless slot_index && pokemon_data

      db.execute(
        "INSERT INTO player_daycare (player_id, slot_index, initial_level, pokemon_data, egg_generated, step_counter) VALUES (?, ?, ?, ?, ?, ?)",
        [player_id, slot_index, initial_level, pokemon_data.to_json, egg_generated, step_counter]
      )
    end

    db.close
    @logger.info "Saved daycare for player #{player_id}: #{slots.size} Pokemon"
  rescue SQLite3::Exception => e
    @logger.error "Failed to save daycare for player #{player_id}: #{e.message}"
    db.close rescue nil
  end

  def load_daycare(player_id)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    # Check if table exists
    table_exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='player_daycare'").any?
    unless table_exists
      db.close
      return nil
    end

    rows = db.execute("SELECT * FROM player_daycare WHERE player_id = ? ORDER BY slot_index", [player_id])
    db.close

    return nil if rows.empty?

    # Get egg status from first row
    first_row = rows.first
    daycare_data = {
      egg_generated: first_row['egg_generated'] || 0,
      step_counter: first_row['step_counter'] || 0,
      slots: []
    }

    rows.each do |row|
      pokemon_data = JSON.parse(row['pokemon_data'], symbolize_names: true) rescue nil
      next unless pokemon_data

      daycare_data[:slots] << {
        slot_index: row['slot_index'],
        initial_level: row['initial_level'],
        pokemon: pokemon_data
      }
    end

    @logger.info "Loaded daycare for player #{player_id}: #{daycare_data[:slots].size} Pokemon"
    return daycare_data
  rescue SQLite3::Exception => e
    @logger.error "Failed to load daycare for player #{player_id}: #{e.message}"
    db.close rescue nil
    return nil
  end

  def update_player_playtime(player_id)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    # Get current session start
    player = db.execute("SELECT session_start, playtime_seconds FROM players WHERE id = ?", [player_id]).first

    if player && player['session_start']
      session_start = player['session_start'].to_i
      current_playtime = (player['playtime_seconds'] || 0).to_i
      session_duration = Time.now.to_i - session_start

      # Add session duration to total playtime
      new_playtime = current_playtime + session_duration

      db.execute(
        "UPDATE players SET playtime_seconds = ?, session_start = NULL WHERE id = ?",
        [new_playtime, player_id]
      )

      @logger.info "Updated playtime for player #{player_id}: +#{session_duration}s (total: #{new_playtime}s)"
    end

    db.close
  rescue SQLite3::Exception => e
    @logger.error "Failed to update playtime for player #{player_id}: #{e.message}"
    db.close rescue nil
  end

  def load_player_data(player_id)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    player = db.execute("SELECT * FROM players WHERE id = ?", [player_id]).first

    if player
      # Load bag
      bag = db.execute("SELECT item_id, quantity FROM player_bag WHERE player_id = ?", [player_id])

      # Load Pokemon with full data preservation
      pokemon_rows = db.execute("SELECT * FROM player_pokemon WHERE player_id = ? ORDER BY position", [player_id])

      # Deserialize full Pokemon data from JSON if available
      pokemon = pokemon_rows.map do |row|
        if row['data'] && !row['data'].empty?
          # Use full Pokemon data from JSON (preserves OT, IVs, EVs, etc.)
          begin
            JSON.parse(row['data'], symbolize_names: true)
          rescue JSON::ParserError => e
            @logger.warn "Failed to parse Pokemon JSON data for player #{player_id}: #{e.message}"
            # Fall back to basic data from columns
            row
          end
        else
          # Fall back to basic data from columns (for old saves without full data)
          row
        end
      end

      # Load event persistence data (switches, variables, self_switches)
      switches = {}
      variables = {}
      self_switches = {}

      if player['switches'] && !player['switches'].empty?
        begin
          switches = JSON.parse(player['switches'], symbolize_names: true)
        rescue JSON::ParserError => e
          @logger.warn "Failed to parse switches for player #{player_id}: #{e.message}"
          switches = {}
        end
      end

      if player['variables'] && !player['variables'].empty?
        begin
          variables = JSON.parse(player['variables'], symbolize_names: true)
        rescue JSON::ParserError => e
          @logger.warn "Failed to parse variables for player #{player_id}: #{e.message}"
          variables = {}
        end
      end

      if player['self_switches'] && !player['self_switches'].empty?
        begin
          self_switches = JSON.parse(player['self_switches'], symbolize_names: true)
        rescue JSON::ParserError => e
          @logger.warn "Failed to parse self_switches for player #{player_id}: #{e.message}"
          self_switches = {}
        end
      end

      # Load badges
      badges = [false] * 8  # Default: no badges
      if player['badges'] && !player['badges'].empty?
        begin
          badges = JSON.parse(player['badges'])
          @logger.info "[BADGE DEBUG] Player #{player_id} (#{player['username']}): Loaded badges from DB: #{badges.inspect}"
        rescue JSON::ParserError => e
          @logger.warn "Failed to parse badges for player #{player_id}: #{e.message}"
          badges = [false] * 8
        end
      else
        @logger.info "[BADGE DEBUG] Player #{player_id} (#{player['username']}): No badges in DB, using default: #{badges.inspect}"
      end

      # Load Pokedex
      pokedex = {}
      pokedex_rows = db.execute("SELECT species, seen, owned FROM player_pokedex WHERE player_id = ?", [player_id])
      pokedex_rows.each do |row|
        species = row['species'] || row[0]
        pokedex[species] = {
          seen: row['seen'] || row[1] || 0,
          owned: row['owned'] || row[2] || 0
        }
      end

      # Load PC boxes
      pc_boxes = []
      begin
        pc_box_rows = db.execute("SELECT box_number, box_name, slot, data FROM player_pc_boxes WHERE player_id = ? ORDER BY box_number, slot", [player_id])

        # Group by box number
        boxes_hash = {}
        pc_box_rows.each do |row|
          box_number = row['box_number'] || row[0]
          box_name = row['box_name'] || row[1]
          slot = row['slot'] || row[2]
          data_json = row['data'] || row[3]

          # Initialize box if not exists
          boxes_hash[box_number] ||= {
            box_number: box_number,
            box_name: box_name,
            pokemon: []
          }

          # Parse Pokemon data
          if data_json && !data_json.empty?
            begin
              pkmn_data = JSON.parse(data_json, symbolize_names: true)
              boxes_hash[box_number][:pokemon] << {
                slot: slot,
                data: pkmn_data
              }
            rescue JSON::ParserError => e
              @logger.warn "Failed to parse PC box Pokemon JSON for player #{player_id}: #{e.message}"
            end
          end
        end

        # Convert hash to array
        pc_boxes = boxes_hash.values
      rescue SQLite3::SQLException => e
        # Table might not exist yet
        @logger.warn "Could not load PC boxes for player #{player_id}: #{e.message}"
        pc_boxes = []
      end

      db.close

      # Load daycare data
      daycare = load_daycare(player_id)

      @logger.info "[BADGE DEBUG] Player #{player_id} (#{player['username']}): Sending badges to client: #{badges.inspect}"

      return {
        id: player['id'],
        username: player['username'],
        map_id: player['map_id'],
        x: player['x'],
        y: player['y'],
        direction: player['direction'],
        bag: bag,
        pokemon: pokemon,
        pc_boxes: pc_boxes,
        has_running_shoes: player['has_running_shoes'] || 0,
        money: player['money'] || 3000,
        badge_count: player['badge_count'] || 0,
        trainer_id: player['trainer_id'],
        badges: badges,
        switches: switches,
        variables: variables,
        self_switches: self_switches,
        pokedex: pokedex,
        daycare: daycare,
        playtime_seconds: player['playtime_seconds'] || 0,
        created_at: player['created_at']
      }
    end

    db.close
    return nil
  end

  def get_player_elo(player_id)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    result = db.execute("SELECT elo FROM players WHERE id = ?", [player_id]).first
    db.close

    return result ? (result['elo'] || 1000) : 1000
  rescue SQLite3::Exception => e
    @logger.error "Failed to get player ELO: #{e.message}"
    db.close rescue nil
    return 1000
  end

  def update_battle_stats(player_id, new_elo, is_winner)
    db = SQLite3::Database.new(@db_path)

    if is_winner
      db.execute("UPDATE players SET elo = ?, wins = wins + 1 WHERE id = ?", [new_elo, player_id])
    else
      db.execute("UPDATE players SET elo = ?, losses = losses + 1 WHERE id = ?", [new_elo, player_id])
    end

    db.close
    @logger.info "Updated battle stats for player #{player_id}: ELO=#{new_elo}, Win=#{is_winner}"
  rescue SQLite3::Exception => e
    @logger.error "Failed to update battle stats: #{e.message}"
    db.close rescue nil
  end

  def has_collected_item?(player_id, map_id, event_id)
    db = SQLite3::Database.new(@db_path)

    result = db.execute(
      "SELECT id FROM player_collected_items WHERE player_id = ? AND map_id = ? AND event_id = ?",
      [player_id, map_id, event_id]
    ).first

    db.close
    return !result.nil?
  rescue SQLite3::Exception => e
    @logger.error "Failed to check collected item: #{e.message}"
    db.close rescue nil
    return false
  end

  def mark_item_collected(player_id, map_id, event_id)
    db = SQLite3::Database.new(@db_path)

    db.execute(
      "INSERT OR IGNORE INTO player_collected_items (player_id, map_id, event_id) VALUES (?, ?, ?)",
      [player_id, map_id, event_id]
    )

    db.close
    @logger.info "Marked item collected: Player #{player_id}, Map #{map_id}, Event #{event_id}"
    return true
  rescue SQLite3::Exception => e
    @logger.error "Failed to mark item collected: #{e.message}"
    db.close rescue nil
    return false
  end

  def get_collected_items(player_id, map_id)
    db = SQLite3::Database.new(@db_path)

    results = db.execute(
      "SELECT event_id FROM player_collected_items WHERE player_id = ? AND map_id = ?",
      [player_id, map_id]
    )

    db.close
    return results.map { |row| row[0] }
  rescue SQLite3::Exception => e
    @logger.error "Failed to get collected items: #{e.message}"
    db.close rescue nil
    return []
  end

  #==========================================================================
  # AUCTION HOUSE SYSTEM
  #==========================================================================

  def init_auction_house_db
    db = SQLite3::Database.new(@db_path)

    # Create auction_listings table
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS auction_listings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seller_id INTEGER NOT NULL,
        seller_username TEXT NOT NULL,
        listing_type TEXT NOT NULL CHECK(listing_type IN ('ITEM', 'POKEMON')),
        item_id TEXT,
        item_quantity INTEGER,
        pokemon_data TEXT,
        price INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK(status IN ('ACTIVE', 'SOLD', 'CANCELLED')),
        buyer_id INTEGER,
        bought_at INTEGER
      )
    SQL

    # Create indexes for faster queries
    db.execute "CREATE INDEX IF NOT EXISTS idx_listings_status ON auction_listings(status)"
    db.execute "CREATE INDEX IF NOT EXISTS idx_listings_seller ON auction_listings(seller_id)"
    db.execute "CREATE INDEX IF NOT EXISTS idx_listings_type ON auction_listings(listing_type)"

    db.close
    @logger.info "Auction house database initialized"
  end

  # Add money column to players table
  def init_player_money
    db = SQLite3::Database.new(@db_path)

    begin
      db.execute("ALTER TABLE players ADD COLUMN money INTEGER DEFAULT 3000")
      @logger.info "Added money column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists
    end

    db.close
  end

  def update_player_money(player_id, amount)
    db = SQLite3::Database.new(@db_path)
    db.execute("UPDATE players SET money = ? WHERE id = ?", [amount, player_id])
    db.close
  end

  # Add badge_count column to players table
  def init_player_badge_count
    db = SQLite3::Database.new(@db_path)

    begin
      db.execute("ALTER TABLE players ADD COLUMN badge_count INTEGER DEFAULT 0")
      @logger.info "Added badge_count column to players table"
    rescue SQLite3::SQLException => e
      # Column already exists
    end

    db.close
  end

  def update_player_badge_count(player_id, count)
    db = SQLite3::Database.new(@db_path)
    db.execute("UPDATE players SET badge_count = ? WHERE id = ?", [count, player_id])
    db.close
  end

  # Handle auction listing creation (item)
  def handle_auction_list_item(client_id, data)
    player_id = @player_data[client_id][:player_id]
    username = @player_data[client_id][:username]
    item_id = data[:item_id] || data['item_id']
    quantity = (data[:quantity] || data['quantity'] || 1).to_i
    price = (data[:price] || data['price']).to_i

    @logger.info "[AUCTION] Player ##{player_id} listing item #{item_id} x#{quantity} for #{price}"

    # Validate price
    if price <= 0
      send_to_client(client_id, {type: :auction_error, error: "Price must be greater than 0"})
      return
    end

    # Validate quantity
    if quantity <= 0
      send_to_client(client_id, {type: :auction_error, error: "Quantity must be greater than 0"})
      return
    end

    # Check if player has the item in their bag (anti-dupe security)
    player_bag = @player_data[client_id][:bag] || []
    bag_item = player_bag.find { |i| (i[:item_id] || i['item_id']).to_s == item_id.to_s }

    if !bag_item || (bag_item[:quantity] || bag_item['quantity'] || 0) < quantity
      send_to_client(client_id, {type: :auction_error, error: "You don't have enough of that item!"})
      return
    end

    # ANTI-DUPE: Remove item from player's bag BEFORE creating listing
    bag_item_quantity = (bag_item[:quantity] || bag_item['quantity']).to_i
    if bag_item_quantity == quantity
      # Remove entirely
      player_bag.delete(bag_item)
    else
      # Reduce quantity
      if bag_item[:quantity]
        bag_item[:quantity] = bag_item_quantity - quantity
      else
        bag_item['quantity'] = bag_item_quantity - quantity
      end
    end

    # Save bag immediately
    @player_data[client_id][:bag] = player_bag
    save_player_bag(player_id, player_bag)

    # Create listing in database
    db = SQLite3::Database.new(@db_path)
    db.execute(
      "INSERT INTO auction_listings (seller_id, seller_username, listing_type, item_id, item_quantity, price, created_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [player_id, username, 'ITEM', item_id.to_s, quantity, price, Time.now.to_i, 'ACTIVE']
    )
    listing_id = db.last_insert_row_id
    db.close

    @logger.info "[AUCTION] Created listing ##{listing_id}"
    send_to_client(client_id, {type: :auction_list_success, listing_id: listing_id})
  end

  # Handle auction listing creation (Pokemon)
  def handle_auction_list_pokemon(client_id, data)
    player_id = @player_data[client_id][:player_id]
    username = @player_data[client_id][:username]
    pokemon_data = data[:pokemon_data] || data['pokemon_data']
    price = (data[:price] || data['price']).to_i
    party_index = (data[:party_index] || data['party_index']).to_i

    @logger.info "[AUCTION] Player ##{player_id} listing Pokemon for #{price}"

    # Validate price
    if price <= 0
      send_to_client(client_id, {type: :auction_error, error: "Price must be greater than 0"})
      return
    end

    # Validate Pokemon data
    if !pokemon_data
      send_to_client(client_id, {type: :auction_error, error: "Invalid Pokemon data"})
      return
    end

    # ANTI-DUPE: Remove Pokemon from player's party BEFORE creating listing
    player_pokemon = @player_data[client_id][:pokemon] || []

    if party_index < 0 || party_index >= player_pokemon.length
      send_to_client(client_id, {type: :auction_error, error: "Invalid Pokemon index"})
      return
    end

    # Remove Pokemon from party
    player_pokemon.delete_at(party_index)
    @player_data[client_id][:pokemon] = player_pokemon
    save_player_pokemon(player_id, player_pokemon)

    # Create listing in database
    db = SQLite3::Database.new(@db_path)
    db.execute(
      "INSERT INTO auction_listings (seller_id, seller_username, listing_type, pokemon_data, price, created_at, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
      [player_id, username, 'POKEMON', pokemon_data.to_json, price, Time.now.to_i, 'ACTIVE']
    )
    listing_id = db.last_insert_row_id
    db.close

    @logger.info "[AUCTION] Created Pokemon listing ##{listing_id}"
    send_to_client(client_id, {type: :auction_list_success, listing_id: listing_id})
  end

  # Handle auction browse
  def handle_auction_browse(client_id, data)
    filter_type = data[:filter_type] || data['filter_type'] || 'ALL'
    search_query = data[:search] || data['search'] || ''
    offset = (data[:offset] || data['offset'] || 0).to_i
    limit = (data[:limit] || data['limit'] || 50).to_i

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    # Build query
    sql = "SELECT * FROM auction_listings WHERE status = 'ACTIVE'"
    params = []

    if filter_type == 'ITEM'
      sql += " AND listing_type = 'ITEM'"
    elsif filter_type == 'POKEMON'
      sql += " AND listing_type = 'POKEMON'"
    end

    if !search_query.empty?
      sql += " AND (item_id LIKE ? OR pokemon_data LIKE ? OR seller_username LIKE ?)"
      search_pattern = "%#{search_query}%"
      params += [search_pattern, search_pattern, search_pattern]
    end

    sql += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
    params += [limit, offset]

    listings = db.execute(sql, params)
    db.close

    # Parse Pokemon data from JSON
    listings.each do |listing|
      if listing['pokemon_data'] && !listing['pokemon_data'].empty?
        begin
          listing['pokemon_data'] = JSON.parse(listing['pokemon_data'], symbolize_names: true)
        rescue JSON::ParserError
          listing['pokemon_data'] = nil
        end
      end
    end

    send_to_client(client_id, {type: :auction_browse_result, listings: listings})
  end

  # Handle auction purchase
  def handle_auction_buy(client_id, data)
    player_id = @player_data[client_id][:player_id]
    username = @player_data[client_id][:username]
    listing_id = (data[:listing_id] || data['listing_id']).to_i

    @logger.info "[AUCTION] Player ##{player_id} attempting to buy listing ##{listing_id}"

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    # Get listing
    listing = db.execute("SELECT * FROM auction_listings WHERE id = ?", [listing_id]).first

    if !listing
      db.close
      send_to_client(client_id, {type: :auction_error, error: "Listing not found"})
      return
    end

    if listing['status'] != 'ACTIVE'
      db.close
      send_to_client(client_id, {type: :auction_error, error: "Listing is no longer available"})
      return
    end

    if listing['seller_id'] == player_id
      db.close
      send_to_client(client_id, {type: :auction_error, error: "You can't buy your own listing!"})
      return
    end

    price = listing['price']

    # Check if buyer has enough money
    buyer_money = @player_data[client_id][:money] || 0
    if buyer_money < price
      db.close
      send_to_client(client_id, {type: :auction_error, error: "Not enough money! Need #{price}, have #{buyer_money}"})
      return
    end

    # TRANSACTION: Deduct money, give item/Pokemon, mark as sold
    # Deduct money from buyer
    @player_data[client_id][:money] = buyer_money - price
    update_player_money(player_id, buyer_money - price)

    # Add money to seller (even if offline)
    seller_id = listing['seller_id']
    seller_client_id = @player_data.find { |cid, pdata| pdata[:player_id] == seller_id }&.first

    if seller_client_id
      # Seller is online
      seller_money = @player_data[seller_client_id][:money] || 0
      @player_data[seller_client_id][:money] = seller_money + price
      update_player_money(seller_id, seller_money + price)
      send_to_client(seller_client_id, {
        type: :auction_sold,
        listing_id: listing_id,
        price: price,
        buyer: username,
        money: @player_data[seller_client_id][:money]
      })
    else
      # Seller is offline - update database directly
      player_row = db.execute("SELECT money FROM players WHERE id = ?", [seller_id]).first
      if player_row
        seller_money = player_row['money'] || 0
        update_player_money(seller_id, seller_money + price)
      end
    end

    # Give item/Pokemon to buyer
    if listing['listing_type'] == 'ITEM'
      # Add item to buyer's bag
      buyer_bag = @player_data[client_id][:bag] || []
      item_id = listing['item_id']
      quantity = listing['item_quantity']

      existing_item = buyer_bag.find { |i| (i[:item_id] || i['item_id']).to_s == item_id.to_s }
      if existing_item
        if existing_item[:quantity]
          existing_item[:quantity] = (existing_item[:quantity] || 0) + quantity
        else
          existing_item['quantity'] = (existing_item['quantity'] || 0) + quantity
        end
      else
        buyer_bag << {item_id: item_id, quantity: quantity}
      end

      @player_data[client_id][:bag] = buyer_bag
      save_player_bag(player_id, buyer_bag)

    elsif listing['listing_type'] == 'POKEMON'
      # Add Pokemon to buyer's party
      buyer_pokemon = @player_data[client_id][:pokemon] || []
      pokemon_data = JSON.parse(listing['pokemon_data'], symbolize_names: true)

      if buyer_pokemon.length < 6
        buyer_pokemon << pokemon_data
        @player_data[client_id][:pokemon] = buyer_pokemon
        save_player_pokemon(player_id, buyer_pokemon)
      else
        db.close
        # Refund buyer
        @player_data[client_id][:money] = buyer_money
        update_player_money(player_id, buyer_money)
        send_to_client(client_id, {type: :auction_error, error: "Your party is full!"})
        return
      end
    end

    # Mark listing as sold
    db.execute(
      "UPDATE auction_listings SET status = 'SOLD', buyer_id = ?, bought_at = ? WHERE id = ?",
      [player_id, Time.now.to_i, listing_id]
    )
    db.close

    @logger.info "[AUCTION] Listing ##{listing_id} sold to player ##{player_id} for #{price}"

    # Send updated inventory to buyer
    send_to_client(client_id, {
      type: :auction_buy_success,
      listing_id: listing_id,
      price: price,
      money: @player_data[client_id][:money],
      bag: @player_data[client_id][:bag],
      pokemon: @player_data[client_id][:pokemon]
    })
  end

  # Handle auction cancel
  def handle_auction_cancel(client_id, data)
    player_id = @player_data[client_id][:player_id]
    listing_id = (data[:listing_id] || data['listing_id']).to_i

    @logger.info "[AUCTION] Player ##{player_id} cancelling listing ##{listing_id}"

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    # Get listing
    listing = db.execute("SELECT * FROM auction_listings WHERE id = ?", [listing_id]).first

    if !listing
      db.close
      send_to_client(client_id, {type: :auction_error, error: "Listing not found"})
      return
    end

    if listing['seller_id'] != player_id
      db.close
      send_to_client(client_id, {type: :auction_error, error: "You can only cancel your own listings!"})
      return
    end

    if listing['status'] != 'ACTIVE'
      db.close
      send_to_client(client_id, {type: :auction_error, error: "Listing is no longer active"})
      return
    end

    # Return item/Pokemon to seller
    if listing['listing_type'] == 'ITEM'
      # Return item to bag
      player_bag = @player_data[client_id][:bag] || []
      item_id = listing['item_id']
      quantity = listing['item_quantity']

      existing_item = player_bag.find { |i| (i[:item_id] || i['item_id']).to_s == item_id.to_s }
      if existing_item
        if existing_item[:quantity]
          existing_item[:quantity] = (existing_item[:quantity] || 0) + quantity
        else
          existing_item['quantity'] = (existing_item['quantity'] || 0) + quantity
        end
      else
        player_bag << {item_id: item_id, quantity: quantity}
      end

      @player_data[client_id][:bag] = player_bag
      save_player_bag(player_id, player_bag)

    elsif listing['listing_type'] == 'POKEMON'
      # Return Pokemon to party
      player_pokemon = @player_data[client_id][:pokemon] || []
      pokemon_data = JSON.parse(listing['pokemon_data'], symbolize_names: true)

      if player_pokemon.length < 6
        player_pokemon << pokemon_data
        @player_data[client_id][:pokemon] = player_pokemon
        save_player_pokemon(player_id, player_pokemon)
      else
        db.close
        send_to_client(client_id, {type: :auction_error, error: "Your party is full! Cannot cancel."})
        return
      end
    end

    # Mark listing as cancelled
    db.execute("UPDATE auction_listings SET status = 'CANCELLED' WHERE id = ?", [listing_id])
    db.close

    @logger.info "[AUCTION] Listing ##{listing_id} cancelled"

    # Send updated inventory to seller
    send_to_client(client_id, {
      type: :auction_cancel_success,
      listing_id: listing_id,
      bag: @player_data[client_id][:bag],
      pokemon: @player_data[client_id][:pokemon]
    })
  end

  # Handle get my listings
  def handle_auction_my_listings(client_id, data)
    player_id = @player_data[client_id][:player_id]

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    listings = db.execute(
      "SELECT * FROM auction_listings WHERE seller_id = ? AND status = 'ACTIVE' ORDER BY created_at DESC",
      [player_id]
    )
    db.close

    # Parse Pokemon data from JSON
    listings.each do |listing|
      if listing['pokemon_data'] && !listing['pokemon_data'].empty?
        begin
          listing['pokemon_data'] = JSON.parse(listing['pokemon_data'], symbolize_names: true)
        rescue JSON::ParserError
          listing['pokemon_data'] = nil
        end
      end
    end

    send_to_client(client_id, {type: :auction_my_listings_result, listings: listings})
  end

  # ============================================================================
  # COMMAND SYSTEM
  # ============================================================================

  def handle_command(client_id, message)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    # Parse command and arguments
    parts = message[1..-1].split(' ', 2)  # Remove leading / and split

    # Validate command is not empty
    if parts[0].nil? || parts[0].empty?
      send_server_message(client_id, "Usage: /<command> [arguments]. Type /help for a list of commands.", color: "YELLOW")
      return
    end

    command = parts[0].downcase
    args = parts[1] || ""

    @logger.info "Command from #{username}: /#{command} #{args}"

    # Check if command is an alias
    actual_command = ServerConfig.find_command_by_alias(command.to_sym) || command.to_sym

    # Check if command is enabled
    unless ServerConfig.command_enabled?(actual_command)
      send_server_message(client_id, "Command /#{command} is not available.")
      return
    end

    # Get player permission level
    permission = get_player_permission(player_id)

    # Check if player has permission for this command
    required_permission = ServerConfig.get_command_permission(actual_command)
    unless has_permission?(permission, required_permission)
      send_server_message(client_id, "You don't have permission to use /#{command}.")
      return
    end

    # Route command to handler
    case actual_command
    when :help
      cmd_help(client_id, args)
    when :msg
      cmd_msg(client_id, args)
    when :reply
      cmd_reply(client_id, args)
    when :online
      cmd_online(client_id, args)
    when :time
      cmd_time(client_id, args)
    when :spawn
      cmd_spawn(client_id, args)
    when :home
      cmd_home(client_id, args)
    when :sethome
      cmd_sethome(client_id, args)
    when :ping
      cmd_ping(client_id, args)
    when :stats
      cmd_stats(client_id, args)
    when :badge
      cmd_badge(client_id, args)
    when :playtime
      cmd_playtime(client_id, args)
    when :changepassword
      cmd_changepassword(client_id, args)
    when :ignore
      cmd_ignore(client_id, args)
    when :unignore
      cmd_unignore(client_id, args)
    when :mute
      cmd_mute(client_id, args)
    when :unmute
      cmd_unmute(client_id, args)
    when :kick
      cmd_kick(client_id, args)
    when :warn
      cmd_warn(client_id, args)
    when :ban
      cmd_ban(client_id, args)
    when :unban
      cmd_unban(client_id, args)
    when :give
      cmd_give(client_id, args)
    when :tp
      cmd_tp(client_id, args)
    when :tpa
      cmd_tpa(client_id, args)
    when :tpaccept
      cmd_tpaccept(client_id, args)
    when :tpdeny
      cmd_tpdeny(client_id, args)
    when :summon
      cmd_summon(client_id, args)
    when :setspawn
      cmd_setspawn(client_id, args)
    when :settime
      cmd_settime(client_id, args)
    when :broadcast
      cmd_broadcast(client_id, args)
    when :heal
      cmd_heal(client_id, args)
    when :setmoney
      cmd_setmoney(client_id, args)
    when :maintenance
      cmd_maintenance(client_id, args)
    else
      send_server_message(client_id, "Unknown command: /#{command}. Use /help for available commands.")
    end
  rescue => e
    @logger.error "Error handling command /#{command}: #{e.message}"
    @logger.error e.backtrace.join("\n")
    send_server_message(client_id, "Error executing command: #{e.message}")
  end

  # Helper: Send server message to client
  def send_server_message(client_id, message, color: "YELLOW")
    send_to_client(client_id, {
      type: "chat_message",
      data: {
        username: "[SERVER]",
        message: message,
        timestamp: Time.now.to_f,
        color: color
      }
    })
  end

  # Helper: Get player permission level
  def get_player_permission(player_id)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    player = db.execute("SELECT username, permission FROM players WHERE id = ?", [player_id]).first
    db.close

    return :player unless player

    # Check if user is in admin list (overrides database)
    if ServerConfig.is_admin?(player['username'])
      return :admin
    end

    (player['permission'] || 'player').to_sym
  end

  # Helper: Check if player has required permission
  def has_permission?(player_perm, required_perm)
    perm_levels = { player: 0, moderator: 1, admin: 2 }
    perm_levels[player_perm] >= perm_levels[required_perm]
  end

  # Helper: Check if player is muted
  def is_muted?(player_id)
    return false unless player_id

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    mute = db.execute(
      "SELECT * FROM player_mutes WHERE player_id = ? AND active = 1 ORDER BY muted_at DESC LIMIT 1",
      [player_id]
    ).first
    db.close

    return false unless mute

    # Check if mute has expired
    if mute['muted_until'] && Time.now.to_i > mute['muted_until']
      # Mute expired, deactivate it
      db = SQLite3::Database.new(@db_path)
      db.execute("UPDATE player_mutes SET active = 0 WHERE id = ?", [mute['id']])
      db.close
      return false
    end

    true
  end

  # Helper: Check if player is banned
  def is_banned?(player_id)
    return false unless player_id

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    ban = db.execute(
      "SELECT * FROM player_bans WHERE player_id = ? AND active = 1 ORDER BY banned_at DESC LIMIT 1",
      [player_id]
    ).first
    db.close

    return false unless ban

    # Check if ban has expired
    if ban['banned_until'] && Time.now.to_i > ban['banned_until']
      # Ban expired, deactivate it
      db = SQLite3::Database.new(@db_path)
      db.execute("UPDATE player_bans SET active = 0 WHERE id = ?", [ban['id']])
      db.close
      return false
    end

    true
  end

  # Helper: Find client by username
  def find_client_by_username(username)
    @clients.find { |id, info| info[:username]&.downcase == username.downcase }
  end

  # Helper: Check if user is ignoring another user
  def is_ignoring?(player_id, target_username)
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true

    result = db.execute(
      "SELECT COUNT(*) as count FROM player_ignores WHERE player_id = ? AND ignored_username = ?",
      [player_id, target_username.downcase]
    ).first
    db.close

    result['count'] > 0
  end

  # ============================================================================
  # PLAYER COMMANDS
  # ============================================================================

  def cmd_help(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]
    permission = get_player_permission(player_id)

    if args.empty?
      # Show all available commands
      send_server_message(client_id, "=== Available Commands ===")

      ServerConfig::COMMANDS.each do |cmd, config|
        next unless config[:enabled]
        next unless has_permission?(permission, config[:permission])

        aliases_str = config[:aliases] ? " (#{config[:aliases].map { |a| "/#{a}" }.join(', ')})" : ""
        send_server_message(client_id, "/#{cmd}#{aliases_str} - #{config[:description]}")
      end
    else
      # Show help for specific command
      cmd_sym = args.to_sym
      actual_cmd = ServerConfig.find_command_by_alias(cmd_sym) || cmd_sym
      config = ServerConfig::COMMANDS[actual_cmd]

      if config && config[:enabled]
        aliases_str = config[:aliases] ? " (Aliases: #{config[:aliases].map { |a| "/#{a}" }.join(', ')})" : ""
        send_server_message(client_id, "/#{actual_cmd}#{aliases_str} - #{config[:description]}")
      else
        send_server_message(client_id, "Unknown command: /#{args}")
      end
    end
  end

  def cmd_msg(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    parts = args.split(' ', 2)
    if parts.length < 2
      send_server_message(client_id, "Usage: /msg <player> <message>")
      return
    end

    target_username = parts[0]
    message = parts[1]

    target = find_client_by_username(target_username)
    unless target
      send_server_message(client_id, "Player '#{target_username}' not found.")
      return
    end

    target_id = target[0]
    target_player_id = target[1][:player_id]

    # Check if target is ignoring sender
    if is_ignoring?(target_player_id, username)
      send_server_message(client_id, "Message sent.") # Don't reveal they're ignored
      return
    end

    # Send PM to target
    send_to_client(target_id, {
      type: "chat_message",
      data: {
        username: "[PM from #{username}]",
        message: message,
        timestamp: Time.now.to_f,
        color: "MAGENTA"
      }
    })

    # Confirm to sender
    send_server_message(client_id, "[PM to #{target[1][:username]}] #{message}", color: "MAGENTA")

    # Track last PM sender for /reply
    @last_pm_sender[target_id] = username

    @logger.info "PM from #{username} to #{target[1][:username]}: #{message}"
  end

  def cmd_reply(client_id, args)
    username = @clients[client_id][:username]

    if args.empty?
      send_server_message(client_id, "Usage: /reply <message>")
      return
    end

    last_sender = @last_pm_sender[client_id]
    unless last_sender
      send_server_message(client_id, "No one has sent you a message yet.")
      return
    end

    # Use cmd_msg to send the reply
    cmd_msg(client_id, "#{last_sender} #{args}")
  end

  def cmd_online(client_id, args)
    online_players = @clients.select { |id, info| info[:username] }.map { |id, info| info[:username] }

    send_server_message(client_id, "=== Online Players (#{online_players.length}/#{@max_players}) ===")
    online_players.each do |name|
      send_server_message(client_id, "- #{name}")
    end
  end

  def cmd_time(client_id, args)
    server_time = Time.now
    send_server_message(client_id, "Server time: #{server_time.strftime('%Y-%m-%d %H:%M:%S %Z')}")
  end

  def cmd_spawn(client_id, args)
    username = @clients[client_id][:username]

    # Get server spawn point from config
    spawn = ServerConfig.get_spawn_position

    # Teleport player
    send_to_client(client_id, {
      type: "teleport",
      data: {
        map_id: spawn[:map_id].to_i,
        x: spawn[:x].to_i,
        y: spawn[:y].to_i
      }
    })

    send_server_message(client_id, "Teleported to spawn point (Map #{spawn[:map_id]} at #{spawn[:x]}, #{spawn[:y]}).")
    @logger.info "#{username} teleported to spawn"
  end

  def cmd_home(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    player = db.execute("SELECT home_map_id, home_x, home_y FROM players WHERE id = ?", [player_id]).first
    db.close

    unless player && player['home_map_id']
      send_server_message(client_id, "You haven't set a home yet. Use /sethome to set one.")
      return
    end

    # Teleport player
    send_to_client(client_id, {
      type: "teleport",
      data: {
        map_id: player['home_map_id'],
        x: player['home_x'],
        y: player['home_y']
      }
    })

    send_server_message(client_id, "Teleported to home.")
    @logger.info "#{username} teleported to home"
  end

  def cmd_sethome(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    # Get player's current position
    current_pos = @player_data[client_id]
    unless current_pos
      send_server_message(client_id, "Unable to get your current position.")
      return
    end

    # Save home position
    db = SQLite3::Database.new(@db_path)
    db.execute(
      "UPDATE players SET home_map_id = ?, home_x = ?, home_y = ? WHERE id = ?",
      [current_pos[:map_id], current_pos[:x], current_pos[:y], player_id]
    )
    db.close

    send_server_message(client_id, "Home set to your current location.")
    @logger.info "#{username} set home at map #{current_pos[:map_id]} (#{current_pos[:x]}, #{current_pos[:y]})"
  end

  def cmd_ping(client_id, args)
    # Send ping request and track time
    send_to_client(client_id, {
      type: "ping_request",
      data: {
        timestamp: Time.now.to_f
      }
    })
  end

  def cmd_stats(client_id, args)
    username = @clients[client_id][:username]

    # If args provided, show stats for that player, otherwise show own stats
    target_username = args.empty? ? username : args

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    player = db.execute("SELECT * FROM players WHERE username = ?", [target_username]).first
    db.close

    unless player
      send_server_message(client_id, "Player '#{target_username}' not found.")
      return
    end

    send_server_message(client_id, "=== Stats for #{target_username} ===")
    send_server_message(client_id, "Wins: #{player['wins'] || 0} | Losses: #{player['losses'] || 0}")
    send_server_message(client_id, "ELO: #{player['elo'] || 1000}")
    send_server_message(client_id, "Badges: #{player['badge_count'] || 0}/8")
    send_server_message(client_id, "Money: $#{player['money'] || 0}")
    send_server_message(client_id, "Total Trades: #{player['total_trades'] || 0}")
  end

  def cmd_badge(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    player = db.execute("SELECT badge_count, badges FROM players WHERE id = ?", [player_id]).first
    db.close

    badge_count = player['badge_count'] || 0
    send_server_message(client_id, "You have #{badge_count}/8 badges.")
  end

  def cmd_playtime(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    player = db.execute("SELECT created_at, playtime_seconds, session_start FROM players WHERE id = ?", [player_id]).first
    db.close

    if player
      begin
        # Calculate total playtime (stored + current session)
        total_playtime = (player['playtime_seconds'] || 0).to_i

        # Add current session time if logged in
        if player['session_start'] && !player['session_start'].to_s.empty?
          session_start_str = player['session_start'].to_s
          # Parse timestamp manually: "YYYY-MM-DD HH:MM:SS"
          if session_start_str =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/
            year, month, day, hour, min, sec = $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i
            session_start = Time.local(year, month, day, hour, min, sec)
            current_session = (Time.now - session_start).to_i
            total_playtime += current_session
          end
        end

        # Format playtime
        hours = total_playtime / 3600
        minutes = (total_playtime % 3600) / 60
        playtime_str = hours > 0 ? "#{hours}h #{minutes}m" : "#{minutes}m"

        # Account age
        if player['created_at'] && !player['created_at'].to_s.empty?
          created_str = player['created_at'].to_s
          # Parse timestamp manually
          if created_str =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/
            year, month, day, hour, min, sec = $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i
            created = Time.local(year, month, day, hour, min, sec)
            days = ((Time.now - created) / 86400).to_i

            send_server_message(client_id, "Total playtime: #{playtime_str}")
            send_server_message(client_id, "Account age: #{days} days")
          else
            send_server_message(client_id, "Total playtime: #{playtime_str}")
          end
        else
          send_server_message(client_id, "Total playtime: #{playtime_str}")
        end
      rescue => e
        @logger.error "Playtime command error: #{e.message}"
        @logger.error e.backtrace.join("\n")
        send_server_message(client_id, "Error retrieving playtime data")
      end
    end
  end

  def cmd_changepassword(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    # Parse arguments: /changepassword <old_password> <new_password>
    parts = args.split(' ', 2)
    if parts.length < 2
      send_server_message(client_id, "Usage: /changepassword <old_password> <new_password>")
      send_server_message(client_id, "Password must be at least #{ServerConfig::MIN_PASSWORD_LENGTH} characters.")
      return
    end

    old_password = parts[0]
    new_password = parts[1]

    # Validate new password length
    if new_password.length < ServerConfig::MIN_PASSWORD_LENGTH
      send_server_message(client_id, "New password must be at least #{ServerConfig::MIN_PASSWORD_LENGTH} characters.")
      return
    end

    begin
      db = SQLite3::Database.new(@db_path)
      db.results_as_hash = true

      # Get current password hash
      result = db.execute("SELECT password_hash FROM players WHERE id = ?", [player_id]).first

      unless result
        db.close
        send_server_message(client_id, "Error: Could not find your account.")
        return
      end

      # Verify old password
      old_password_hash = Digest::SHA256.hexdigest(old_password + username)
      if old_password_hash != result['password_hash']
        db.close
        send_server_message(client_id, "Incorrect current password. Password not changed.")
        @logger.warn "#{username} failed password change - wrong current password"
        return
      end

      # Create new password hash
      new_password_hash = Digest::SHA256.hexdigest(new_password + username)

      # Update password in database
      db.execute("UPDATE players SET password_hash = ? WHERE id = ?", [new_password_hash, player_id])
      db.close

      send_server_message(client_id, "Password changed successfully!")
      @logger.info "#{username} changed their password"

    rescue => e
      @logger.error "Password change error for #{username}: #{e.message}"
      send_server_message(client_id, "Error changing password. Please try again.")
    end
  end

  def cmd_ignore(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    if args.empty?
      send_server_message(client_id, "Usage: /ignore <player>")
      return
    end

    target_username = args.strip

    if target_username.downcase == username.downcase
      send_server_message(client_id, "You cannot ignore yourself.")
      return
    end

    # Check if player exists
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    target = db.execute("SELECT id FROM players WHERE username = ?", [target_username]).first

    unless target
      db.close
      send_server_message(client_id, "Player '#{target_username}' not found.")
      return
    end

    # Add to ignore list
    begin
      db.execute(
        "INSERT OR IGNORE INTO player_ignores (player_id, ignored_username) VALUES (?, ?)",
        [player_id, target_username.downcase]
      )
      db.close
      send_server_message(client_id, "You are now ignoring #{target_username}.")
      @logger.info "#{username} is now ignoring #{target_username}"
    rescue => e
      db.close
      send_server_message(client_id, "Failed to ignore player: #{e.message}")
    end
  end

  def cmd_unignore(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    if args.empty?
      send_server_message(client_id, "Usage: /unignore <player>")
      return
    end

    target_username = args.strip

    db = SQLite3::Database.new(@db_path)
    db.execute(
      "DELETE FROM player_ignores WHERE player_id = ? AND ignored_username = ?",
      [player_id, target_username.downcase]
    )
    db.close

    send_server_message(client_id, "You are no longer ignoring #{target_username}.")
    @logger.info "#{username} is no longer ignoring #{target_username}"
  end

  # ============================================================================
  # MODERATOR COMMANDS
  # ============================================================================

  def cmd_mute(client_id, args)
    username = @clients[client_id][:username]

    parts = args.split(' ')
    if parts.empty?
      send_server_message(client_id, "Usage: /mute <player> [duration_minutes] [reason]")
      return
    end

    target_username = parts[0]
    duration = parts[1] ? parts[1].to_i : ServerConfig::DEFAULT_MUTE_DURATION
    reason = parts[2..-1].join(' ') if parts.length > 2

    # Find target player
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    target = db.execute("SELECT id FROM players WHERE username = ?", [target_username]).first

    unless target
      db.close
      send_server_message(client_id, "Player '#{target_username}' not found.")
      return
    end

    target_id = target['id']
    muted_until = duration > 0 ? (Time.now.to_i + (duration * 60)) : nil

    # Deactivate any existing mutes
    db.execute("UPDATE player_mutes SET active = 0 WHERE player_id = ?", [target_id])

    # Add new mute
    db.execute(
      "INSERT INTO player_mutes (player_id, username, muted_by, reason, muted_at, muted_until, active) VALUES (?, ?, ?, ?, ?, ?, 1)",
      [target_id, target_username, username, reason, Time.now.to_i, muted_until]
    )
    db.close

    duration_str = duration > 0 ? "for #{duration} minutes" : "permanently"
    reason_str = reason ? " (Reason: #{reason})" : ""

    send_server_message(client_id, "Muted #{target_username} #{duration_str}#{reason_str}")

    # Notify target if online
    target_client = find_client_by_username(target_username)
    if target_client
      send_server_message(target_client[0], "You have been muted #{duration_str}#{reason_str}")
    end

    @logger.info "#{username} muted #{target_username} #{duration_str}#{reason_str}"
  end

  def cmd_unmute(client_id, args)
    username = @clients[client_id][:username]

    if args.empty?
      send_server_message(client_id, "Usage: /unmute <player>")
      return
    end

    target_username = args.strip

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    target = db.execute("SELECT id FROM players WHERE username = ?", [target_username]).first

    unless target
      db.close
      send_server_message(client_id, "Player '#{target_username}' not found.")
      return
    end

    # Deactivate all mutes
    db.execute("UPDATE player_mutes SET active = 0 WHERE player_id = ?", [target['id']])
    db.close

    send_server_message(client_id, "Unmuted #{target_username}.")

    # Notify target if online
    target_client = find_client_by_username(target_username)
    if target_client
      send_server_message(target_client[0], "You have been unmuted.")
    end

    @logger.info "#{username} unmuted #{target_username}"
  end

  def cmd_kick(client_id, args)
    username = @clients[client_id][:username]

    parts = args.split(' ', 2)
    if parts.empty?
      send_server_message(client_id, "Usage: /kick <player> [reason]")
      return
    end

    target_username = parts[0]
    reason = parts[1] || "No reason provided"

    target = find_client_by_username(target_username)
    unless target
      send_server_message(client_id, "Player '#{target_username}' not found.")
      return
    end

    target_id = target[0]

    # Send kick message
    send_server_message(target_id, "You have been kicked by #{username}. Reason: #{reason}")

    # Disconnect player
    disconnect_client(target_id, "Kicked by #{username}: #{reason}")

    send_server_message(client_id, "Kicked #{target_username}.")
    @logger.info "#{username} kicked #{target_username}: #{reason}"
  end

  def cmd_warn(client_id, args)
    username = @clients[client_id][:username]

    parts = args.split(' ', 2)
    if parts.length < 2
      send_server_message(client_id, "Usage: /warn <player> <message>")
      return
    end

    target_username = parts[0]
    warning = parts[1]

    target = find_client_by_username(target_username)
    unless target
      send_server_message(client_id, "Player '#{target_username}' not found.")
      return
    end

    target_id = target[0]

    # Send warning
    send_to_client(target_id, {
      type: "chat_message",
      data: {
        username: "[WARNING from #{username}]",
        message: warning,
        timestamp: Time.now.to_f,
        color: "RED"
      }
    })

    send_server_message(client_id, "Warned #{target_username}.")
    @logger.info "#{username} warned #{target_username}: #{warning}"
  end

  # ============================================================================
  # ADMIN COMMANDS
  # ============================================================================

  def cmd_ban(client_id, args)
    username = @clients[client_id][:username]

    parts = args.split(' ')
    if parts.empty?
      send_server_message(client_id, "Usage: /ban <player> [duration_minutes] [reason]")
      return
    end

    target_username = parts[0]
    duration = parts[1] ? parts[1].to_i : ServerConfig::DEFAULT_BAN_DURATION
    reason = parts[2..-1].join(' ') if parts.length > 2

    # Find target player
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    target = db.execute("SELECT id FROM players WHERE username = ?", [target_username]).first

    unless target
      db.close
      send_server_message(client_id, "Player '#{target_username}' not found.")
      return
    end

    target_id = target['id']
    banned_until = duration > 0 ? (Time.now.to_i + (duration * 60)) : nil

    # Deactivate any existing bans
    db.execute("UPDATE player_bans SET active = 0 WHERE player_id = ?", [target_id])

    # Add new ban
    db.execute(
      "INSERT INTO player_bans (player_id, username, banned_by, reason, banned_at, banned_until, active) VALUES (?, ?, ?, ?, ?, ?, 1)",
      [target_id, target_username, username, reason, Time.now.to_i, banned_until]
    )
    db.close

    duration_str = duration > 0 ? "for #{duration} minutes" : "permanently"
    reason_str = reason ? " (Reason: #{reason})" : ""

    send_server_message(client_id, "Banned #{target_username} #{duration_str}#{reason_str}")

    # Kick player if online - IMMEDIATELY disconnect them
    target_client = find_client_by_username(target_username)
    if target_client
      target_client_id = target_client[0]

      # Send error message with ban reason (causes client to show disconnect screen)
      send_to_client(target_client_id, {
        type: "error",
        data: {
          error_type: "banned",
          message: "You have been banned #{duration_str}#{reason_str}\nContact an administrator for more information.",
          ban_duration: duration,
          banned_by: username
        }
      })

      # Wait a moment for message to be sent, then force disconnect
      sleep(0.1)

      # Close socket immediately to kick player
      socket = @clients[target_client_id][:socket]
      if socket && !socket.closed?
        socket.close rescue nil
      end

      # Clean up client data
      disconnect_client(target_client_id)

      @logger.info "[BAN] Kicked #{target_username} (client ##{target_client_id}) immediately"
    end

    @logger.info "#{username} banned #{target_username} #{duration_str}#{reason_str}"
  end

  def cmd_unban(client_id, args)
    username = @clients[client_id][:username]

    if args.empty?
      send_server_message(client_id, "Usage: /unban <player>")
      return
    end

    target_username = args.strip

    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    target = db.execute("SELECT id FROM players WHERE username = ?", [target_username]).first

    unless target
      db.close
      send_server_message(client_id, "Player '#{target_username}' not found.")
      return
    end

    # Deactivate all bans
    db.execute("UPDATE player_bans SET active = 0 WHERE player_id = ?", [target['id']])
    db.close

    send_server_message(client_id, "Unbanned #{target_username}.")
    @logger.info "#{username} unbanned #{target_username}"
  end

  def cmd_give(client_id, args)
    username = @clients[client_id][:username]

    parts = args.split(' ')
    if parts.length < 3
      send_server_message(client_id, "Usage: /give <player> <item|pokemon> <id> [amount|level]")
      return
    end

    target_username = parts[0]
    give_type = parts[1].downcase
    item_id = parts[2]
    amount_or_level = parts[3] ? parts[3].to_i : 1

    target = find_client_by_username(target_username)
    unless target
      send_server_message(client_id, "Player '#{target_username}' not online.")
      return
    end

    target_id = target[0]

    case give_type
    when 'item'
      # Give item
      send_to_client(target_id, {
        type: "admin_give_item",
        data: {
          item_id: item_id,
          quantity: amount_or_level
        }
      })
      send_server_message(client_id, "Gave #{amount_or_level}x #{item_id} to #{target_username}.")
      send_server_message(target_id, "You received #{amount_or_level}x #{item_id} from an admin.")
      @logger.info "#{username} gave #{amount_or_level}x #{item_id} to #{target_username}"

    when 'pokemon', 'pkmn'
      # Give Pokemon
      send_to_client(target_id, {
        type: "admin_give_pokemon",
        data: {
          species: item_id,
          level: amount_or_level
        }
      })
      send_server_message(client_id, "Gave level #{amount_or_level} #{item_id} to #{target_username}.")
      send_server_message(target_id, "You received a level #{amount_or_level} #{item_id} from an admin.")
      @logger.info "#{username} gave level #{amount_or_level} #{item_id} to #{target_username}"

    else
      send_server_message(client_id, "Invalid type. Use 'item' or 'pokemon'.")
    end
  end

  def cmd_tp(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    # Check if player is admin for forced teleport
    permission = get_player_permission(player_id)
    is_admin = has_permission?(permission, :admin)

    if args.empty?
      send_server_message(client_id, "Usage: /tp <player> (Admin only - Use /tpa for teleport requests)")
      return
    end

    unless is_admin
      send_server_message(client_id, "Only admins can use /tp. Use /tpa <player> to send a teleport request.")
      return
    end

    target_username = args.strip

    target = find_client_by_username(target_username)
    unless target
      send_server_message(client_id, "Player '#{target_username}' not online.")
      return
    end

    target_id = target[0]
    target_player_id = target[1][:player_id]
    target_pos = @player_data[target_id]

    unless target_pos
      send_server_message(client_id, "Unable to get #{target_username}'s position.")
      return
    end

    # Admins bypass badge restrictions

    # Teleport player
    send_to_client(client_id, {
      type: "teleport",
      data: {
        map_id: target_pos[:map_id],
        x: target_pos[:x],
        y: target_pos[:y]
      }
    })

    send_server_message(client_id, "Teleported to #{target_username}.")
    send_server_message(target_id, "#{username} (Admin) teleported to you.")
    @logger.info "#{username} (Admin) teleported to #{target_username}"
  end

  def cmd_tpa(client_id, args)
    username = @clients[client_id][:username]
    player_id = @clients[client_id][:player_id]

    if args.empty?
      send_server_message(client_id, "Usage: /tpa <player>")
      return
    end

    target_username = args.strip

    target = find_client_by_username(target_username)
    unless target
      send_server_message(client_id, "Player '#{target_username}' not online.")
      return
    end

    target_id = target[0]
    target_player_id = target[1][:player_id]

    # Can't teleport to yourself
    if target_id == client_id
      send_server_message(client_id, "You cannot teleport to yourself.")
      return
    end

    # Badge restriction: Can only TP to players with same or fewer badges
    db = SQLite3::Database.new(@db_path)
    db.results_as_hash = true
    my_badges = db.execute("SELECT badge_count FROM players WHERE id = ?", [player_id]).first
    target_badges = db.execute("SELECT badge_count FROM players WHERE id = ?", [target_player_id]).first
    db.close

    my_badge_count = my_badges ? (my_badges['badge_count'] || 0) : 0
    target_badge_count = target_badges ? (target_badges['badge_count'] || 0) : 0

    if target_badge_count > my_badge_count
      send_server_message(client_id, "You cannot teleport to #{target_username} - they have more badges than you (#{target_badge_count} vs #{my_badge_count}).")
      return
    end

    # Clean up expired requests
    clean_expired_tp_requests

    # Check if target already has a pending request
    if @tp_requests[target_id] && @tp_requests[target_id][:expires_at] > Time.now
      send_server_message(client_id, "#{target_username} already has a pending teleport request. Please wait.")
      return
    end

    # Create request with 60 second expiry
    @tp_requests[target_id] = {
      requester_id: client_id,
      requester_username: username,
      expires_at: Time.now + 60
    }

    send_server_message(client_id, "Teleport request sent to #{target_username}. They have 60 seconds to respond.")
    send_server_message(target_id, "#{username} wants to teleport to you. Use /tpaccept to accept or /tpdeny to deny. (60s)", color: "YELLOW")
    @logger.info "#{username} sent teleport request to #{target_username}"
  end

  def cmd_tpaccept(client_id, args)
    username = @clients[client_id][:username]

    # Check if there's a pending request
    request = @tp_requests[client_id]

    unless request
      send_server_message(client_id, "You have no pending teleport requests.")
      return
    end

    # Check if request expired
    if request[:expires_at] < Time.now
      @tp_requests.delete(client_id)
      send_server_message(client_id, "The teleport request has expired.")
      return
    end

    requester_id = request[:requester_id]
    requester_username = request[:requester_username]

    # Check if requester is still online
    unless @clients[requester_id]
      @tp_requests.delete(client_id)
      send_server_message(client_id, "#{requester_username} is no longer online.")
      return
    end

    # Get target position
    target_pos = @player_data[client_id]

    unless target_pos
      send_server_message(client_id, "Unable to get your position.")
      @tp_requests.delete(client_id)
      return
    end

    # Teleport requester to target
    send_to_client(requester_id, {
      type: "teleport",
      data: {
        map_id: target_pos[:map_id],
        x: target_pos[:x],
        y: target_pos[:y]
      }
    })

    send_server_message(requester_id, "Teleport request accepted! Teleporting to #{username}...")
    send_server_message(client_id, "You accepted #{requester_username}'s teleport request.")
    @logger.info "#{username} accepted teleport request from #{requester_username}"

    # Clean up request
    @tp_requests.delete(client_id)
  end

  def cmd_tpdeny(client_id, args)
    username = @clients[client_id][:username]

    # Check if there's a pending request
    request = @tp_requests[client_id]

    unless request
      send_server_message(client_id, "You have no pending teleport requests.")
      return
    end

    requester_id = request[:requester_id]
    requester_username = request[:requester_username]

    # Notify both players
    if @clients[requester_id]
      send_server_message(requester_id, "#{username} denied your teleport request.")
    end
    send_server_message(client_id, "You denied #{requester_username}'s teleport request.")
    @logger.info "#{username} denied teleport request from #{requester_username}"

    # Clean up request
    @tp_requests.delete(client_id)
  end

  def clean_expired_tp_requests
    @tp_requests.delete_if { |_, request| request[:expires_at] < Time.now }
  end

  def cmd_summon(client_id, args)
    username = @clients[client_id][:username]

    if args.empty?
      send_server_message(client_id, "Usage: /summon <player>")
      return
    end

    target_username = args.strip

    target = find_client_by_username(target_username)
    unless target
      send_server_message(client_id, "Player '#{target_username}' not online.")
      return
    end

    target_id = target[0]
    my_pos = @player_data[client_id]

    unless my_pos
      send_server_message(client_id, "Unable to get your position.")
      return
    end

    # Teleport target to you
    send_to_client(target_id, {
      type: "teleport",
      data: {
        map_id: my_pos[:map_id],
        x: my_pos[:x],
        y: my_pos[:y]
      }
    })

    send_server_message(client_id, "Summoned #{target_username} to you.")
    send_server_message(target_id, "You were summoned by #{username}.")
    @logger.info "#{username} summoned #{target_username}"
  end

  def cmd_setspawn(client_id, args)
    username = @clients[client_id][:username]

    # Get current position
    my_pos = @player_data[client_id]
    unless my_pos
      send_server_message(client_id, "Unable to get your position.")
      return
    end

    spawn_data = {
      map_id: my_pos[:map_id],
      x: my_pos[:x],
      y: my_pos[:y]
    }

    db = SQLite3::Database.new(@db_path)
    db.execute(
      "INSERT OR REPLACE INTO server_settings (key, value) VALUES ('spawn_point', ?)",
      [spawn_data.to_json]
    )
    db.close

    send_server_message(client_id, "Server spawn point set to your current location.")
    @logger.info "#{username} set server spawn to map #{my_pos[:map_id]} (#{my_pos[:x]}, #{my_pos[:y]})"
  end

  def cmd_settime(client_id, args)
    username = @clients[client_id][:username]

    if args.empty?
      send_server_message(client_id, "Usage: /settime <hour> (0-23)")
      return
    end

    hour = args.to_i
    unless hour >= 0 && hour <= 23
      send_server_message(client_id, "Hour must be between 0 and 23.")
      return
    end

    # Broadcast time change to all clients
    broadcast({
      type: "time_set",
      data: {
        hour: hour
      }
    })

    send_server_message(client_id, "Server time set to #{hour}:00.")
    @logger.info "#{username} set server time to #{hour}:00"
  end

  def cmd_broadcast(client_id, args)
    username = @clients[client_id][:username]

    if args.empty?
      send_server_message(client_id, "Usage: /broadcast <message>")
      return
    end

    # Broadcast to all players
    broadcast({
      type: "chat_message",
      data: {
        username: "[ANNOUNCEMENT]",
        message: args,
        timestamp: Time.now.to_f,
        color: "RED"
      }
    })

    @logger.info "#{username} broadcast: #{args}"
  end

  def cmd_heal(client_id, args)
    username = @clients[client_id][:username]

    target_username = args.empty? ? username : args.strip

    target = find_client_by_username(target_username)
    unless target
      send_server_message(client_id, "Player '#{target_username}' not online.")
      return
    end

    target_id = target[0]

    # Send heal command to client
    send_to_client(target_id, {
      type: "admin_heal",
      data: {}
    })

    send_server_message(client_id, "Healed #{target_username}'s Pokemon.")
    if target_id != client_id
      send_server_message(target_id, "Your Pokemon were healed by an admin.")
    end
    @logger.info "#{username} healed #{target_username}'s Pokemon"
  end

  def cmd_setmoney(client_id, args)
    username = @clients[client_id][:username]

    parts = args.split(' ')
    if parts.length < 2
      send_server_message(client_id, "Usage: /setmoney <player> <amount>")
      return
    end

    target_username = parts[0]
    amount = parts[1].to_i

    target = find_client_by_username(target_username)
    unless target
      send_server_message(client_id, "Player '#{target_username}' not online.")
      return
    end

    target_id = target[0]
    target_player_id = target[1][:player_id]

    # Update in database
    db = SQLite3::Database.new(@db_path)
    db.execute("UPDATE players SET money = ? WHERE id = ?", [amount, target_player_id])
    db.close

    # Update in memory
    if @player_data[target_id]
      @player_data[target_id][:money] = amount
    end

    # Notify client to update money
    send_to_client(target_id, {
      type: "admin_setmoney",
      data: {
        money: amount
      }
    })

    send_server_message(client_id, "Set #{target_username}'s money to $#{amount}.")
    send_server_message(target_id, "Your money was set to $#{amount} by an admin.")
    @logger.info "#{username} set #{target_username}'s money to $#{amount}"
  end

  def cmd_maintenance(client_id, args)
    username = @clients[client_id][:username]

    @maintenance_mode = !@maintenance_mode

    status = @maintenance_mode ? "enabled" : "disabled"
    send_server_message(client_id, "Maintenance mode #{status}.")

    if @maintenance_mode
      # Notify all non-admin players
      @clients.each do |id, info|
        next unless info[:username]
        next if get_player_permission(info[:player_id]) == :admin

        send_server_message(id, "Server is entering maintenance mode. Please finish up.")
      end
    end

    @logger.info "#{username} #{status} maintenance mode"
  end

end

# Parse command line options
options = {
  port: MultiplayerServer::DEFAULT_PORT,
  max_players: MultiplayerServer::DEFAULT_MAX_PLAYERS,
  debug: false
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby multiplayer_server.rb [options]"

  opts.on("-p", "--port PORT", Integer, "Server port (default: #{options[:port]})") do |p|
    options[:port] = p
  end

  opts.on("-m", "--max-players MAX", Integer, "Maximum players (default: #{options[:max_players]})") do |m|
    options[:max_players] = m
  end

  opts.on("-d", "--debug", "Enable debug logging") do
    options[:debug] = true
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Start server
log_level = options[:debug] ? Logger::DEBUG : Logger::INFO
server = MultiplayerServer.new(
  port: options[:port],
  max_players: options[:max_players],
  log_level: log_level
)

server.start
