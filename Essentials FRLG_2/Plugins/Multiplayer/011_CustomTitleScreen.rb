class PokemonLoadScreen
  alias multiplayer_pbStartLoadScreen pbStartLoadScreen unless method_defined?(:multiplayer_pbStartLoadScreen)

  def pbStartLoadScreen
    mode = pbGameModeSelection

    case mode
    when GameMode::SINGLEPLAYER
      pbSetGameMode(GameMode::SINGLEPLAYER)
      pbSingleplayerMenu

    when GameMode::MULTIPLAYER
      pbSetGameMode(GameMode::MULTIPLAYER)
      pbMultiplayerMenu

    else
      $scene = pbCallTitle
      return
    end
  end

  def pbSingleplayerMenu

    commands = []
    commands.push(_INTL("Continue")) if SaveData.exists?
    commands.push(_INTL("New Game"))
    commands.push(_INTL("Options"))
    commands.push(_INTL("Back"))

    @scene.pbStartScene(commands, false, nil, nil, 0)
    @scene.pbStartScene2

    loop do      command = @scene.pbChoose(commands)

      if !SaveData.exists?
        command += 1 if command >= 0
      end

      case command
      when 0
        if SaveData.exists?
          @scene.pbEndScene

          Game.load(load_save_file(SaveData::FILE_PATH))
          return
        else
          pbPlayBuzzerSE
        end

      when 1
        @scene.pbEndScene
        Game.start_new
        return

      when 2
        pbFadeOutIn do          scene = PokemonOption_Scene.new
          screen = PokemonOptionScreen.new(scene)
          screen.pbStartScreen(true)
        end

      when 3
        pbPlayCloseMenuSE
        @scene.pbEndScene
        $scene = pbCallTitle
        return

      else
        pbPlayBuzzerSE
      end
    end
  end

  def pbMultiplayerMenu

    commands = []
    commands.push(_INTL("Join Server"))
    commands.push(_INTL('Options'))
    commands.push(_INTL("Back"))

    @scene.pbStartScene(commands, false, nil, nil, 0)
    @scene.pbStartScene2

    loop do      command = @scene.pbChoose(commands)

      case command
      when 0
        @scene.pbEndScene
        if pbJoinMultiplayerGame

          return
        else

          $scene = pbCallTitle
          return
        end

      when 1
        pbFadeOutIn do          scene  =  PokemonOption_Scene.new
          screen = PokemonOptionScreen.new(scene)
          screen.pbStartScreen(true)
        end

      when 2
        pbPlayCloseMenuSE
        @scene.pbEndScene
        $scene = pbCallTitle
        return

      else
        pbPlayBuzzerSE
      end
    end
  end
end

def pbGameModeSelection

  commands = []
  commands.push(_INTL("Singleplayer"))
  commands.push(_INTL("Multiplayer"))
  commands.push(_INTL('Quit Game'))

  scene = PokemonLoad_Scene.new
  scene.pbStartScene(commands, false, nil, nil, 0)
  scene.pbStartScene2

  loop do    command = scene.pbChoose(commands)

    case command
    when 0
      pbPlayDecisionSE
      scene.pbEndScene
      return GameMode::SINGLEPLAYER

    when 1
      pbPlayDecisionSE
      scene.pbEndScene
      return GameMode::MULTIPLAYER

    when 2
      pbPlayCloseMenuSE
      scene.pbEndScene
      $scene = nil
      return nil

    else
      pbPlayBuzzerSE
    end
  end
end

def pbJoinMultiplayerGame
  begin

    $multiplayer_has_saved_position = false
    $multiplayer_auto_connected = true

    Game.start_new

    pbSetGameMode(GameMode::MULTIPLAYER)
    puts "Game mode RESTORED to MULTIPLAYER after Game.start_new"

    10.times do      Graphics.update
      Input.update
    end

    max_attempts = 3
    attempt = 0
    username = nil
    password = nil
    connected = false

    while attempt < max_attempts && !connected
      attempt += 1

      username, password = pbMultiplayerLoginScreen(false)

      if username.nil? || username.empty?
        puts "ERROR: Login cancelled or failed - no username provided"
        pbMessage(_INTL("Login cancelled."))
        return false
      end

      puts "Login attempt #{attempt}/#{max_attempts}: #{username}"

      $player.name = username if $player
      puts "Player name set to: #{$player.name}"

      server_host  =  MultiplayerConfig::SERVER_HOST
      server_port = MultiplayerConfig::SERVER_PORT

      puts "Connecting to server #{server_host}:#{server_port}..."

      if pbConnectToMultiplayer(server_host, server_port, username, password)

        puts 'Waiting for server authentication...'
        30.times do
          break unless pbMultiplayerConnected?
          pbMultiplayerClient.update
          sleep(0.05)
        end

        # Check for errors FIRST - even if disconnected, the error message may have been saved
        error = pbMultiplayerClient.get_last_error if pbMultiplayerClient

        if error
          puts "Server error: #{error}"
          pbDisconnectFromMultiplayer

          if error.include?("password") || error.include?("Invalid")
            puts "Invalid password - showing error to user"
            pbSimpleAlert("LOGIN FAILED", "Invalid password!\n\nPlease check your password and try again.")
            pbClearMultiplayerCredentials if attempt == 1
          elsif error.include?("already online")
            pbSimpleAlert("LOGIN FAILED", "That username is already logged in!\n\nPlease use a different username.")
            return false
          elsif error.include?("Server full")
            pbSimpleAlert("SERVER FULL", "The server is full!\n\nPlease try again later.")
            return false
          elsif error.include?("Registration failed")
            pbSimpleAlert("REGISTRATION FAILED", "Could not create account.\n\nPlease try a different username.")
          else
            pbSimpleAlert("SERVER ERROR", error)
          end
        elsif pbMultiplayerConnected?
          puts 'Authentication successful!'
          connected = true
        else
          puts "ERROR: Lost connection immediately after connecting"
          pbSimpleAlert("CONNECTION FAILED", "Connection failed!\n\nThe server may be offline or unreachable.")
          return false
        end
      else

        puts 'ERROR: Failed to connect to server'
        pbSimpleAlert("CONNECTION FAILED", "Connection failed!\n\nThe server may be offline or unreachable.\nPlease check your connection and try again later.")
        return false
      end
    end

    unless connected
      pbSimpleAlert("LOGIN FAILED", "Maximum login attempts exceeded.\n\nReturning to title screen.")
      return false
    end

    puts "Connected! Waiting for player data from server..."

    100.times do
      if pbMultiplayerConnected?
        pbMultiplayerClient.update
      else
        puts 'ERROR: Lost connection to server while loading'
        pbMessage(_INTL("Connection lost while loading your character!\\nReturning to title screen."))
        return false
      end
      sleep(0.05)
      break if $multiplayer_has_saved_position
    end

    unless $multiplayer_has_saved_position
      puts "ERROR: Timed out waiting for player data from server"
      pbMessage(_INTL("Server did not respond with your character data.\\nReturning to title screen."))
      return false
    end

      puts "=== SERVER DATA CHECK ==="
      puts "Has saved position flag: #{$multiplayer_has_saved_position || 'nil'}"
      puts "Saved map: #{$multiplayer_saved_map || 'nil'}"
      puts "Saved X: #{$multiplayer_saved_x || 'nil'}"
      puts "Saved Y: #{$multiplayer_saved_y || 'nil'}"
      puts "========================="

      default_spawn_map = 3
      default_spawn_x = 25
      default_spawn_y = 6
      spawn_dir = 2

      if $multiplayer_has_saved_position && $multiplayer_saved_map &&
         $multiplayer_saved_x && $multiplayer_saved_y
        spawn_map = $multiplayer_saved_map
        spawn_x = $multiplayer_saved_x
        spawn_y = $multiplayer_saved_y
      else
        spawn_map = default_spawn_map
        spawn_x = default_spawn_x
        spawn_y = default_spawn_y
      end

      is_returning_player = false
      if spawn_map != default_spawn_map || spawn_x != default_spawn_x || spawn_y != default_spawn_y

        is_returning_player = true
        puts "RETURNING PLAYER! Using server position: Map #{spawn_map} (#{spawn_x}, #{spawn_y})"
      elsif $multiplayer_server_sent_pokemon_data && $player && $player.party.any?

        is_returning_player = true
        puts "RETURNING PLAYER! At spawn with #{$player.party.size} Pokemon"
      else

        is_returning_player = false
        puts "NEW PLAYER! Using default spawn: Map #{spawn_map} (#{spawn_x}, #{spawn_y})"
      end

      puts "Setting event blocking flags BEFORE map initialization..."

      $multiplayer_disable_common_events = true

      $map_factory = PokemonMapFactory.new(spawn_map)

      $map_factory.setup(spawn_map)

      $game_temp.player_new_map_id  =  spawn_map
      $game_temp.player_new_x = spawn_x
      $game_temp.player_new_y = spawn_y
      $game_temp.player_new_direction = spawn_dir

      $game_player.moveto(spawn_x, spawn_y)
      case spawn_dir
      when 2 then $game_player.turn_down
      when 4 then $game_player.turn_left
      when 6 then $game_player.turn_right
      when 8 then $game_player.turn_up
      end
      $game_player.straighten

      begin
        if $player && $player.character_ID

          charset = GameData::PlayerMetadata.get($player.character_ID).walk_charset rescue nil
          if charset
            $game_player.character_name = charset
            $game_player.character_hue  =  0
            puts "Set player sprite from character_ID: #{$game_player.character_name}"
          end
        end
      rescue => e
        puts "Error setting player charset: #{e.message}"
      end

      if !$game_player.character_name || $game_player.character_name.empty?
        $game_player.character_name = "trainer_POKEMONTRAINER_Red"
        $game_player.character_hue = 0
        puts "Set player sprite to fallback: #{$game_player.character_name}"
      end

      puts "Map factory initialized and set up for Map #{spawn_map}"
      puts "Player position set: (#{spawn_x}, #{spawn_y}) facing #{spawn_dir}"

      $multiplayer_disable_common_events = false

      if $game_player
        $game_player.instance_variable_set(:@mp_blocked_events, {})
      end

      puts "Events re-enabled - map initialization complete"

      puts "Player has #{$player ? $player.party.length : 0} Pokemon from server data"

      $multiplayer_show_welcome  =  false
      $multiplayer_show_starter_choice = false

      welcome_msg = is_returning_player ? "Welcome back!" : "Welcome to the server!"
      pbMultiplayerNotify(welcome_msg, 4.0) if defined?(pbMultiplayerNotify)

      $scene  =  Scene_Map.new

      if $multiplayer_client && $player && $player.party && $player.party.length > 0
        puts "Sending full Pokemon party data to server..."
        $multiplayer_client.send_player_data
      end

      puts 'Successfully joined multiplayer game!'

      if defined?(FollowingPkmn) && $player && $player.party && $player.party.length > 0
        $PokemonGlobal.follower_toggled  =  true if $PokemonGlobal.respond_to?(:follower_toggled=)
        $multiplayer_needs_follower_init  =  true
        puts "[Following] Will initialize follower after map is ready"
      end

      $multiplayer_music_enabled  =  false
      $multiplayer_play_music_on_first_update  =  true

      puts "Scene_Map created - main loop will start the game"
      return true
  rescue SystemStackError => e

    puts "!!! SYSTEM STACK ERROR during login !!!"
    puts "This is usually caused by alias recursion in Scene_Map or Graphics.update"
    puts "Error: #{e.message}"
    puts e.backtrace[0..10].join("\n")

    pbDisconnectFromMultiplayer if pbMultiplayerConnected?

    pbSimpleAlert("LOGIN ERROR", "System stack overflow!\n\nThis is a rare error. Please try again.\nIf it persists, restart the game.")
    return false
  rescue => e
    puts "Error in pbJoinMultiplayerGame: #{e.class.name} - #{e.message}"
    puts e.backtrace[0..20].join("\n")

    pbDisconnectFromMultiplayer if pbMultiplayerConnected?

    pbMessage(_INTL("Login error: {1}", e.message))
    return false
  end
end
