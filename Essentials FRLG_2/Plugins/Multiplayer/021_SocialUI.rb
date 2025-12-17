class SocialUI
  attr_reader :active

  def initialize
    @active = false
    @viewport = nil
    @sprites = {}
    @player_list = []
    @current_index = 0
    @mode = :players
    @keys_pressed = {}
    @scroll_offset = 0
    @visible_players = 4
    @card_height = 55
  end

  def activate
    return unless $multiplayer_client && $multiplayer_client.connected

    @active  =  true
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999

    $multiplayer_client.request_social_data

    create_sprites

    wait_count = 0
    initial_list_size = @player_list.length

    while wait_count < 20
      Graphics.update
      Input.update
      $multiplayer_client.update if $multiplayer_client
      refresh_player_list

      if @player_list.length > 0 && @player_list.length != initial_list_size
        puts "[SOCIAL UI] Received player data: #{@player_list.length} players"
        break
      end

      sleep(0.05)
      wait_count += 1
    end

    refresh_player_list
    puts "[SOCIAL UI] Final player list: #{@player_list.length} players"
  end

  def deactivate
    @active = false
    dispose_sprites
    @viewport.dispose if @viewport
    @viewport = nil
  end

  def update
    return unless @active

    Graphics.update
    Input.update

    handle_input
    update_animations
  end

  private

  def create_sprites

    @sprites[:background]  =  Sprite.new(@viewport)
    @sprites[:background].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites[:background].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(15, 15, 25, 240))

    @sprites[:title_bar]  =  Sprite.new(@viewport)
    @sprites[:title_bar].bitmap = Bitmap.new(Graphics.width, 60)
    @sprites[:title_bar].bitmap.fill_rect(0, 0, Graphics.width, 60, Color.new(40, 40, 60, 255))
    @sprites[:title_bar].bitmap.fill_rect(0, 58, Graphics.width, 2, Color.new(100, 180, 255, 255))
    @sprites[:title_bar].z = 1

    @sprites[:title_text] = Sprite.new(@viewport)
    @sprites[:title_text].bitmap = Bitmap.new(Graphics.width, 60)
    pbSetSystemFont(@sprites[:title_text].bitmap)
    @sprites[:title_text].bitmap.font.size = 32
    @sprites[:title_text].bitmap.font.bold = true
    @sprites[:title_text].bitmap.font.color = Color.new(255, 255, 255)
    @sprites[:title_text].z = 2

    @sprites[:tabs] = Sprite.new(@viewport)
    @sprites[:tabs].bitmap = Bitmap.new(Graphics.width, 40)
    @sprites[:tabs].y = 60
    @sprites[:tabs].z = 2

    @sprites[:list_bg] = Sprite.new(@viewport)
    @sprites[:list_bg].bitmap = Bitmap.new(Graphics.width - 40, Graphics.height - 180)
    @sprites[:list_bg].x = 20
    @sprites[:list_bg].y  =  110
    @sprites[:list_bg].bitmap.fill_rect(0, 0, @sprites[:list_bg].bitmap.width,
                                        @sprites[:list_bg].bitmap.height, Color.new(25, 25, 40, 220))
    @sprites[:list_bg].z = 1

    @sprites[:player_cards]  =  Sprite.new(@viewport)
    @sprites[:player_cards].bitmap = Bitmap.new(Graphics.width - 60, Graphics.height - 200)
    @sprites[:player_cards].x = 30
    @sprites[:player_cards].y = 120
    @sprites[:player_cards].z = 3

    @sprites[:cursor] = Sprite.new(@viewport)
    @sprites[:cursor].bitmap = Bitmap.new(Graphics.width - 80, @card_height)
    draw_cursor
    @sprites[:cursor].x = 40
    @sprites[:cursor].z = 2

    @sprites[:help] = Sprite.new(@viewport)
    @sprites[:help].bitmap = Bitmap.new(Graphics.width, 40)
    @sprites[:help].y = Graphics.height - 50
    @sprites[:help].z  =  4
    pbSetSystemFont(@sprites[:help].bitmap)
    @sprites[:help].bitmap.font.size = 20

    draw_title
    draw_tabs
    draw_help_text
  end

  def draw_cursor
    return unless @sprites[:cursor]

    bitmap = @sprites[:cursor].bitmap
    bitmap.clear

    bitmap.fill_rect(0, 0, bitmap.width, bitmap.height, Color.new(100, 180, 255, 100))

    bitmap.fill_rect(3, 3, bitmap.width - 6, bitmap.height - 6, Color.new(80, 160, 240, 150))

    bitmap.fill_rect(5, 5, bitmap.width - 10, bitmap.height - 10, Color.new(30, 30, 50, 0))
  end

  def draw_title
    return unless @sprites[:title_text]

    bitmap = @sprites[:title_text].bitmap
    bitmap.clear

    title = case @mode
            when :players then 'ONLINE PLAYERS'
            when :leaderboard_trades then "TRADE LEADERBOARD"
            when :leaderboard_elo then 'BATTLE RANKINGS'
            end

    bitmap.draw_text(20, 10, Graphics.width - 40, 40, title)

    if @mode == :players
      online_count = @player_list.count { |p| p[:online] || p[:id] }
      count_text = "#{online_count} Online"
      bitmap.font.size = 20
      bitmap.font.color = Color.new(150, 200, 255)
      bitmap.draw_text(Graphics.width - 200, 20, 180, 32, count_text, 2)
    end
  end

  def draw_tabs
    return unless @sprites[:tabs]

    bitmap = @sprites[:tabs].bitmap
    bitmap.clear

    tabs = [
      { mode: :players, name: "Players", x: 20 },
      { mode: :leaderboard_trades, name: 'Top Traders', x: 180 },
      { mode: :leaderboard_elo, name: 'Top Battlers', x: 380 }
    ]

    pbSetSystemFont(bitmap)
    bitmap.font.size = 22

    tabs.each do |tab|
      is_active  =  @mode == tab[:mode]

      color = is_active ? Color.new(60, 100, 180, 255) : Color.new(40, 40, 60, 200)
      bitmap.fill_rect(tab[:x], 5, 150, 30, color)

      bitmap.font.color = is_active ? Color.new(255, 255, 255) : Color.new(150, 150, 170)
      bitmap.draw_text(tab[:x], 5, 150, 30, tab[:name], 1)
    end
  end

  def draw_help_text
    return unless @sprites[:help]

    bitmap = @sprites[:help].bitmap
    bitmap.clear
    bitmap.font.color = Color.new(200, 200, 220)

    if @mode == :players
      text = "Arrow Keys: Navigate  |  ENTER: Actions  |  TAB: Switch View  |  ESC: Close"
    else
      text = "Arrow Keys: Scroll  |  TAB: Switch View  |  ESC: Close"
    end

    bitmap.draw_text(0, 10, Graphics.width, 32, text, 1)
  end

  def draw_player_cards
    return unless @sprites[:player_cards]

    bitmap = @sprites[:player_cards].bitmap
    bitmap.clear

    pbSetSystemFont(bitmap)

    case @mode
    when :players

      online_players = @player_list.select { |p| p[:online] }
      draw_players_list(bitmap, online_players)
    when :leaderboard_trades

      draw_trade_leaderboard(bitmap)
    when :leaderboard_elo

      draw_elo_leaderboard(bitmap)
    end
  end

  def draw_players_list(bitmap, player_list)
    visible_start = @scroll_offset
    visible_end = [@scroll_offset + @visible_players, player_list.length].min

    player_list[visible_start...visible_end].each_with_index do |player, display_index|
      y_pos  =  display_index * @card_height

      is_current = (visible_start + display_index) == @current_index
      card_color  =  is_current ? Color.new(40, 40, 70, 200) : Color.new(30, 30, 50, 150)

      bitmap.font.size = 20
      bitmap.font.bold = true
      bitmap.font.color = Color.new(255, 255, 255)
      bitmap.draw_text(15, y_pos + 2, 300, 24, player[:username])

      bitmap.font.size = 14
      bitmap.font.bold  =  false
      bitmap.font.color = Color.new(180, 220, 255)

      stats_text = sprintf("Trades: %d  │  W/L: %d/%d  │  ELO: %d",
                          player[:total_trades] || 0,
                          player[:wins] || 0,
                          player[:losses] || 0,
                          player[:elo] || 1000)
      bitmap.draw_text(15, y_pos + 28, 600, 20, stats_text)

      status_color = player[:in_battle] ? Color.new(255, 100, 100) : Color.new(100, 255, 100)
      bitmap.fill_rect(bitmap.width - 45, y_pos + 12, 10, 10, status_color)

      bitmap.font.size = 13
      bitmap.font.color = Color.new(200, 200, 200)
      status_text = player[:in_battle] ? "In Battle" : "Available"
      bitmap.draw_text(bitmap.width - 110, y_pos + 8, 60, 18, status_text, 2)
    end
  end

  def draw_trade_leaderboard(bitmap)

    sorted_players = @player_list.sort_by { |p| -(p[:total_trades] || 0) }

    visible_start = @scroll_offset
    visible_end = [@scroll_offset + @visible_players, sorted_players.length].min

    sorted_players[visible_start...visible_end].each_with_index do |player, display_index|
      y_pos = display_index * @card_height
      rank  =  visible_start + display_index + 1

      bitmap.font.size = 24
      bitmap.font.bold = true
      rank_color = case rank
                   when 1 then Color.new(255, 215, 0)
                   when 2 then Color.new(192, 192, 192)
                   when 3 then Color.new(205, 127, 50)
                   else Color.new(150, 150, 150)
                   end
      bitmap.font.color = rank_color
      bitmap.draw_text(8, y_pos + 5, 45, 30, "##{rank}")

      bitmap.font.size  =  18
      bitmap.font.bold  =  true
      bitmap.font.color = Color.new(255, 255, 255)
      bitmap.draw_text(60, y_pos + 2, 300, 24, player[:username])

      is_online  =  player[:online]
      bitmap.font.size = 12
      bitmap.font.bold = false
      bitmap.font.color = is_online ? Color.new(100, 255, 100) : Color.new(150, 150, 150)
      bitmap.draw_text(60, y_pos + 28, 150, 18, is_online ? "● Online" : "○ Offline")

      bitmap.font.size = 22
      bitmap.font.color = Color.new(100, 255, 150)
      bitmap.draw_text(bitmap.width - 180, y_pos + 8, 160, 28,
                      "#{player[:total_trades] || 0} trades", 2)
    end
  end

  def draw_elo_leaderboard(bitmap)

    sorted_players = @player_list.sort_by { |p| -(p[:elo] || 1000) }

    visible_start = @scroll_offset
    visible_end = [@scroll_offset + @visible_players, sorted_players.length].min

    sorted_players[visible_start...visible_end].each_with_index do |player, display_index|
      y_pos = display_index * @card_height
      rank = visible_start + display_index + 1

      bitmap.font.size = 24
      bitmap.font.bold  =  true
      rank_color = case rank
                   when 1 then Color.new(255, 215, 0)
                   when 2 then Color.new(192, 192, 192)
                   when 3 then Color.new(205, 127, 50)
                   else Color.new(150, 150, 150)
                   end
      bitmap.font.color = rank_color
      bitmap.draw_text(8, y_pos + 5, 45, 30, "##{rank}")

      bitmap.font.size = 18
      bitmap.font.bold = true
      bitmap.font.color = Color.new(255, 255, 255)
      username_with_status = player[:username]
      bitmap.draw_text(60, y_pos + 2, 300, 24, username_with_status)

      bitmap.font.size  =  14
      bitmap.font.bold = false
      bitmap.font.color  =  Color.new(200, 200, 220)
      wins = player[:wins] || 0
      losses = player[:losses] || 0
      total = wins + losses
      winrate = total > 0 ? ((wins.to_f / total) * 100).round : 0

      is_online  =  player[:online]
      status_text  =  is_online ? " ● Online" : " ○ Offline"
      status_color = is_online ? Color.new(100, 255, 100) : Color.new(150, 150, 150)

      bitmap.draw_text(60, y_pos + 26, 240, 20,
                      sprintf("%d-%d (%d%% winrate)", wins, losses, winrate))
      bitmap.font.size = 12
      bitmap.font.color = status_color
      bitmap.draw_text(230, y_pos + 28, 150, 18, status_text)

      elo = player[:elo] || 1000
      bitmap.font.size = 26
      bitmap.font.bold = true
      elo_color  =  case elo
                  when 0...900 then Color.new(180, 180, 180)
                  when 900...1100 then Color.new(150, 255, 150)
                  when 1100...1300 then Color.new(100, 150, 255)
                  when 1300...1500 then Color.new(200, 100, 255)
                  else Color.new(255, 100, 100)
                  end
      bitmap.font.color = elo_color
      bitmap.draw_text(bitmap.width - 180, y_pos + 10, 160, 32, elo.to_s, 2)
    end
  end

  def handle_input
    return unless @active

    # Use Input.triggerex? which respects window focus guard
    if Input.triggerex?(0x09)  # Tab key
      cycle_mode
    end

    if Input.triggerex?(0x26)  # Up arrow
      navigate_up
    end

    if Input.triggerex?(0x28)  # Down arrow
      navigate_down
    end

    if @mode == :players && Input.triggerex?(0x0D)  # Enter key
      show_player_actions
    end

    if Input.triggerex?(0x1B)  # Escape key
      deactivate
    end
  end

  def cycle_mode
    modes = [:players, :leaderboard_trades, :leaderboard_elo]
    current_idx = modes.index(@mode)
    @mode = modes[(current_idx + 1) % modes.length]

    @current_index = 0
    @scroll_offset = 0

    draw_title
    draw_tabs
    draw_help_text
    draw_player_cards
  end

  def get_displayed_list

    case @mode
    when :players

      @player_list.select { |p| p[:online] }
    when :leaderboard_trades

      @player_list.sort_by { |p| -(p[:total_trades] || 0) }
    when :leaderboard_elo

      @player_list.sort_by { |p| -(p[:elo] || 1000) }
    else
      @player_list
    end
  end

  def navigate_up

    displayed_list  =  get_displayed_list

    if @current_index > 0
      @current_index -= 1

      if @current_index < @scroll_offset
        @scroll_offset = @current_index
      end

      update_cursor_position
      draw_player_cards
    end
  end

  def navigate_down

    displayed_list = get_displayed_list

    if @current_index < displayed_list.length - 1
      @current_index += 1

      if @current_index >= @scroll_offset + @visible_players
        @scroll_offset = @current_index - @visible_players + 1
      end

      update_cursor_position
      draw_player_cards
    end
  end

  def update_cursor_position
    return unless @sprites[:cursor]

    display_index = @current_index - @scroll_offset

    if display_index < 0 || display_index >= @visible_players
      @sprites[:cursor].visible = false
    else
      @sprites[:cursor].visible = true
      @sprites[:cursor].y = 120 + (display_index * @card_height)
    end
  end

  def show_player_actions
    return if @player_list.empty?

    displayed_list  =  get_displayed_list
    return if displayed_list.empty?
    return if @current_index >= displayed_list.length

    selected_player = displayed_list[@current_index]
    return unless selected_player

    if @mode != :players
      show_player_profile(selected_player)
      return
    end

    if selected_player[:id] == $multiplayer_client.client_id
      pbMessage("That's you!")
      return
    end

    commands = []
    commands << "Request Trade" unless selected_player[:in_battle]
    commands << 'Request Battle' unless selected_player[:in_battle]
    commands << "View Profile"
    commands << "Cancel"

    choice  =  pbMessage("\\l[3]Actions for #{selected_player[:username]}:",
                       commands, -1)

    case choice
    when 0
      initiate_trade_request(selected_player)
    when 1
      initiate_battle_request(selected_player)
    when 2
      show_player_profile(selected_player)
    end
  end

  def initiate_trade_request(player)

    puts "[SOCIAL UI] Trade request clicked for player: #{player[:username]}"
    puts "[SOCIAL UI] Player data: id=#{player[:id]}, player_id=#{player[:player_id]}, online=#{player[:online]}"

    deactivate

    if defined?(pbModernTradeManager)
      pbModernTradeManager.initiate_trade(player[:id], player[:username])
    else

      scene  =  PokemonParty_Scene.new
      screen = PokemonPartyScreen.new(scene, $player.party)
      screen.pbStartScene(_INTL('Choose a Pokemon to offer.'), false)

      pkmn_choice = screen.pbChoosePokemon
      screen.pbEndScene

      if pkmn_choice >= 0
        pokemon = $player.party[pkmn_choice]

        if pokemon && defined?(pbModernTradeManager)
          pbModernTradeManager.send_trade_offer(player[:id], player[:username], pokemon)
        end
      end
    end
  end

  def initiate_battle_request(player)

    format_commands  =  [
      "Single Battle",
      'Double Battle',
      "Triple Battle",
      "Rotation Battle",
      "Cancel"
    ]

    format_choice = pbMessage('\\l[3]Battle format?', format_commands, -1)

    if format_choice >= 0 && format_choice < 4

      battle_format = case format_choice
      when 0 then :single
      when 1 then :double
      when 2 then :triple
      when 3 then :rotation
      else :single
      end

      $multiplayer_client.send_battle_request(player[:id], battle_format)
      pbMessage("Battle request sent to #{player[:username]}!")
    end
  end

  def show_player_profile(player)
    profile_text = sprintf(
      'Player: %s\n\nTotal Trades: %d\nBattle Record: %d-%d\nELO Rating: %d\nWin Rate: %d%%',
      player[:username],
      player[:total_trades] || 0,
      player[:wins] || 0,
      player[:losses] || 0,
      player[:elo] || 1000,
      calculate_winrate(player)
    )

    pbMessage(profile_text)
  end

  def calculate_winrate(player)
    wins  =  player[:wins] || 0
    losses = player[:losses] || 0
    total  =  wins + losses
    return 0 if total == 0
    ((wins.to_f / total) * 100).round
  end

  def refresh_player_list

    if $multiplayer_client && $multiplayer_client.connected
      @player_list = $multiplayer_client.social_player_list || []
      draw_player_cards
      update_cursor_position
    end
  end

  def update_animations

    if @sprites[:cursor]
      phase = (Graphics.frame_count % 60) / 60.0
      alpha_mod  =  (Math.sin(phase * 2 * Math::PI) * 30).to_i

    end
  end

  def dispose_sprites
    @sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite.bitmap
      sprite.dispose
    end
    @sprites.clear
  end
end

$social_ui = nil

def pbOpenSocialUI
  return unless $multiplayer_client && $multiplayer_client.connected

  $social_ui ||= SocialUI.new
  $social_ui.activate

  loop do    $social_ui.update
    break unless $social_ui.active
  end
end
