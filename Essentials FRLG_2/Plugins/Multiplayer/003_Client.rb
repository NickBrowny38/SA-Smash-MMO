begin
  require 'socket' unless defined?(TCPSocket)
  require 'thread' unless defined?(Thread)
rescue LoadError => e
  puts "Warning: Could not load required library: #{e.message}"
  puts "Multiplayer functionality will not be available."
end

class MultiplayerClient
  attr_reader :connected, :username, :remote_players, :my_client_id, :social_player_list
  attr_accessor :client_id

  def initialize
    @socket = nil
    @connected  =  false
    @username = nil
    @my_client_id = nil
    @server_host = nil
    @server_port = nil
    @remote_players = {}
    @social_player_list = []
    @message_queue = Queue.new
    @receive_thread  =  nil
    @heartbeat_thread = nil
    @last_position_update = 0
    @position_update_interval = 0.05
    @disconnected_during_battle = false
    @server_data_loaded = false
  end

  def connect(host, port, username, password = nil)
    return false if @connected

    begin

      connection_thread = Thread.new do        begin
          TCPSocket.new(host, port)
        rescue => e
          e
        end
      end

      timeout_counter = 0
      max_wait = 50

      while timeout_counter < max_wait
        if connection_thread.alive?
          sleep(0.1)
          timeout_counter += 1
        else
          break
        end
      end

      if connection_thread.alive?
        connection_thread.kill
        puts "Connection timed out - server may be offline"
        @connected = false
        return false
      end

      result = connection_thread.value
      if result.is_a?(Exception)
        raise result
      end

      @socket = result
      @server_host = host
      @server_port = port
      @username = username
      @connected = true

      @receive_thread = Thread.new { receive_loop }

      @heartbeat_thread = Thread.new { heartbeat_loop }

      send_message(MultiplayerProtocol.connect_message(username, password))

      puts "Connected to multiplayer server at #{host}:#{port}"
      return true
    rescue Errno::ECONNREFUSED
      puts "Connection refused - server is not running"
      @connected = false
      @socket = nil
      return false
    rescue => e
      puts "Failed to connect to server: #{e.message}"
      @connected = false
      @socket.close if @socket rescue nil
      @socket = nil
      return false
    end
  end

  def connected?
    @connected
  end

  def disconnect
    return unless @connected

    begin

      if defined?($game_temp) && $game_temp && $game_temp.in_battle
        puts 'Disconnected during battle - will be treated as forfeit on reconnect'
        @disconnected_during_battle = true
      end

      send_player_data

      send_message(MultiplayerProtocol.create_message("disconnect"))
      @socket.close if @socket
    rescue

    ensure

      was_connected = @connected
      @connected = false
      @socket = nil
      @my_client_id = nil
      @server_data_loaded = false
      @receive_thread.kill if @receive_thread
      @receive_thread = nil
      @heartbeat_thread.kill if @heartbeat_thread
      @heartbeat_thread = nil
      @remote_players.clear
      puts 'Disconnected from multiplayer server' if was_connected
    end
  end

  def update
    return unless @connected

    until @message_queue.empty?
      begin
        message = @message_queue.pop(true)
        process_message(message)
      rescue ThreadError
        break
      end
    end

    if defined?($stats) && $stats && defined?(pbGetMultiplayerPlaytime)
      $stats.play_time = pbGetMultiplayerPlaytime
    end

    send_position_update

    if Graphics.frame_count % (60 * Graphics.frame_rate) == 0
      send_player_data
    end

    check_pending_teleport
  end

  def heartbeat_loop
    loop do      break unless @connected

      begin

        sleep(20)
        send_heartbeat if @connected
      rescue => e
        puts "Heartbeat thread error: #{e.message}"
        break
      end
    end
  end

  def send_position_update
    return unless @connected
    return unless $game_player
    return unless $player

    player_data  =  {
      map_id: $game_player.map.map_id,
      x: $game_player.x,
      y: $game_player.y,
      real_x: $game_player.real_x,
      real_y: $game_player.real_y,
      direction: $game_player.direction,
      pattern: $game_player.pattern,
      move_speed: $game_player.move_speed,
      movement_type: get_movement_type,
      charset: get_charset_name
    }

    # Include money and badges in position updates for real-time sync
    if @server_data_loaded && $player
      player_data[:money] = $player.money.to_i if $player.respond_to?(:money)
      player_data[:badge_count] = $player.badge_count.to_i if $player.respond_to?(:badge_count)
    end

    send_message(MultiplayerProtocol.position_update_message(player_data))
  end

  def send_chat_message(message)
    return unless @connected

    send_message(MultiplayerProtocol.create_message("chat_message", {
      message: message
    }))
  end

  def send_heartbeat
    return unless @connected

    send_message(MultiplayerProtocol.create_message('heartbeat'))
  end

  def send_follower_update
    return unless @connected
    return unless $player

    follower_data = nil
    if defined?(FollowingPkmn) && FollowingPkmn.respond_to?(:active?) && FollowingPkmn.active?
      pkmn = FollowingPkmn.get_pokemon if FollowingPkmn.respond_to?(:get_pokemon)
      if pkmn
        follower_data = {
          species: pkmn.species,
          shiny: pkmn.shiny?,
          form: pkmn.form
        }
        puts "[Following] Sending follower update: #{pkmn.species}"
      else
        puts "[Following] Follower removed (was #{@last_follower_species}), sending nil"
        @last_follower_species  =  nil
      end
    else
      puts "[Following] Follower removed (FollowingPkmn not active), sending nil"
    end

    send_message(MultiplayerProtocol.create_message("follower_update", {
      follower: follower_data
    }))

    @last_follower_species = follower_data ? follower_data[:species] : nil
  end

  def send_player_data
    return unless @connected
    return unless $player && $bag

    bag_data = []
    if $bag
      $bag.pockets.each do |pocket|
        pocket.each do |item|
          bag_data << {
            item_id: item[0],
            quantity: item[1]
          }
        end
      end
    end

    pokemon_data = []
    if $player && $player.party
      $player.party.each do |pkmn|
        next unless pkmn

        if defined?(pbModernTradeManager)
          pokemon_data << pbModernTradeManager.serialize_pokemon(pkmn)
        else

          pokemon_data << {
            species: pkmn.species,
            level: pkmn.level,
            name: pkmn.name,
            hp: pkmn.hp,
            status: pkmn.status,
            exp: pkmn.exp
          }
        end
      end
    end

    picked_up_items = []
    if defined?(pbMultiplayerItemPersistence) && pbMultiplayerItemPersistence
      picked_up_items  =  pbMultiplayerItemPersistence.get_picked_up_items
    end

    pc_boxes = []
    if defined?($PokemonStorage) && $PokemonStorage
      $PokemonStorage.maxBoxes.times do |box_idx|
        box_data = {
          box_number: box_idx,
          box_name: $PokemonStorage[box_idx].name,
          pokemon: []
        }

        PokemonBox::BOX_SIZE.times do |slot_idx|
          pkmn = $PokemonStorage[box_idx, slot_idx]
          next unless pkmn

          if defined?(pbModernTradeManager)
            box_data[:pokemon] << {
              slot: slot_idx,
              data: pbModernTradeManager.serialize_pokemon(pkmn)
            }
          else
            box_data[:pokemon] << {
              slot: slot_idx,
              data: {
                species: pkmn.species,
                level: pkmn.level,
                name: pkmn.name,
                hp: pkmn.hp,
                status: pkmn.status,
                exp: pkmn.exp
              }
            }
          end
        end

        pc_boxes << box_data unless box_data[:pokemon].empty?
      end
    end

    save_data = {
      bag: bag_data,
      pokemon: pokemon_data,
      pc_boxes: pc_boxes,
      picked_up_items: picked_up_items
    }

    if $player

      if @server_data_loaded

        save_data[:money]  =  $player.money.to_i if $player.respond_to?(:money)

        save_data[:badge_count] = $player.badge_count.to_i if $player.respond_to?(:badge_count)

        if $player.respond_to?(:badges) && $player.badges
          save_data[:badges] = $player.badges
        end

        if $player.respond_to?(:pokedex) && $player.pokedex
          pokedex_data = {}
          begin

            GameData::Species.each do |species_data|
              next if species_data.form != 0
              species_symbol = species_data.species
              seen  =  $player.pokedex.seen?(species_symbol)
              owned = $player.pokedex.owned?(species_symbol)
              if seen || owned

                pokedex_data[species_symbol.to_s] = {
                  seen: seen ? 1 : 0,
                  owned: owned ? 1 : 0
                }
              end
            end
            save_data[:pokedex] = pokedex_data unless pokedex_data.empty?
          rescue => e
            puts "[SAVE] Error serializing Pokedex: #{e.message}"
            puts e.backtrace[0..5].join('\n')
          end
        end
      end

      begin
        has_shoes = $player.has_running_shoes
        save_data[:has_running_shoes] = (has_shoes == true) ? 1 : 0
      rescue
        save_data[:has_running_shoes] = 0
      end
    end

    if defined?($game_switches) && $game_switches

      switches_data = {}
      begin

        switches_collection = $game_switches.instance_variable_get(:@data)
        if switches_collection
          if switches_collection.is_a?(Hash)

            switches_collection.each do |key, value|
              switches_data[key.to_s] = value if value
            end
          elsif switches_collection.is_a?(Array)

            switches_collection.each_with_index do |value, index|
              switches_data[index.to_s] = value if value && index > 0
            end
          end
        end
      rescue => e
        puts "[SAVE] Error serializing switches: #{e.message}"
      end
      save_data[:switches] = switches_data unless switches_data.empty?
    end

    if defined?($game_variables) && $game_variables

      variables_data = {}
      begin

        variables_collection = $game_variables.instance_variable_get(:@data)
        if variables_collection
          if variables_collection.is_a?(Hash)

            variables_collection.each do |key, value|
              variables_data[key.to_s] = value if value && value != 0
            end
          elsif variables_collection.is_a?(Array)

            variables_collection.each_with_index do |value, index|
              variables_data[index.to_s] = value if value && value != 0 && index > 0
            end
          end
        end
      rescue => e
        puts "[SAVE] Error serializing variables: #{e.message}"
      end
      save_data[:variables] = variables_data unless variables_data.empty?
    end

    if defined?($game_self_switches) && $game_self_switches

      self_switches_data = {}
      begin

        self_switches_hash = $game_self_switches.instance_variable_get(:@data)
        if self_switches_hash && self_switches_hash.is_a?(Hash)
          self_switches_hash.each do |key, value|
            if value && key.is_a?(Array) && key.length == 3

              key_str = "#{key[0]}_#{key[1]}_#{key[2]}"
              self_switches_data[key_str] = value
            end
          end
        end
      rescue => e
        puts "[SAVE] Error serializing self_switches: #{e.message}"
      end
      save_data[:self_switches] = self_switches_data unless self_switches_data.empty?
    end

    if $game_player && $game_player.map
      save_data[:map_id] = $game_player.map.map_id
      save_data[:x] = $game_player.x
      save_data[:y] = $game_player.y
      shoes_status = $player && $player.has_running_shoes ? "shoes" : "no shoes"
      total_pc_pokemon = pc_boxes.sum { |box| box[:pokemon].size }
      puts "Sent player data: #{bag_data.size} items, #{pokemon_data.size} Pokemon, #{pc_boxes.size} PC boxes (#{total_pc_pokemon} Pokemon), #{picked_up_items.size} picked items, #{shoes_status}, position: Map #{save_data[:map_id]} (#{save_data[:x]}, #{save_data[:y]})"
    else
      total_pc_pokemon = pc_boxes.sum { |box| box[:pokemon].size }
      puts "Sent player data: #{bag_data.size} items, #{pokemon_data.size} Pokemon, #{pc_boxes.size} PC boxes (#{total_pc_pokemon} Pokemon), #{picked_up_items.size} picked items, position: NONE (player not on map yet)"
    end

    if defined?(FollowingPkmn) && FollowingPkmn.respond_to?(:active?) && FollowingPkmn.active?
      pkmn = FollowingPkmn.get_pokemon if FollowingPkmn.respond_to?(:get_pokemon)
      if pkmn
        save_data[:follower] = {
          species: pkmn.species,
          shiny: pkmn.shiny?,
          form: pkmn.form
        }
        puts "[Following] Added follower to player data: #{pkmn.species}"
      end
    end

    send_message(MultiplayerProtocol.create_message('save_data', save_data))
  end

  def get_remote_players_on_map(map_id)
    @remote_players.values.select { |p| p[:map_id] == map_id }
  end

  private

  def send_message(message)

    is_trade_msg  =  message[:type].to_s.include?("trade")
    puts "[SEND_MESSAGE] Called with message type: #{message[:type]}" if is_trade_msg

    unless @connected
      puts "[SEND_MESSAGE] Not connected!" if is_trade_msg
      return
    end
    unless @socket
      puts '[SEND_MESSAGE] No socket!' if is_trade_msg
      return
    end

    begin
      puts "[SEND_MESSAGE] Serializing message..." if is_trade_msg
      json = MultiplayerProtocol.serialize(message)
      puts "[SEND_MESSAGE] JSON length: #{json.length} bytes" if is_trade_msg
      puts '[SEND_MESSAGE] Writing to socket...' if is_trade_msg
      @socket.write(json)
      @socket.flush
      puts '[SEND_MESSAGE] Write successful and flushed!' if is_trade_msg
    rescue => e
      puts "[SEND_MESSAGE] ERROR: #{e.message}"
      puts "[SEND_MESSAGE] Backtrace: #{e.backtrace.first(3).join("\n")}"
      disconnect
    end
  end

  alias send_json_message send_message

  def receive_loop
    loop do      break unless @connected
      break unless @socket

      begin
        line  =  @socket.gets
        break if line.nil?

        line.strip!
        next if line.empty?

        message = MultiplayerProtocol.deserialize(line)
        @message_queue.push(message) if message
      rescue => e
        puts "Error receiving message: #{e.message}"
        break
      end
    end

    disconnect
  end

  def process_message(message)

    msg_type = message[:type] || message['type']
    msg_data = message[:data] || message['data'] || message

    case msg_type
    when "connected"
      handle_connected(msg_data)

    when "player_list"
      handle_player_list(msg_data)

    when "player_joined", "player_join"
      handle_player_joined(msg_data)

    when "player_left", "player_leave"
      handle_player_left(msg_data)

    when "position_update", "player_move"
      handle_position_update(msg_data)

    when "follower_update"
      handle_follower_update(msg_data)

    when "player_data"
      handle_player_data(msg_data)

    when "chat_message", "chat"
      handle_chat_message(msg_data)

    when "error"
      handle_error(msg_data)

    when "update_available"
      handle_update_available(msg_data)

    when "battle_request"
      handle_battle_request(msg_data)

    when "battle_request_sent"
      handle_battle_request_sent(msg_data)

    when "battle_declined"
      handle_battle_declined(msg_data)

    when "battle_accepted"
      handle_battle_accepted_msg(msg_data)

    when 'battle_start'
      handle_battle_start_msg(msg_data)

    when "battle_start_sync"
      handle_battle_start_sync_msg(msg_data)

    when "battle_opponent_choice"
      handle_battle_opponent_choice_msg(msg_data)

    when "battle_ready"
      handle_battle_ready_msg(msg_data)

    when "battle_switch"
      handle_battle_switch_msg(msg_data)

    when "trade_offer"
      puts "[CLIENT DEBUG] Received 'trade_offer' message type"
      handle_trade_offer_received(msg_data)

    when "trade_offer_sent"
      handle_trade_offer_sent(msg_data)

    when 'trade_accepted'
      handle_trade_accepted(msg_data)

    when 'trade_declined'
      handle_trade_declined(msg_data)

    when "trade_complete"
      handle_trade_complete(msg_data)

    when "trade_offer_v2"
      handle_trade_offer_v2(msg_data)

    when "trade_counter_offer_v2"
      handle_trade_counter_offer_v2(msg_data)

    when "trade_confirm_v2"
      handle_trade_confirm_v2(msg_data)

    when "trade_decline_v2"
      handle_trade_decline_v2(msg_data)

    when 'trade_change_offer_v2'
      handle_trade_change_offer_v2(msg_data)

    when 'execute_trade_v2'
      handle_execute_trade_v2(msg_data)

    when "social_data"
      handle_social_data(msg_data)

    when "elo_update"
      handle_elo_update(msg_data)

    when "battle_party_response"
      handle_battle_party_response(msg_data)

    when "auction_list_success"
      handle_auction_list_success(msg_data)

    when 'auction_browse_result'
      handle_auction_browse_result(msg_data)

    when "auction_buy_success"
      handle_auction_buy_success(msg_data)

    when "auction_cancel_success"
      handle_auction_cancel_success(msg_data)

    when "auction_my_listings_result"
      handle_auction_my_listings_result(msg_data)

    when "auction_sold"
      handle_auction_sold(msg_data)

    when 'auction_error'
      handle_auction_error(msg_data)

    when "starter_claim_success"
      handle_starter_claim_success(msg_data)

    when "starter_claim_rejected"
      handle_starter_claim_rejected(msg_data)

    when "battle_forfeit"
      handle_battle_forfeit(msg_data)

    when "admin_give_item"
      handle_admin_give_item(msg_data)

    when "admin_give_pokemon"
      handle_admin_give_pokemon(msg_data)

    when "admin_heal"
      handle_admin_heal(msg_data)

    when "admin_setmoney"
      handle_admin_setmoney(msg_data)

    when "teleport"
      handle_teleport(msg_data)

    when 'time_set'
      handle_time_set(msg_data)

    when 'ping_request'
      handle_ping_request(msg_data)

    else
      puts "Unknown message type: #{message[:type]}"
    end
  end

  def handle_connected(data)

    @my_client_id  =  data[:client_id]
    puts "Connected to server with client_id: #{@my_client_id}"
  end

  def handle_player_list(data)

    players  =  data[:players] || data['players'] || data
    players = [players] unless players.is_a?(Array)

    players.each do |player|
      player_id  =  player[:id] || player['id']
      next if @my_client_id && player_id == @my_client_id

      @remote_players[player_id] = {
        id: player_id,
        username: player[:username] || player['username'],
        map_id: player[:map_id] || player['map_id'],
        x: player[:x] || player['x'],
        y: player[:y] || player['y'],
        direction: player[:direction] || player['direction'] || 2,
        charset: player[:charset] || player['charset'] || 'boy_walk',
        movement_type: player[:movement_type] || player['movement_type'] || 0
      }
    end

    puts "Received player list: #{@remote_players.size} other players online"
  end

  def handle_player_joined(data)
    player_id  =  data[:id] || data['id']
    return if @my_client_id && player_id == @my_client_id

    @remote_players[player_id]  =  {
      id: player_id,
      username: data[:username] || data['username'],
      map_id: data[:map_id] || data['map_id'],
      x: data[:x] || data['x'],
      y: data[:y] || data['y'],
      direction: data[:direction] || data['direction'] || 2,
      charset: data[:charset] || data['charset'] || 'boy_walk',
      movement_type: data[:movement_type] || data['movement_type'] || 0
    }

    puts "Player joined: #{@remote_players[player_id][:username]}"

    pbMultiplayerNotify("#{@remote_players[player_id][:username]} joined the game", 3.0) if defined?(pbMultiplayerNotify)
  end

  def handle_player_left(data)
    player_id  =  data[:id] || data['id'] || data[:client_id] || data['client_id']
    username  =  data[:username] || data['username']

    @remote_players.delete(player_id)
    puts "Player left: #{username}"

    pbMultiplayerNotify("#{username} left the game", 3.0) if defined?(pbMultiplayerNotify)
  end

  def handle_position_update(data)
    player_id  =  data[:id]
    old_map = @remote_players[player_id] ? @remote_players[player_id][:map_id] : nil
    new_map = data[:map_id]

    if old_map && new_map && old_map != new_map
      puts "[CLIENT] *** Player #{player_id} WARPED from map #{old_map} to map #{new_map} ***"
    end

    if @remote_players[player_id]
      @remote_players[player_id].merge!(data)
    else
      @remote_players[player_id] = data
    end

    if data[:follower] || data['follower']
      follower = data[:follower] || data['follower']
      @other_player_followers ||= {}
      new_follower_data = {
        species: (follower[:species] || follower['species']).to_sym,
        shiny: follower[:shiny] || follower['shiny'] || false,
        form: follower[:form] || follower['form'] || 0
      }

      old_data = @other_player_followers[player_id]
      if !old_data || old_data[:species] != new_follower_data[:species]
        puts "[Following] Player #{player_id} follower changed: #{old_data ? old_data[:species] : 'none'} -> #{new_follower_data[:species]}"
        new_follower_data[:needs_sprite_update] = true
      end

      @other_player_followers[player_id] = new_follower_data
    elsif (data.has_key?(:follower) && data[:follower].nil?) || (data.has_key?('follower') && data['follower'].nil?)

      if @other_player_followers && @other_player_followers[player_id]
        @other_player_followers.delete(player_id)
        puts "[Following] Player #{player_id} explicitly removed follower"
      end
    end

  end

  def handle_follower_update(data)
    player_id = data[:id] || data['id']
    return unless player_id

    @other_player_followers ||= {}

    if data[:follower] || data['follower']
      follower = data[:follower] || data['follower']
      new_follower_data = {
        species: (follower[:species] || follower['species']).to_sym,
        shiny: follower[:shiny] || follower['shiny'] || false,
        form: follower[:form] || follower['form'] || 0
      }

      old_data = @other_player_followers[player_id]
      if !old_data || old_data[:species] != new_follower_data[:species]
        puts "[Following] FOLLOWER UPDATE: Player #{player_id} follower changed: #{old_data ? old_data[:species] : 'none'} -> #{new_follower_data[:species]}"
        new_follower_data[:needs_sprite_update] = true
      end

      @other_player_followers[player_id] = new_follower_data
    elsif (data.has_key?(:follower) && data[:follower].nil?) || (data.has_key?('follower') && data['follower'].nil?)

      if @other_player_followers[player_id]
        @other_player_followers.delete(player_id)
        puts "[Following] FOLLOWER UPDATE: Player #{player_id} explicitly removed follower"
      end
    end
  end

  def handle_player_data(data)

    puts "=== RECEIVED PLAYER DATA FROM SERVER ==="
    puts "Raw data keys: #{data.keys.inspect}"

    map_id = data[:map_id] || (data[:position] && data[:position][:map_id])
    x = data[:x] || (data[:position] && data[:position][:x])
    y = data[:y] || (data[:position] && data[:position][:y])

    puts "  Position: Map #{map_id || 'nil'} (#{x || 'nil'}, #{y || 'nil'})"
    puts "  Bag items: #{data[:bag] ? data[:bag].size : 0}"
    puts "  Pokemon: #{data[:pokemon] ? data[:pokemon].size : 0}"
    puts "  Has starter: #{data[:has_starter]}"
    puts "========================================"

    @server_position = data

    if data.has_key?(:has_starter) || data.has_key?('has_starter')
      $multiplayer_server_has_starter_flag  =  (data[:has_starter] || data['has_starter']) == 1
      puts "Server has_starter flag set to: #{$multiplayer_server_has_starter_flag}"
    end

    if map_id && x && y
      $multiplayer_has_saved_position = true
      $multiplayer_saved_map  =  map_id
      $multiplayer_saved_x = x
      $multiplayer_saved_y = y
      puts "Position data stored successfully!"
    else
      puts "WARNING: No valid position data received from server"
      $multiplayer_has_saved_position = false
    end

    if data.has_key?(:has_running_shoes) || data.has_key?('has_running_shoes')
      has_running_shoes = data[:has_running_shoes] || data['has_running_shoes']
      if $player
        $player.has_running_shoes = (has_running_shoes == 1 || has_running_shoes == true)
        puts "Loaded running shoes: #{$player.has_running_shoes ? 'YES' : 'NO'}"
      end
    end

    if data.has_key?(:money) || data.has_key?('money')
      money  =  data[:money] || data['money'] || 3000
      if $player
        $player.money = money.to_i
        puts "Loaded money: $#{$player.money}"
      end
    end

    if data.has_key?(:badge_count) || data.has_key?('badge_count')
      badge_count = data[:badge_count] || data['badge_count'] || 0
      if $player && $player.respond_to?(:badge_count=)
        $player.badge_count = badge_count.to_i
        puts "Loaded badges: #{$player.badge_count}"
      end
    end

    if data.has_key?(:trainer_id) || data.has_key?('trainer_id')
      trainer_id  =  data[:trainer_id] || data['trainer_id']
      if trainer_id && $player && $player.respond_to?(:id=)
        $player.id = trainer_id.to_i
        puts "Loaded trainer ID: #{$player.id}"
      end
    end

    if data.has_key?(:badges) || data.has_key?('badges')
      badges = data[:badges] || data['badges']
      puts "[BADGE CLIENT DEBUG] Received badges from server: #{badges.inspect}"
      puts "[BADGE CLIENT DEBUG] Badges class: #{badges.class}"
      puts "[BADGE CLIENT DEBUG] Badges length: #{badges.length}" if badges.respond_to?(:length)
      if badges && $player && $player.respond_to?(:badges=)
        puts "[BADGE CLIENT DEBUG] Before assignment - $player.badges: #{$player.badges.inspect}"
        $player.badges = badges
        puts "[BADGE CLIENT DEBUG] After assignment - $player.badges: #{$player.badges.inspect}"
        puts "[BADGE CLIENT DEBUG] Badge count: #{$player.badge_count}"
        puts "Loaded badges: #{$player.badge_count} badges"
      end
    end

    if data.has_key?(:pokedex) || data.has_key?('pokedex')
      pokedex_data  =  data[:pokedex] || data['pokedex']
      if pokedex_data && $player && $player.respond_to?(:pokedex) && $player.pokedex
        begin

          seen_count = 0
          owned_count = 0

          pokedex_data.each do |species_id, entry|

            begin
              next unless GameData::Species.exists?(species_id)
              species = GameData::Species.get(species_id).species

              seen = entry[:seen] || entry['seen'] || 0
              owned = entry[:owned] || entry['owned'] || 0

              if seen == 1 || seen == true
                $player.pokedex.set_seen(species)
                seen_count += 1
              end
              if owned == 1 || owned == true
                $player.pokedex.set_owned(species)
                owned_count += 1
              end
            rescue => e
              puts "[LOAD] Error processing species #{species_id}: #{e.message}"
              next
            end
          end

          puts "Loaded Pokedex: #{seen_count} seen, #{owned_count} owned"
        rescue => e
          puts "[LOAD] Error loading Pokedex: #{e.message}"
        end
      end
    end

    # Load daycare data
    if data.has_key?(:daycare) || data.has_key?('daycare')
      daycare_data = data[:daycare] || data['daycare']
      if daycare_data && defined?(MultiplayerDaycare)
        MultiplayerDaycare.load(daycare_data)
      end
    end

    if data.has_key?(:playtime_seconds) || data.has_key?('playtime_seconds')
      playtime_seconds = data[:playtime_seconds] || data['playtime_seconds'] || 0
      $multiplayer_playtime_base = playtime_seconds.to_i
      $multiplayer_session_start = Time.now
      puts "Loaded playtime: #{$multiplayer_playtime_base} seconds"
    end

    if data.has_key?(:created_at) || data.has_key?('created_at')
      created_at = data[:created_at] || data['created_at']
      $multiplayer_created_at  =  created_at
      puts "Account created: #{created_at}"
    end

    @server_data_loaded = true

    if data[:bag] && data[:bag].any? && $bag
      puts "Loading bag data from server..."
      $bag.clear
      data[:bag].each do |item|
        item_id  =  item[:item_id] || item['item_id']
        quantity = item[:quantity] || item['quantity'] || 1
        $bag.add(item_id, quantity) if item_id
      end
      puts "Loaded #{data[:bag].size} bag items"
    end

    if data[:pokemon] && $player
      if data[:pokemon].any?
        puts 'Loading Pokemon data from server...'
        $player.party.clear
        data[:pokemon].each do |pkmn_data|

          species = pkmn_data[:species] || pkmn_data['species']

          if species
            pokemon = pbModernTradeManager.deserialize_pokemon(pkmn_data)
            $player.party << pokemon
          end
        end
        puts "Loaded #{$player.party.size} Pokemon from server (with full data including OT)"
      else

        puts 'Server sent empty Pokemon array (new player or data loss)'

        $multiplayer_server_sent_pokemon_data = true
      end
    else
      puts "No Pokemon data from server - first time player"
      $multiplayer_server_sent_pokemon_data = false
    end

    if data[:pc_boxes] && defined?($PokemonStorage) && $PokemonStorage
      puts "Loading PC storage data from server..."
      pc_boxes_data = data[:pc_boxes]

      $PokemonStorage.maxBoxes.times do |box_idx|
        PokemonBox::BOX_SIZE.times do |slot_idx|
          $PokemonStorage[box_idx, slot_idx] = nil
        end
      end

      pc_boxes_data.each do |box_data|
        box_number = box_data[:box_number] || box_data['box_number']
        box_name = box_data[:box_name] || box_data['box_name']
        pokemon_list = box_data[:pokemon] || box_data['pokemon'] || []

        if box_name && box_number
          $PokemonStorage[box_number].name = box_name
        end

        pokemon_list.each do |pkmn_entry|
          slot = pkmn_entry[:slot] || pkmn_entry['slot']
          pkmn_data = pkmn_entry[:data] || pkmn_entry['data']

          next unless slot && pkmn_data

          if defined?(pbModernTradeManager)
            pokemon = pbModernTradeManager.deserialize_pokemon(pkmn_data)
            $PokemonStorage[box_number, slot]  =  pokemon if pokemon
          end
        end
      end

      total_pc_pokemon = 0
      pc_boxes_data.each { |box| total_pc_pokemon += (box[:pokemon] || box['pokemon'] || []).size }
      puts "Loaded #{pc_boxes_data.size} PC boxes with #{total_pc_pokemon} total Pokemon"
    end

    if data[:picked_up_items] && defined?(pbMultiplayerItemPersistence)
      pbMultiplayerItemPersistence.load_from_server(data[:picked_up_items])
    end

    if data[:switches] || data['switches']
      switches_data = data[:switches] || data['switches']
      if defined?($game_switches) && $game_switches && switches_data.is_a?(Hash)
        begin

          switches_collection = $game_switches.instance_variable_get(:@data)
          if switches_collection
            if switches_collection.is_a?(Hash)

              switches_data.each do |key, value|
                index = key.to_s.to_i
                switches_collection[index] = value if index && index > 0
              end
            elsif switches_collection.is_a?(Array)

              switches_data.each do |key, value|
                index = key.to_s.to_i
                switches_collection[index] = value if index && index > 0
              end
            end
          end
        rescue => e
          puts "[LOAD] Error loading switches: #{e.message}"
        end
      end
    end

    if data[:variables] || data['variables']
      variables_data = data[:variables] || data['variables']
      if defined?($game_variables) && $game_variables && variables_data.is_a?(Hash)
        begin

          variables_collection = $game_variables.instance_variable_get(:@data)
          if variables_collection
            if variables_collection.is_a?(Hash)

              variables_data.each do |key, value|
                index = key.to_s.to_i
                variables_collection[index] = value if index && index > 0
              end
            elsif variables_collection.is_a?(Array)

              variables_data.each do |key, value|
                index = key.to_s.to_i
                variables_collection[index] = value if index && index > 0
              end
            end
          end
        rescue => e
          puts "[LOAD] Error loading variables: #{e.message}"
        end
      end
    end

    if data[:self_switches] || data['self_switches']
      self_switches_data  =  data[:self_switches] || data['self_switches']
      if defined?($game_self_switches) && $game_self_switches && self_switches_data.is_a?(Hash)
        begin

          self_switches_hash = $game_self_switches.instance_variable_get(:@data)
          if self_switches_hash && self_switches_hash.is_a?(Hash)
            self_switches_data.each do |key_str, value|

              parts = key_str.to_s.split('_')
              if parts.length == 3
                map_id = parts[0].to_i
                event_id = parts[1].to_i
                letter = parts[2]
                self_switches_hash[[map_id, event_id, letter]]  =  value
              end
            end
          end
        rescue => e
          puts "[LOAD] Error loading self_switches: #{e.message}"
        end
      end
    end

    if @disconnected_during_battle
      puts "Clearing battle state after disconnect during battle"

      if defined?($game_temp) && $game_temp
        $game_temp.in_battle  =  false
      end

      if defined?($game_switches) && $game_switches &&
         defined?($game_self_switches) && $game_self_switches
        switches_collection = $game_switches.instance_variable_get(:@data)
        if switches_collection &&
           ((switches_collection.is_a?(Array) && switches_collection[78]) ||
            (switches_collection.is_a?(Hash) && switches_collection[78]))

          puts 'Marking rival battle event as completed to prevent cutscene replay'
          self_switches_hash  =  $game_self_switches.instance_variable_get(:@data)
          if self_switches_hash && self_switches_hash.is_a?(Hash)

            self_switches_hash[[6, 25, 'A']] = true
          end
        end
      end

      @disconnected_during_battle = false
    end
  end

  def get_saved_position
    @server_position
  end

  def handle_chat_message(data)
    username = data[:username] || data['username']
    message = data[:message] || data['message']
    color = data[:color] || data['color']
    permission = data[:permission] || data['permission']

    display_name = username
    if permission
      case permission.to_s.downcase.to_sym
      when :admin
        display_name = "[ADMIN] #{username}"
      when :moderator, :mod
        display_name = "[MOD] #{username}"
      end
    end

    puts "[#{display_name}]: #{message}"

    if defined?(pbMultiplayerChat) && pbMultiplayerChat

      chat_method = pbMultiplayerChat.method(:add_message)

      if chat_method.arity == -3 || chat_method.arity == 3

        pbMultiplayerChat.add_message(display_name, message, color)
      else

        pbMultiplayerChat.add_message(display_name, message)
      end
    end
  end

  def handle_error(data)
    error_msg = data[:message] || data['message'] || "Unknown server error"
    error_type  =  data[:error_type] || data['error_type'] || "general"

    puts "Server error: #{error_msg} (type: #{error_type})"

    if error_type == "game_mismatch"
      client_game_id = MultiplayerProtocol::GAME_ID
      server_game_id = data[:expected_game_id] || data['expected_game_id'] || "unknown"

      @last_error = "WRONG GAME!\n\nYour game: #{client_game_id}\nServer expects: #{server_game_id}\n\nThis server is for a different game. Please connect to the correct server."

      puts "[GAME_ID] Client game '#{client_game_id}' rejected - server expects '#{server_game_id}'"

      disconnect

    elsif error_type == "version_mismatch" || error_type == "outdated_client"
      server_version = data[:server_version] || data['server_version']
      client_version = MultiplayerVersion::VERSION
      min_required = data[:min_required_version] || data['min_required_version']

      if error_type == "version_mismatch"

        @last_error = "VERSION INCOMPATIBLE!\n\nYour version: #{client_version}\nServer version: #{server_version}\n\nMajor version mismatch - please update your game."
      elsif error_type == "outdated_client"

        @last_error = "CLIENT OUTDATED!\n\nYour version: #{client_version}\nMinimum required: #{min_required}\n\nPlease update your game to continue playing."
      end

      puts "[VERSION] Client #{client_version} rejected by server (server: #{server_version}, min: #{min_required})"
    else

      @last_error = error_msg
    end

    @last_error_time = Time.now

    if defined?(pbMultiplayerNotify)
      pbMultiplayerNotify("Server error: #{error_msg}", 5.0)
    end
  end

  def handle_update_available(data)
    new_version = data[:new_version] || data['new_version']
    current_version = MultiplayerVersion::VERSION
    update_message = data[:message] || data['message'] || "A new game update is available!"

    puts "[VERSION] Update available: #{current_version} -> #{new_version}"

    # Only show notification if player is fully logged in and on the map
    # Don't show during password entry or other screens
    if defined?(pbMultiplayerNotify) && defined?($scene) && $scene.is_a?(Scene_Map)
      pbMultiplayerNotify("UPDATE AVAILABLE: v#{new_version} (you have v#{current_version})", 15.0)
    end

    @update_available = true
    @latest_version = new_version
    @update_message = update_message

    # Set the global pending update variable so auto-updater can prompt for download
    # This triggers the on_frame_update handler in 045_AutoUpdater.rb
    # The prompt will appear when player reaches the map
    $mmo_pending_update = {
      new_version: new_version,
      current_version: current_version,
      message: update_message
    }
    puts "[VERSION] Set $mmo_pending_update - download prompt will appear when on map"
  end

  def update_available?
    @update_available == true
  end

  def latest_version
    @latest_version
  end

  def update_message
    @update_message
  end

  def get_last_error

    if @last_error && @last_error_time && (Time.now - @last_error_time < 5)
      error = @last_error
      @last_error = nil
      return error
    end
    return nil
  end

  def get_movement_type
    return 0 unless $game_player

    if $game_player.character_name.include?("surf")
      return 3
    elsif $game_player.character_name.include?("cycle")
      return 2
    elsif $game_player.character_name.include?("run")
      return 1
    else
      return 0
    end
  end

  def get_charset_name
    return "boy_walk" unless $game_player
    $game_player.character_name
  end

  def request_battle_party(opponent_id)
    data = {
      type: :request_battle_party,
      opponent_id: opponent_id
    }
    send_message(data)
  end

  def get_received_battle_party(opponent_id)

    @received_battle_parties ||= {}
    @received_battle_parties[opponent_id]
  end

  def handle_battle_party_response(data)
    @received_battle_parties ||= {}
    @received_battle_parties[data[:player_id]]  =  data[:party]
  end

  def client_id
    @my_client_id
  end

  def send_battle_request(target_id, battle_format = :single)
    return unless @connected
    send_message(MultiplayerProtocol.create_message('battle_request', {
      target_id: target_id,
      format: battle_format
    }))
  end

  def send_battle_accept(from_id, battle_format = :single)
    return unless @connected
    send_message(MultiplayerProtocol.create_message("battle_accept", {
      from_id: from_id,
      format: battle_format
    }))
  end

  def send_battle_decline(from_id)
    return unless @connected
    send_message(MultiplayerProtocol.create_message("battle_decline", {
      from_id: from_id
    }))
  end

  def send_battle_choice(battle_id, opponent_id, turn, choice)
    return unless @connected
    send_message(MultiplayerProtocol.create_message("battle_choice", {
      battle_id: battle_id,
      opponent_id: opponent_id,
      turn: turn,
      choice: choice
    }))
  end

  def send_battle_state(battle_id, opponent_id, state)
    return unless @connected
    send_message(MultiplayerProtocol.create_message('battle_state', {
      battle_id: battle_id,
      opponent_id: opponent_id,
      state: state
    }))
  end

  def send_battle_ready(battle_id, opponent_id, rng_seed)
    return unless @connected
    send_message(MultiplayerProtocol.create_message('battle_ready', {
      battle_id: battle_id,
      opponent_id: opponent_id,
      rng_seed: rng_seed
    }))
  end

  def send_battle_switch(battle_id, opponent_id, battler_index, party_index)
    return unless @connected
    send_message(MultiplayerProtocol.create_message('battle_switch', {
      battle_id: battle_id,
      opponent_id: opponent_id,
      battler_index: battler_index,
      party_index: party_index
    }))
  end

  def accept_battle_request(from_id, battle_format = "Single Battle")
    send_battle_accept(from_id, battle_format)
  end

  def decline_battle_request(from_id)
    send_battle_decline(from_id)
  end

  def request_battle_party(opponent_id)
    return unless @connected
    send_message(MultiplayerProtocol.create_message("battle_party_request", {
      target_id: opponent_id
    }))
  end

  def get_received_battle_party(opponent_id)

    @received_battle_parties ||= {}
    @received_battle_parties[opponent_id]
  end

  def handle_battle_party_response(data)
    opponent_id = data[:player_id] || data['player_id']
    party_data = data[:party] || data['party']
    @received_battle_parties ||= {}
    @received_battle_parties[opponent_id]  =  party_data
    puts "[BATTLE] Received battle party from player #{opponent_id}: #{party_data.length} Pokemon"
  end

  def send_trade_offer(target_id, pokemon_data, trade_id = nil)
    return unless @connected
    data  =  {
      target_id: target_id,
      pokemon: pokemon_data
    }
    data[:trade_id] = trade_id if trade_id
    send_message(MultiplayerProtocol.create_message("trade_offer", data))
  end

  def send_trade_accept(from_id, my_pokemon_data, their_pokemon_data)
    return unless @connected
    send_message(MultiplayerProtocol.create_message("trade_accept", {
      from_id: from_id,
      my_pokemon: my_pokemon_data,
      their_pokemon: their_pokemon_data
    }))
  end

  def send_trade_decline(from_id)
    return unless @connected
    send_message(MultiplayerProtocol.create_message("trade_decline", {
      from_id: from_id
    }))
  end

  def accept_trade_offer(from_player_id, trade_id, their_pokemon_data, my_pokemon_data)
    return unless @connected
    send_message(MultiplayerProtocol.create_message("trade_accept", {
      from_id: from_player_id,
      trade_id: trade_id,
      their_pokemon: their_pokemon_data,
      my_pokemon: my_pokemon_data
    }))
  end

  def decline_trade_offer(from_player_id, trade_id)
    return unless @connected
    send_message(MultiplayerProtocol.create_message("trade_decline", {
      from_id: from_player_id,
      trade_id: trade_id
    }))
  end

  def confirm_trade_complete(trade_id)
    return unless @connected
    send_message(MultiplayerProtocol.create_message('trade_complete', {
      trade_id: trade_id
    }))
  end

  def handle_battle_request_sent(data)
    target_username = data[:target_username] || data['target_username']
    puts "[BATTLE] Battle request sent to #{target_username}"
    pbMultiplayerNotify("Battle request sent to #{target_username}", 2.0) if defined?(pbMultiplayerNotify)
  end

  def handle_battle_declined(data)
    opponent_username = data[:opponent_username] || data['opponent_username']
    puts "[BATTLE] #{opponent_username} declined your battle request"
    pbMultiplayerNotify("#{opponent_username} declined your battle", 3.0) if defined?(pbMultiplayerNotify)
  end

  def handle_battle_accepted_msg(data)
    opponent_id = data[:opponent_id] || data['opponent_id']
    opponent_username = data[:opponent_username] || data['opponent_username']
    format = data[:format] || data['format'] || :single

    puts "[BATTLE] #{opponent_username} accepted your battle request!"
    pbMultiplayerNotify("#{opponent_username} accepted! Battle starting...", 2.0) if defined?(pbMultiplayerNotify)

  end

  def handle_battle_start_msg(data)
    opponent_id = data[:opponent_id] || data['opponent_id']
    opponent_username = data[:opponent_username] || data['opponent_username']
    format = data[:format] || data['format'] || :single
    opponent_party = data[:opponent_party] || data['opponent_party']

    if opponent_party.is_a?(String)
      begin
        opponent_party = JSON.parse(opponent_party, symbolize_names: true)
      rescue JSON::ParserError => e
        puts "[BATTLE ERROR] Failed to parse party JSON: #{e.message}"
        opponent_party  =  []
      end
    end

    puts "[BATTLE] Starting battle with #{opponent_username}! (#{format})"
    puts "[BATTLE] Received party data: #{opponent_party ? opponent_party.length : 0} Pokemon"

    @received_battle_parties ||= {}
    @received_battle_parties[opponent_id] = opponent_party if opponent_party

    if defined?(pbMultiplayerBattleManager)
      pbMultiplayerBattleManager.start_multiplayer_battle(opponent_id, opponent_username, format)
    end
  end

  def handle_battle_start_sync_msg(data)
    battle_id = data[:battle_id] || data['battle_id']
    opponent_id = data[:opponent_id] || data['opponent_id']
    opponent_username = data[:opponent_username] || data['opponent_username']
    format = data[:format] || data['format'] || :single
    opponent_party = data[:opponent_party] || data['opponent_party']
    rng_seed = data[:rng_seed] || data['rng_seed']
    is_host = data[:is_host] || data['is_host']

    if opponent_party.is_a?(String)
      begin
        opponent_party = JSON.parse(opponent_party, symbolize_names: true)
      rescue JSON::ParserError => e
        puts "[BATTLE SYNC ERROR] Failed to parse party JSON: #{e.message}"
        opponent_party = []
      end
    end

    puts "[BATTLE SYNC] Starting synchronized battle ##{battle_id}"
    puts "[BATTLE SYNC] Opponent: #{opponent_username} (#{format})"
    puts "[BATTLE SYNC] RNG Seed: #{rng_seed}, Is Host: #{is_host}"
    puts "[BATTLE SYNC] Opponent party: #{opponent_party ? opponent_party.length : 0} Pokemon"

    if defined?(pbMultiplayerBattleManager)
      pbMultiplayerBattleManager.start_synchronized_battle(
        opponent_id, opponent_username, format, opponent_party, rng_seed, battle_id, is_host
      )
    end
  end

  def handle_battle_opponent_choice_msg(data)
    battle_id = data[:battle_id] || data['battle_id']
    turn = data[:turn] || data['turn']
    choice = data[:choice] || data['choice']

    puts "[BATTLE SYNC] Received opponent's choice for battle ##{battle_id}, turn #{turn}"

    if defined?(pbMultiplayerBattleManager) && pbMultiplayerBattleManager.active_mp_battle
      pbMultiplayerBattleManager.receive_opponent_battle_choice(choice)
    end
  end

  def handle_battle_ready_msg(data)
    battle_id = data[:battle_id] || data['battle_id']
    rng_seed = data[:rng_seed] || data['rng_seed']

    puts "[BATTLE SYNC] Received opponent's battle ready signal for battle ##{battle_id}, RNG seed: #{rng_seed}"

    if defined?(pbMultiplayerBattleManager)
      pbMultiplayerBattleManager.receive_opponent_battle_ready(rng_seed)
    end
  end

  def handle_battle_switch_msg(data)
    battle_id = data[:battle_id] || data['battle_id']
    party_index = data[:party_index] || data['party_index']

    puts "[BATTLE SYNC] Received opponent's switch choice for battle ##{battle_id}: party slot #{party_index}"

    # Set global variables that the battle sync checks for
    $multiplayer_opponent_switch_received = true
    $multiplayer_opponent_switch_data = {
      battle_id: battle_id,
      party_index: party_index
    }
  end

  def handle_trade_offer_received(data)
    puts "[CLIENT DEBUG] handle_trade_offer_received called!"
    puts "[CLIENT DEBUG] Data received: #{data.inspect}"
    return unless defined?(pbModernTradeManager)
    from_id  =  data[:from_id] || data['from_id']
    from_username = data[:from_username] || data['from_username']
    pokemon_data = data[:pokemon] || data['pokemon']
    trade_id = data[:trade_id] || data['trade_id'] || "#{from_id}_#{Time.now.to_i}"
    puts "[CLIENT DEBUG] Calling pbModernTradeManager.receive_trade_offer with:"
    puts "  from_id: #{from_id}, from_username: #{from_username}, trade_id: #{trade_id}"
    pbModernTradeManager.receive_trade_offer(from_id, from_username, pokemon_data, trade_id)
  end

  def handle_trade_offer_sent(data)
    target_username = data[:target_username] || data['target_username']
    puts "[TRADE] Trade offer sent to #{target_username}"
    pbMultiplayerNotify("Trade offer sent to #{target_username}", 2.0) if defined?(pbMultiplayerNotify)
  end

  def handle_trade_accepted(data)
    opponent_username = data[:opponent_username] || data['opponent_username']
    received_pokemon = data[:received_pokemon] || data['received_pokemon']

    puts "[TRADE] #{opponent_username} accepted your trade!"

    @trade_received_pokemon = received_pokemon
    @trade_opponent_username  =  opponent_username

    if defined?(pbModernTradeManager)
      pbModernTradeManager.trade_accepted(opponent_username, received_pokemon)
    end
  end

  def handle_trade_complete(data)
    opponent_username = data[:opponent_username] || data['opponent_username']
    received_pokemon = data[:received_pokemon] || data['received_pokemon']

    puts "[TRADE] Trade completed with #{opponent_username}!"

    @trade_received_pokemon = received_pokemon
    @trade_opponent_username = opponent_username

    if defined?(pbModernTradeManager)
      pbModernTradeManager.trade_accepted(opponent_username, received_pokemon)
    end
  end

  def handle_trade_declined(data)
    opponent_username = data[:opponent_username] || data['opponent_username']
    puts "[TRADE] #{opponent_username} declined your trade offer"
    pbMultiplayerNotify("#{opponent_username} declined your trade", 3.0) if defined?(pbMultiplayerNotify)
  end

  def handle_starter_claim_success(data)
    puts "[STARTER] Starter claim successful!"
    $multiplayer_starter_claim_successful = true
    $multiplayer_server_has_starter_flag = true
  end

  def handle_starter_claim_rejected(data)
    puts "[STARTER] Starter claim rejected: #{data[:message]}"
    $multiplayer_starter_claim_rejected = true
    pbMessage(_INTL(data[:message])) if defined?(pbMessage) && data[:message]
  end

  def handle_trade_offer_v2(data)
    from_player_id = data[:from_player_id] || data['from_player_id']
    from_username = data[:from_username] || data['from_username']
    trade_session_id  =  data[:trade_session_id] || data['trade_session_id']
    pokemon_data = data[:pokemon_data] || data['pokemon_data']

    puts "[TRADE V2] Received trade offer from #{from_username}"

    if defined?(pbModernTradeManager)
      pbModernTradeManager.receive_trade_offer(
        from_player_id,
        from_username,
        trade_session_id,
        pokemon_data
      )
    end
  end

  def handle_trade_counter_offer_v2(data)
    pokemon_data = data[:pokemon_data] || data['pokemon_data']

    puts "[TRADE V2] Received counter-offer"

    if defined?(pbModernTradeManager)
      pbModernTradeManager.receive_counter_offer(pokemon_data)
    end
  end

  def handle_trade_confirm_v2(data)
    puts '[TRADE V2] Partner confirmed trade'

    if defined?(pbModernTradeManager)
      pbModernTradeManager.receive_trade_confirm
    end
  end

  def handle_trade_decline_v2(data)
    reason = data[:reason] || data['reason'] || "declined"

    puts "[TRADE V2] Trade declined: #{reason}"

    if defined?(pbModernTradeManager)
      pbModernTradeManager.receive_trade_decline(reason)
    end
  end

  def handle_trade_change_offer_v2(data)
    pokemon_data = data[:pokemon_data] || data['pokemon_data']

    puts '[TRADE V2] Partner changed their offer'

    if defined?(pbModernTradeManager)
      pbModernTradeManager.receive_offer_change(pokemon_data)
    end
  end

  def handle_execute_trade_v2(data)
    my_pokemon_id  =  data[:my_pokemon_id] || data['my_pokemon_id']
    their_pokemon_data = data[:their_pokemon_data] || data['their_pokemon_data']

    puts '[TRADE V2] Server authorized trade execution'

    if defined?(pbModernTradeManager)
      pbModernTradeManager.execute_trade_server_authorized(
        my_pokemon_id,
        their_pokemon_data
      )
    end
  end

  def handle_battle_forfeit(data)
    battle_id  =  data[:battle_id] || data['battle_id']
    forfeiter_username = data[:forfeiter_username] || data['forfeiter_username']
    message = data[:message] || data['message'] || "Opponent forfeited"

    puts "[BATTLE FORFEIT] Battle ##{battle_id}: #{forfeiter_username} forfeited"

    $multiplayer_battle_forfeited  =  true

    if defined?(pbMultiplayerBattleManager) && pbMultiplayerBattleManager.active_mp_battle
      puts "[BATTLE FORFEIT] Opponent disconnected - you win by forfeit!"

    end
  end

  def request_social_data
    return unless @connected
    puts "[SOCIAL] Requesting social data from server..."
    send_message(MultiplayerProtocol.create_message("get_social_data", {}))
  end

  def handle_social_data(data)
    @social_player_list = data[:players] || data['players'] || []
    puts "[SOCIAL] Received data for #{@social_player_list.length} players"
  end

  def handle_elo_update(data)
    old_elo = data[:old_elo] || data['old_elo']
    new_elo  =  data[:new_elo] || data['new_elo']
    change = data[:change] || data['change']
    opponent  =  data[:opponent] || data['opponent']
    result  =  data[:result] || data['result']

    message = if result == "win"
                sprintf("Victory! ELO: %d → %d (+%d)\nDefeated %s", old_elo, new_elo, change, opponent)
              else
                sprintf("Defeat. ELO: %d → %d (%d)\nLost to %s", old_elo, new_elo, change, opponent)
              end

    pbMessage(message) if defined?(pbMessage)
  end

  def handle_battle_request(data)
    from_player_id = data[:from_id] || data['from_id']
    from_username = data[:from_username] || data['from_username']
    battle_format = data[:format] || data['format'] || "Single Battle"

    puts "[BATTLE] Received battle request from #{from_username} (format: #{battle_format})"

    if defined?(pbMultiplayerBattleManager)

      format_symbol  =  case battle_format
                      when "Double Battle" then :double
                      when "Triple Battle" then :triple
                      when 'Rotation Battle' then :rotation
                      else :single
                      end
      pbMultiplayerBattleManager.receive_battle_request(from_player_id, from_username, format_symbol)
    end
  end

  def report_battle_complete(winner_id, loser_id)
    return unless @connected
    send_message(MultiplayerProtocol.create_message('battle_complete', {
      winner_id: winner_id,
      loser_id: loser_id
    }))
  end

  def handle_admin_give_item(data)
    item_id = data[:item_id] || data['item_id']
    quantity = data[:quantity] || data['quantity'] || 1

    return unless $bag && item_id

    begin

      $bag.add(item_id.to_sym, quantity)
      puts "[ADMIN] Received #{quantity}x #{item_id}"
    rescue => e
      puts "[ADMIN] Error giving item: #{e.message}"
    end
  end

  def handle_admin_give_pokemon(data)
    species = data[:species] || data['species']
    level = data[:level] || data['level'] || 5

    return unless $player && species

    begin

      pokemon = Pokemon.new(species.to_sym, level)

      if $player.party.length < 6
        $player.party << pokemon
        puts "[ADMIN] Received level #{level} #{species}"
      else

        pbStorePokemon(pokemon)
        puts "[ADMIN] Received level #{level} #{species} (sent to PC - party full)"
      end
    rescue => e
      puts "[ADMIN] Error giving Pokemon: #{e.message}"
    end
  end

  def handle_admin_heal(data)
    return unless $player && $player.party

    begin

      $player.party.each do |pokemon|
        next unless pokemon
        pokemon.heal
      end

      pbMessage(_INTL("Your Pokémon were healed!"))
      puts "[ADMIN] Pokemon healed"
    rescue => e
      puts "[ADMIN] Error healing Pokemon: #{e.message}"
    end
  end

  def handle_admin_setmoney(data)
    money = data[:money] || data['money']

    return unless $player && money

    begin
      $player.money  =  money.to_i
      puts "[ADMIN] Money set to $#{money}"
    rescue => e
      puts "[ADMIN] Error setting money: #{e.message}"
    end
  end

  def handle_teleport(data)
    map_id = data[:map_id] || data['map_id']
    x  =  data[:x] || data['x']
    y = data[:y] || data['y']

    return unless map_id && x && y

    begin

      @pending_teleport = { map_id: map_id, x: x, y: y }
      puts "[TELEPORT] Teleporting to map #{map_id} (#{x}, #{y})"
    rescue => e
      puts "[TELEPORT] Error: #{e.message}"
    end
  end

  def handle_time_set(data)
    hour = data[:hour] || data['hour']

    return unless hour

    begin

      if defined?(pbSetTimeToHour)
        pbSetTimeToHour(hour.to_i)
        puts "[TIME] Server time set to #{hour}:00"
      end
    rescue => e
      puts "[TIME] Error setting time: #{e.message}"
    end
  end

  def handle_ping_request(data)
    timestamp = data[:timestamp] || data['timestamp']

    return unless timestamp

    begin

      ping_ms = ((Time.now.to_f - timestamp.to_f) * 1000).round

      pbMultiplayerChat.add_message("[SERVER]", "Pong! Latency: #{ping_ms}ms")
      puts "[PING] Latency: #{ping_ms}ms"
    rescue => e
      puts "[PING] Error: #{e.message}"
    end
  end

  def check_pending_teleport
    return unless @pending_teleport

    teleport_data = @pending_teleport
    @pending_teleport = nil

    if defined?(pbFadeOutIn) && defined?($game_temp) && $scene.is_a?(Scene_Map)
      pbFadeOutIn do        $game_temp.player_new_map_id = teleport_data[:map_id]
        $game_temp.player_new_x = teleport_data[:x]
        $game_temp.player_new_y = teleport_data[:y]
        $game_temp.player_new_direction = 2
        $scene.transfer_player
        $game_map.autoplay
        $game_map.refresh
      end
    end
  end
end

$multiplayer_client = nil

def pbMultiplayerClient
  $multiplayer_client ||= MultiplayerClient.new
  return $multiplayer_client
end

def pbGetMultiplayerPlaytime
  return 0 unless defined?($multiplayer_playtime_base) && $multiplayer_playtime_base
  return 0 unless defined?($multiplayer_session_start) && $multiplayer_session_start

  base_time = $multiplayer_playtime_base.to_i
  session_time = (Time.now - $multiplayer_session_start).to_i
  return base_time + session_time
end

def pbConnectToMultiplayer(host, port, username, password = nil)
  pbMultiplayerClient.connect(host, port, username, password)
end

def pbDisconnectFromMultiplayer
  pbMultiplayerClient.disconnect if pbMultiplayerClient
end

def pbMultiplayerConnected?
  pbMultiplayerClient && pbMultiplayerClient.connected
end
