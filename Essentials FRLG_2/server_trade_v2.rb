#===============================================================================
# Server-Side Modern Trade System V2
# Secure, atomic trades with proper state management
#===============================================================================

class TradeSessionV2
  attr_reader :session_id, :player1_id, :player2_id
  attr_accessor :player1_offer, :player2_offer
  attr_accessor :player1_confirmed, :player2_confirmed
  attr_reader :created_at

  def initialize(session_id, player1_id, player2_id)
    @session_id = session_id
    @player1_id = player1_id
    @player2_id = player2_id
    @player1_offer = nil
    @player2_offer = nil
    @player1_confirmed = false
    @player2_confirmed = false
    @created_at = Time.now
    @executed = false
  end

  def expired?
    Time.now - @created_at > 300  # 5 minutes
  end

  def both_confirmed?
    @player1_confirmed && @player2_confirmed && @player1_offer && @player2_offer
  end

  def executed?
    @executed
  end

  def mark_executed
    @executed = true
  end

  def reset_confirmations
    @player1_confirmed = false
    @player2_confirmed = false
  end
end

# Add this to the MultiplPlayer Server class
class MultiplayerServer
  def initialize_trade_v2_system
    @trade_sessions_v2 = {}  # session_id => TradeSessionV2
    @player_trade_locks_v2 = {}  # client_id => session_id (prevent multiple simultaneous trades)
    @logger.info "[TRADE V2] Modern trade system initialized"
  end

  #=============================================================================
  # Trade Offer V2 - Player 1 initiates
  #=============================================================================
  def handle_trade_offer_v2(client_id, data)
    @logger.info "[TRADE V2] handle_trade_offer_v2 called by client #{client_id}"
    @logger.info "[TRADE V2] Data received: #{data.inspect}"

    target_id = data[:target_id] || data['target_id']
    session_id = data[:trade_session_id] || data['trade_session_id']
    pokemon_data = data[:pokemon_data] || data['pokemon_data']

    @logger.info "[TRADE V2] #{client_id} offering trade to #{target_id}, session: #{session_id}"

    # Debug: Show all connected clients
    @logger.info "[TRADE V2] Currently connected clients: #{@clients.keys.inspect}"
    @logger.info "[TRADE V2] Client #{client_id} exists: #{!@clients[client_id].nil?}"
    @logger.info "[TRADE V2] Target #{target_id} exists: #{!@clients[target_id].nil?}"

    # Validate players exist
    unless @clients[client_id] && @clients[target_id]
      @logger.warn "[TRADE V2] One or both players not found (client: #{!@clients[client_id].nil?}, target: #{!@clients[target_id].nil?})"
      send_to_client(client_id, {
        type: "trade_decline_v2",
        data: { reason: "player_not_found" }
      })
      return
    end

    # Check if either player is already in a trade
    if @player_trade_locks_v2[client_id]
      send_to_client(client_id, {
        type: "trade_decline_v2",
        data: { reason: "already_in_trade" }
      })
      return
    end

    if @player_trade_locks_v2[target_id]
      send_to_client(client_id, {
        type: "trade_decline_v2",
        data: { reason: "busy" }
      })
      return
    end

    # Create trade session
    session = TradeSessionV2.new(session_id, client_id, target_id)
    session.player1_offer = pokemon_data
    @trade_sessions_v2[session_id] = session

    # Lock both players into this trade
    @player_trade_locks_v2[client_id] = session_id
    @player_trade_locks_v2[target_id] = session_id

    # Forward offer to target player
    send_to_client(target_id, {
      type: "trade_offer_v2",
      data: {
        from_player_id: client_id,
        from_username: @clients[client_id][:username],
        trade_session_id: session_id,
        pokemon_data: pokemon_data
      }
    })

    @logger.info "[TRADE V2] Session #{session_id} created, offer sent to #{target_id}"
  end

  #=============================================================================
  # Counter Offer V2 - Player 2 responds with their Pokemon
  #=============================================================================
  def handle_trade_counter_offer_v2(client_id, data)
    target_id = data[:target_id] || data['target_id']
    session_id = data[:trade_session_id] || data['trade_session_id']
    pokemon_data = data[:pokemon_data] || data['pokemon_data']

    @logger.info "[TRADE V2] #{client_id} counter-offering, session: #{session_id}"

    session = @trade_sessions_v2[session_id]
    unless session
      @logger.info "[TRADE V2] Session not found"
      return
    end

    # Verify this player is part of the trade
    unless session.player1_id == client_id || session.player2_id == client_id
      @logger.info "[TRADE V2] Player not part of this trade"
      return
    end

    # Store the counter-offer
    if session.player1_id == client_id
      session.player1_offer = pokemon_data
    else
      session.player2_offer = pokemon_data
    end

    # Reset confirmations since offer changed
    session.reset_confirmations

    # Determine the other player
    other_player_id = (session.player1_id == client_id) ? session.player2_id : session.player1_id

    # Send counter-offer to other player
    send_to_client(other_player_id, {
      type: "trade_counter_offer_v2",
      data: { pokemon_data: pokemon_data }
    })

    @logger.info "[TRADE V2] Counter-offer sent to #{other_player_id}"
  end

  #=============================================================================
  # Change Offer V2 - Player changes their Pokemon
  #=============================================================================
  def handle_trade_change_offer_v2(client_id, data)
    target_id = data[:target_id] || data['target_id']
    session_id = data[:trade_session_id] || data['trade_session_id']
    pokemon_data = data[:pokemon_data] || data['pokemon_data']

    @logger.info "[TRADE V2] #{client_id} changing offer, session: #{session_id}"

    session = @trade_sessions_v2[session_id]
    unless session
      @logger.info "[TRADE V2] Session not found"
      return
    end

    # Update the offer
    if session.player1_id == client_id
      session.player1_offer = pokemon_data
    elsif session.player2_id == client_id
      session.player2_offer = pokemon_data
    else
      @logger.info "[TRADE V2] Player not part of this trade"
      return
    end

    # Reset confirmations
    session.reset_confirmations

    # Notify other player
    other_player_id = (session.player1_id == client_id) ? session.player2_id : session.player1_id
    send_to_client(other_player_id, {
      type: "trade_change_offer_v2",
      data: { pokemon_data: pokemon_data }
    })

    @logger.info "[TRADE V2] Changed offer sent to #{other_player_id}"
  end

  #=============================================================================
  # Trade Confirm V2 - Player confirms the trade
  #=============================================================================
  def handle_trade_confirm_v2(client_id, data)
    session_id = data[:trade_session_id] || data['trade_session_id']

    @logger.info "[TRADE V2] #{client_id} confirmed, session: #{session_id}"

    session = @trade_sessions_v2[session_id]
    unless session
      @logger.info "[TRADE V2] Session not found"
      return
    end

    # Mark confirmation
    if session.player1_id == client_id
      session.player1_confirmed = true
    elsif session.player2_id == client_id
      session.player2_confirmed = true
    else
      @logger.info "[TRADE V2] Player not part of this trade"
      return
    end

    # Notify other player
    other_player_id = (session.player1_id == client_id) ? session.player2_id : session.player1_id
    send_to_client(other_player_id, {
      type: "trade_confirm_v2",
      data: {}
    })

    # Check if both confirmed - if so, EXECUTE
    if session.both_confirmed? && !session.executed?
      execute_trade_v2(session)
    end
  end

  #=============================================================================
  # Execute Trade V2 - SERVER AUTHORITATIVE
  # This is the ONLY place where trades are actually executed
  # Both players MUST execute this or face desync
  #=============================================================================
  def execute_trade_v2(session)
    @logger.info "[TRADE V2] EXECUTING TRADE - Session: #{session.session_id}"

    # Mark as executed immediately to prevent double-execution
    session.mark_executed

    player1_data = session.player1_offer
    player2_data = session.player2_offer

    # Extract Pokemon IDs for verification
    player1_pokemon_id = player1_data[:personalID] || player1_data['personalID']
    player2_pokemon_id = player2_data[:personalID] || player2_data['personalID']

    @logger.info "[TRADE V2] P1 Pokemon ID: #{player1_pokemon_id}, P2 Pokemon ID: #{player2_pokemon_id}"

    # Send execute command to BOTH players
    # Player 1 sends their Pokemon, receives Player 2's
    send_to_client(session.player1_id, {
      type: "execute_trade_v2",
      data: {
        my_pokemon_id: player1_pokemon_id,
        their_pokemon_data: player2_data
      }
    })

    # Player 2 sends their Pokemon, receives Player 1's
    send_to_client(session.player2_id, {
      type: "execute_trade_v2",
      data: {
        my_pokemon_id: player2_pokemon_id,
        their_pokemon_data: player1_data
      }
    })

    @logger.info "[TRADE V2] Execute commands sent to both players"

    # Clean up will happen when both players send acknowledgment
  end

  #=============================================================================
  # Trade Complete Acknowledgment V2
  #=============================================================================
  def handle_trade_complete_ack_v2(client_id, data)
    session_id = data[:trade_session_id] || data['trade_session_id']

    @logger.info "[TRADE V2] #{client_id} acknowledged completion, session: #{session_id}"

    session = @trade_sessions_v2[session_id]
    return unless session

    # Mark which player completed
    if session.player1_id == client_id
      session.instance_variable_set(:@player1_completed, true)
    elsif session.player2_id == client_id
      session.instance_variable_set(:@player2_completed, true)
    end

    # Check if both completed
    p1_complete = session.instance_variable_get(:@player1_completed)
    p2_complete = session.instance_variable_get(:@player2_completed)

    if p1_complete && p2_complete
      # Both players completed - record the trade in database
      player1_username = @clients[session.player1_id][:username] rescue "Unknown"
      player2_username = @clients[session.player2_id][:username] rescue "Unknown"

      # Increment trade count for both players
      begin
        @db.execute("UPDATE players SET total_trades = total_trades + 1 WHERE username = ?", [player1_username])
        @db.execute("UPDATE players SET total_trades = total_trades + 1 WHERE username = ?", [player2_username])
        @logger.info "[TRADE V2] Recorded trade for #{player1_username} and #{player2_username}"
      rescue => e
        @logger.error "[TRADE V2] Failed to record trade: #{e.message}"
      end

      # Clean up session
      cleanup_trade_v2(session_id)
      @logger.info "[TRADE V2] Session #{session_id} completed and cleaned up"
    end
  end

  #=============================================================================
  # Trade Decline V2
  #=============================================================================
  def handle_trade_decline_v2(client_id, data)
    target_id = data[:target_id] || data['target_id']
    session_id = data[:trade_session_id] || data['trade_session_id']
    reason = data[:reason] || data['reason'] || "declined"

    @logger.info "[TRADE V2] #{client_id} declined trade, session: #{session_id}, reason: #{reason}"

    session = @trade_sessions_v2[session_id]
    if session
      # Notify other player
      other_player_id = (session.player1_id == client_id) ? session.player2_id : session.player1_id

      send_to_client(other_player_id, {
        type: "trade_decline_v2",
        data: { reason: reason }
      })

      # Clean up
      cleanup_trade_v2(session_id)
    end
  end

  #=============================================================================
  # Cleanup Trade V2
  #=============================================================================
  def cleanup_trade_v2(session_id)
    session = @trade_sessions_v2[session_id]
    return unless session

    # Unlock players
    @player_trade_locks_v2.delete(session.player1_id)
    @player_trade_locks_v2.delete(session.player2_id)

    # Remove session
    @trade_sessions_v2.delete(session_id)

    @logger.info "[TRADE V2] Cleaned up session #{session_id}"
  end

  #=============================================================================
  # Handle Disconnect - Clean up any active trades
  #=============================================================================
  def cleanup_player_trades_v2(client_id)
    session_id = @player_trade_locks_v2[client_id]
    return unless session_id

    @logger.info "[TRADE V2] Cleaning up trades for disconnected player #{client_id}"

    session = @trade_sessions_v2[session_id]
    if session
      # Notify other player
      other_player_id = (session.player1_id == client_id) ? session.player2_id : session.player1_id

      send_to_client(other_player_id, {
        type: "trade_decline_v2",
        data: { reason: "disconnected" }
      })
    end

    cleanup_trade_v2(session_id)
  end

  #=============================================================================
  # Periodic Cleanup - Remove expired sessions
  #=============================================================================
  def cleanup_expired_trade_sessions_v2
    @trade_sessions_v2.each do |session_id, session|
      if session.expired?
        @logger.info "[TRADE V2] Session #{session_id} expired, cleaning up"

        # Notify both players
        send_to_client(session.player1_id, {
          type: "trade_decline_v2",
          data: { reason: "timeout" }
        })

        send_to_client(session.player2_id, {
          type: "trade_decline_v2",
          data: { reason: "timeout" }
        })

        cleanup_trade_v2(session_id)
      end
    end
  end
end

# Log module loaded when server is initialized (can't use @logger here as it's class-level)
