class MultiplayerBattleRequest
  attr_reader :from_player_id
  attr_reader :from_username
  attr_reader :timestamp
  attr_reader :battle_format

  FORMATS = [:single, :double, :triple, :rotation]

  def initialize(from_player_id, from_username, battle_format = :single)
    @from_player_id = from_player_id
    @from_username = from_username
    @battle_format = battle_format
    @timestamp = Time.now
  end

  def expired?
    Time.now - @timestamp > 30
  end
end

class MultiplayerBattleManager
  def initialize
    @pending_requests = []
    @active_battle = nil
    @sent_request = nil
    @request_ui = nil
  end

  def send_battle_request(target_player_id, target_username, format = :single)

    unless MultiplayerBattleRequest::FORMATS.include?(format)
      pbMessage(_INTL("Invalid battle format!"))
      return false
    end

    if @active_battle
      pbMessage(_INTL("You're already in a battle!"))
      return false
    end

    if @sent_request && !@sent_request.expired?
      pbMessage(_INTL("You've already sent a battle request!\\nPlease wait for a response."))
      return false
    end

    if pbMultiplayerConnected?
      pbMultiplayerClient.send_battle_request(target_player_id, format)
      @sent_request = MultiplayerBattleRequest.new($multiplayer_client.client_id, $player.name, format)
      pbMessage(_INTL("Battle request sent to {1}!", target_username))
      return true
    end

    pbMessage(_INTL("Not connected to server!"))
    return false
  end

  def receive_battle_request(from_player_id, from_username, format)

    return if @active_battle

    existing  =  @pending_requests.find { |r| r.from_player_id == from_player_id }
    return if existing

    request = MultiplayerBattleRequest.new(from_player_id, from_username, format)
    @pending_requests << request

    format_name = format.to_s.capitalize
    pbMultiplayerNotify("#{from_username} wants to battle! (#{format_name}) - Press F8 to view", 8.0)

  end

  def has_pending_requests?
    return @pending_requests.any?
  end

  def pending_request_count
    return @pending_requests.size
  end

  def update

    @pending_requests.reject! { |r| r.expired? }

    @sent_request = nil if @sent_request && @sent_request.expired?
  end

  def show_request_ui
    return if @pending_requests.empty?
    return if @request_ui

    @request_ui = MultiplayerBattleRequestUI.new(@pending_requests)
    result = @request_ui.run

    if result

      accept_battle_request(result)
    end

    @request_ui = nil
  end

  def accept_battle_request(request)

    @pending_requests.delete(request)

    if pbMultiplayerConnected?
      pbMultiplayerClient.accept_battle_request(request.from_player_id, request.battle_format)

      pbMultiplayerNotify("Accepted battle vs #{request.from_username}! Preparing...", 5.0)

      puts '[BATTLE] Waiting for server to start synchronized battle...'
    end
  end

  def decline_battle_request(request)

    @pending_requests.delete(request)

    if pbMultiplayerConnected?
      pbMultiplayerClient.decline_battle_request(request.from_player_id)

      pbMultiplayerNotify("Declined battle with #{request.from_username}", 4.0)
    end
  end

  def start_multiplayer_battle(opponent_id, opponent_name, format)

    opponent_party_data = nil
    if pbMultiplayerConnected?
      pbMultiplayerClient.request_battle_party(opponent_id)

      timeout = 50
      while timeout > 0 && !opponent_party_data
        Graphics.update
        pbMultiplayerClient.update
        opponent_party_data = pbMultiplayerClient.get_received_battle_party(opponent_id)
        sleep(0.1)
        timeout -= 1
      end

      unless opponent_party_data
        pbMessage(_INTL("Failed to load opponent's party!\\nBattle cancelled."))
        @active_battle = false
        return false
      end
    else
      pbMessage(_INTL("Not connected to server!\\nBattle cancelled."))
      @active_battle = false
      return false
    end

    @active_battle = true
    puts "Starting multiplayer battle vs #{opponent_name} (#{format})"

    opponent_trainer = NPCTrainer.new(opponent_name, :POKEMONTRAINER_Red)

    opponent_trainer.party = []
    puts "[BATTLE DEBUG] Deserializing #{opponent_party_data.length} Pokemon from opponent"
    opponent_party_data.each_with_index do |pokemon_data, idx|
      puts "[BATTLE DEBUG] Pokemon #{idx} data keys: #{pokemon_data.keys.inspect}"
      puts "[BATTLE DEBUG] Pokemon #{idx} species: #{pokemon_data[:species] || pokemon_data['species']}"
      pokemon  =  pbModernTradeManager.deserialize_pokemon(pokemon_data)
      puts "[BATTLE DEBUG] Deserialized: #{pokemon.name} Lv#{pokemon.level}"
      opponent_trainer.party << pokemon
    end

    if opponent_trainer.party.empty?
      pbMessage(_INTL("Opponent has no valid Pokemon!\\nBattle cancelled."))
      @active_battle = false
      return false
    end

    puts "[BATTLE DEBUG] Player party size: #{$player.party.length}"
    puts "[BATTLE DEBUG] Opponent party size: #{opponent_trainer.party.length}"
    opponent_trainer.party.each_with_index do |pkmn, i|
      puts "[BATTLE DEBUG] Opponent Pokemon #{i}: #{pkmn.name} Lv#{pkmn.level}"
    end

    setBattleRule('single')
    case format
    when :double
      setBattleRule('double')
    when :triple
      setBattleRule("triple")
    when :rotation
      setBattleRule("rotation")
    end

    setBattleRule('noExp')

    player_party = $player.party

    opponent_party = opponent_trainer.party

    scene = BattleCreationHelperMethods.create_battle_scene

    battle  =  Battle.new(scene, player_party, opponent_party, $player, [opponent_trainer])

    BattleCreationHelperMethods.prepare_battle(battle)

    decision = 0
    pbBattleAnimation(pbGetTrainerBattleBGM(opponent_trainer)) do      decision = battle.pbStartBattle
    end

    BattleCreationHelperMethods.after_battle(decision, true)

    battle_result = (decision == 1)

    if pbMultiplayerConnected?
      my_client_id = $multiplayer_client.client_id
      if battle_result
        $multiplayer_client.report_battle_complete(my_client_id, opponent_id)
      else
        $multiplayer_client.report_battle_complete(opponent_id, my_client_id)
      end
    end

    if battle_result
      pbMessage(_INTL("You won the battle!"))
    else
      pbMessage(_INTL("You lost the battle!"))
    end

    @active_battle = false
    return battle_result
  end

  def has_pending_requests?
    !@pending_requests.empty?
  end

  def in_battle?
    @active_battle
  end
end

class MultiplayerBattleRequestUI
  def initialize(requests)
    @requests = requests
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @selection = 0
    create_ui
  end

  def create_ui

    @sprites[:overlay] = Sprite.new(@viewport)
    @sprites[:overlay].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites[:overlay].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))

    @sprites[:window] = Sprite.new(@viewport)
    width = 400
    height = 300
    @sprites[:window].bitmap = Bitmap.new(width, height)
    @sprites[:window].x = (Graphics.width - width) / 2
    @sprites[:window].y = (Graphics.height - height) / 2

    @sprites[:window].bitmap.fill_rect(0, 0, width, height, Color.new(255, 255, 255, 255))
    @sprites[:window].bitmap.fill_rect(4, 4, width - 8, height - 8, Color.new(40, 40, 60, 255))

    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(width - 20, 40)
    @sprites[:title].x = @sprites[:window].x + 10
    @sprites[:title].y = @sprites[:window].y + 10
    pbSetSystemFont(@sprites[:title].bitmap)
    @sprites[:title].bitmap.font.size = 24
    @sprites[:title].bitmap.font.color = Color.new(255, 255, 255, 255)
    @sprites[:title].bitmap.draw_text(0, 0, width - 20, 40, "Battle Requests", 1)

    update_display
  end

  def update_display

    if @sprites[:requests]
      @sprites[:requests].bitmap.dispose
      @sprites[:requests].dispose
    end

    width = 360
    height  =  200
    @sprites[:requests] = Sprite.new(@viewport)
    @sprites[:requests].bitmap  =  Bitmap.new(width, height)
    @sprites[:requests].x = @sprites[:window].x + 20
    @sprites[:requests].y  =  @sprites[:window].y + 60

    @requests.each_with_index do |request, index|
      y_offset = index * 50
      next if y_offset + 45 > height

      if index == @selection
        @sprites[:requests].bitmap.fill_rect(0, y_offset, width, 45, Color.new(100, 100, 120, 255))
      end

      @sprites[:requests].bitmap.fill_rect(0, y_offset, width, 45, Color.new(150, 150, 150, 255))
      @sprites[:requests].bitmap.fill_rect(2, y_offset + 2, width - 4, 41, Color.new(60, 60, 80, 255))

      pbSetSystemFont(@sprites[:requests].bitmap)
      @sprites[:requests].bitmap.font.size = 20
      @sprites[:requests].bitmap.font.color = Color.new(255, 255, 255, 255)
      @sprites[:requests].bitmap.draw_text(10, y_offset + 5, width - 20, 24, request.from_username)

      @sprites[:requests].bitmap.font.size = 14
      @sprites[:requests].bitmap.font.color = Color.new(200, 200, 200, 255)
      format_text = "Format: #{request.battle_format.to_s.capitalize}"
      @sprites[:requests].bitmap.draw_text(10, y_offset + 25, width - 20, 20, format_text)
    end

    if @sprites[:instructions]
      @sprites[:instructions].bitmap.dispose
      @sprites[:instructions].dispose
    end

    @sprites[:instructions] = Sprite.new(@viewport)
    @sprites[:instructions].bitmap = Bitmap.new(360, 30)
    @sprites[:instructions].x = @sprites[:window].x + 20
    @sprites[:instructions].y = @sprites[:window].y + 265
    pbSetSystemFont(@sprites[:instructions].bitmap)
    @sprites[:instructions].bitmap.font.size = 16
    @sprites[:instructions].bitmap.font.color = Color.new(200, 200, 200, 255)
    @sprites[:instructions].bitmap.draw_text(0, 0, 360, 30, "↑↓ Navigate  Enter: Accept  Esc: Decline", 1)
  end

  def run
    loop do      Graphics.update
      Input.update

      if Input.trigger?(Input::UP)
        @selection = (@selection - 1) % @requests.length
        update_display
      end

      if Input.trigger?(Input::DOWN)
        @selection = (@selection + 1) % @requests.length
        update_display
      end

      if Input.trigger?(Input::USE)
        request = @requests[@selection]
        dispose
        return request
      end

      if Input.trigger?(Input::BACK)
        if pbConfirmMessage(_INTL("Decline this battle request?"))
          request = @requests[@selection]
          $multiplayer_battle_manager.decline_battle_request(request)
          @requests.delete(request)

          if @requests.empty?
            dispose
            return nil
          end

          @selection = 0 if @selection >= @requests.length
          update_display
        end
      end
    end
  end

  def dispose
    @sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite.bitmap
      sprite.dispose
    end
    @viewport.dispose
  end
end

$multiplayer_battle_manager = nil

def pbMultiplayerBattleManager
  $multiplayer_battle_manager ||= MultiplayerBattleManager.new
  return $multiplayer_battle_manager
end

class Scene_Map
  alias battle_original_update update

  def update

    if pbIsMultiplayerMode? && pbMultiplayerConnected?
      pbMultiplayerBattleManager.update
    end

    battle_original_update
  end
end
