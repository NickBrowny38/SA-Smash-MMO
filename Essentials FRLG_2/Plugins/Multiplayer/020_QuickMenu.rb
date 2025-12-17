class MultiplayerQuickMenu
  def initialize
    @battle_menu_open  =  false
    @trade_menu_open = false
    @social_ui_open = false
    @auction_ui_open = false
  end

  def update
    return unless pbIsMultiplayerMode? && pbMultiplayerConnected?
    return if $game_temp.message_window_showing
    return if $game_player.move_route_forcing

    # IMPORTANT: Only check keys if window has focus
    # Using Input.triggerex? which respects window focus guard
    if Input.triggerex?(0x77)  # F8 key
      unless @pending_requests_open
        open_pending_requests
        @pending_requests_open = true
      end
    else
      @pending_requests_open = false
    end

    if Input.triggerex?(0x51)  # Q key
      unless @auction_ui_open
        open_auction_house
        @auction_ui_open = true
      end
    else
      @auction_ui_open = false
    end

    if Input.triggerex?(0x4C)  # L key
      unless @social_ui_open
        open_social_ui
        @social_ui_open = true
      end
    else
      @social_ui_open = false
    end

    if Input.trigger?(Input::B_KEY) && !@battle_menu_open && !@trade_menu_open && !@social_ui_open && !@auction_ui_open
      open_battle_menu
    end

    if Input.trigger?(Input::R_KEY) && !@battle_menu_open && !@trade_menu_open && !@social_ui_open && !@auction_ui_open
      open_trade_menu
    end
  end

  def open_pending_requests

    has_battle_requests = pbMultiplayerBattleManager && pbMultiplayerBattleManager.has_pending_requests?

    has_trade_offers = false
    if defined?(pbModernTradeManager) && pbModernTradeManager.current_trade_state == TradeState::WAITING_FOR_OFFER
      has_trade_offers = true
    end

    if !has_battle_requests && !has_trade_offers
      pbMessage(_INTL("No pending requests."))
      return
    end

    if has_battle_requests && has_trade_offers
      commands = []
      commands << _INTL("Battle Requests ({1})", pbMultiplayerBattleManager.pending_request_count)
      commands << _INTL("Trade Offers")
      commands << _INTL("Cancel")

      choice = pbMessage(_INTL("View which requests?"), commands, -1)

      case choice
      when 0
        pbMultiplayerBattleManager.show_request_ui
      when 1
        handle_trade_offer_response
      end
    elsif has_battle_requests

      pbMultiplayerBattleManager.show_request_ui
    elsif has_trade_offers

      handle_trade_offer_response
    end
  end

  def handle_trade_offer_response

    if defined?(pbModernTradeManager) && pbModernTradeManager.current_trade_state == TradeState::WAITING_FOR_OFFER
      pbModernTradeManager.accept_trade_offer
    elsif defined?(pbModernTradeManager) && pbModernTradeManager
      pbModernTradeManager.show_trade_ui
    end
  end

  def open_social_ui
    pbOpenSocialUI if defined?(pbOpenSocialUI)
  end

  def open_auction_house
    pbOpenAuctionHouse if defined?(pbOpenAuctionHouse)
  end

  def open_battle_menu
    @battle_menu_open = true

    remote_players = pbMultiplayerClient.get_remote_players_on_map($game_map.map_id)

    if remote_players.empty?
      pbMessage(_INTL("No players nearby to battle!"))
      @battle_menu_open = false
      return
    end

    commands = []
    player_ids = []

    remote_players.each do |player_data|
      commands << player_data[:username]
      player_ids << player_data[:id]
    end
    commands << "Cancel"

    choice = pbMessage(_INTL('Challenge who to battle?'), commands, -1)

    if choice >= 0 && choice < player_ids.length

      format_commands = [
        "Single Battle",
        'Double Battle',
        "Triple Battle",
        "Rotation Battle",
        "Cancel"
      ]

      format_choice = pbMessage(_INTL("Battle format?"), format_commands, -1)

      if format_choice >= 0 && format_choice < 4
        target_id = player_ids[choice]
        target_name = commands[choice]

        battle_format = case format_choice
        when 0 then :single
        when 1 then :double
        when 2 then :triple
        when 3 then :rotation
        else :single
        end

        pbMultiplayerClient.send_battle_request(target_id, battle_format)
        pbMessage(_INTL("Battle request sent to {1}!", target_name))
      end
    end

    @battle_menu_open  =  false
  end

  def open_trade_menu
    @trade_menu_open  =  true

    remote_players  =  pbMultiplayerClient.get_remote_players_on_map($game_map.map_id)
    puts "[TRADE MENU DEBUG] Found #{remote_players.size} players on map #{$game_map.map_id}"
    remote_players.each { |p| puts "  - Player ID: #{p[:id]}, Username: #{p[:username]}" }

    if remote_players.empty?
      pbMessage(_INTL('No players nearby to trade with!'))
      @trade_menu_open = false
      return
    end

    if !$player || !$player.party || $player.party.length == 0
      pbMessage(_INTL("You don't have any Pokemon to trade!"))
      @trade_menu_open = false
      return
    end

    commands = []
    player_ids = []
    seen_ids = {}

    remote_players.each do |player_data|
      player_id = player_data[:id]

      next if seen_ids[player_id]

      commands << player_data[:username]
      player_ids << player_id
      seen_ids[player_id] = true
    end
    commands << "Cancel"

    puts "[TRADE MENU DEBUG] Final menu has #{commands.size - 1} players"

    choice = pbMessage(_INTL("Trade with who?"), commands, -1)

    if choice >= 0 && choice < player_ids.length
      target_id = player_ids[choice]
      target_name = commands[choice]

      scene = PokemonParty_Scene.new
      screen = PokemonPartyScreen.new(scene, $player.party)
      screen.pbStartScene(_INTL('Choose a Pokemon to offer.'), false)

      pkmn_choice = screen.pbChoosePokemon
      screen.pbEndScene

      if pkmn_choice >= 0
        pokemon = $player.party[pkmn_choice]

        if pokemon

          pbModernTradeManager.send_trade_offer(target_id, target_name, pokemon)
        end
      end
    end

    @trade_menu_open = false
  end
end

$multiplayer_quick_menu = nil

def pbMultiplayerQuickMenu
  $multiplayer_quick_menu ||= MultiplayerQuickMenu.new
  return $multiplayer_quick_menu
end
