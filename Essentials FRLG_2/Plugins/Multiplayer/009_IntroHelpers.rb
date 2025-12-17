def pbShouldSkipIntro?
  return false unless defined?(pbIsMultiplayerMode?)
  return false unless pbIsMultiplayerMode?
  return MultiplayerConfig::SKIP_INTRO_IN_MULTIPLAYER
end

def pbIntroComplete?
  return true unless defined?(MultiplayerConfig)
  return MultiplayerConfig.intro_complete?
end

def pbAllowMultiplayerDuringIntro?
  return true unless defined?(MultiplayerConfig)
  return MultiplayerConfig::ALLOW_MP_DURING_INTRO
end

def pbSetIntroComplete
  return unless defined?(MultiplayerConfig)
  return if MultiplayerConfig::INTRO_COMPLETE_FLAG.nil?

  begin
    if MultiplayerConfig::INTRO_COMPLETE_FLAG.is_a?(String) || MultiplayerConfig::INTRO_COMPLETE_FLAG.is_a?(Symbol)

      $game_switches[MultiplayerConfig::INTRO_COMPLETE_FLAG] = true
    elsif MultiplayerConfig::INTRO_COMPLETE_FLAG.is_a?(Integer)

      $game_switches[MultiplayerConfig::INTRO_COMPLETE_FLAG] = true
    end
    puts "Intro completion flag set: #{MultiplayerConfig::INTRO_COMPLETE_FLAG}"
  rescue => e
    puts "Error setting intro completion flag: #{e.message}"
  end
end

def pbQuickStartMultiplayer

  if !$player || !$player.name || $player.name.empty? || $player.name == "Unnamed"
    pbTrainerName
  end

  if !$player || !$player.name || $player.name.empty? || $player.name == "Unnamed"
    $player.name = "Player#{rand(100..999)}" if $player
  end

  pbWait(10) if defined?(pbWait)

  pbAutoConnectMultiplayer

  pbWait(30) if defined?(pbWait)

  pbMessage("\\se[Battle ball drop]Connected to multiplayer!\\wtnp[10]") if defined?(pbMessage)
end

def pbJustConnect
  pbAutoConnectMultiplayer
  pbWait(20) if defined?(pbWait)
end

def pbEnsurePlayerName
  if !$player || !$player.name || $player.name.empty? || $player.name == "Unnamed"
    $player.name = "Player#{rand(100..999)}" if $player
  end
end

def pbGetPlayerHouseMap

  [3, 4, 5, 6].each do |map_id|
    begin
      map_file  =  sprintf("Data/Map%03d.rxdata", map_id)
      if FileTest.exist?(map_file)
        return map_id
      end
    rescue
      next
    end
  end
  return 3
end

def pbShowLoadingMessage
  if defined?(pbMessage)
    pbMessage("\\se[Door exit]Entering the world...\\wtnp[5]")
  end
  pbWait(10) if defined?(pbWait)
end

def pbCompleteIntro

  username, password = pbMultiplayerLoginScreen

  $player.name = username if $player

  pbWait(10) if defined?(pbWait)

  server_host  =  MultiplayerConfig::SERVER_HOST
  server_port = MultiplayerConfig::SERVER_PORT

  $multiplayer_has_saved_position = false

  if pbConnectToMultiplayer(server_host, server_port, username, password)
    $multiplayer_auto_connected = true

    pbMessage("\\se[Battle ball drop]Connected to multiplayer!\\wtnp[10]") if defined?(pbMessage)

    pbWait(20) if defined?(pbWait)

    pbMessage("\\se[Door exit]Entering the world...\\wtnp[5]") if defined?(pbMessage)

    pbWait(15) if defined?(pbWait)
  else
    pbMessage('\\se[Battle buzzer]Failed to connect!\\wtnp[10]') if defined?(pbMessage)
  end
end

def pbWarpToSavedPosition

  if $multiplayer_has_saved_position && $multiplayer_saved_map && $multiplayer_saved_x && $multiplayer_saved_y
    puts "Warping to saved position: Map #{$multiplayer_saved_map} (#{$multiplayer_saved_x}, #{$multiplayer_saved_y})"

    if defined?(pbWarp)
      pbWarp($multiplayer_saved_map, $multiplayer_saved_x, $multiplayer_saved_y)
      return true
    end
  end

  return false
end

def pbCompleteIntroWithWarp

  username, password = pbMultiplayerLoginScreen

  $player.name = username if $player

  pbWait(10) if defined?(pbWait)

  server_host = MultiplayerConfig::SERVER_HOST
  server_port = MultiplayerConfig::SERVER_PORT

  $multiplayer_has_saved_position  =  false

  if pbConnectToMultiplayer(server_host, server_port, username, password)
    $multiplayer_auto_connected = true

    pbMessage("\\se[Battle ball drop]Connected to multiplayer!\\wtnp[10]") if defined?(pbMessage)

    pbWait(30) if defined?(pbWait)

    if $multiplayer_has_saved_position && $multiplayer_saved_map && $multiplayer_saved_x && $multiplayer_saved_y

      puts "Returning player! Warping to saved position..."
      pbMessage("\\se[Door exit]Welcome back!\\wtnp[5]") if defined?(pbMessage)
      pbWait(10) if defined?(pbWait)

      if defined?(pbWarp)
        pbWarp($multiplayer_saved_map, $multiplayer_saved_x, $multiplayer_saved_y)
      end
    else

      puts 'New player! Using default spawn point...'
      pbMessage("\\se[Door exit]Entering the world...\\wtnp[5]") if defined?(pbMessage)
      pbWait(10) if defined?(pbWait)
    end
  else
    pbMessage("\\se[Battle buzzer]Failed to connect!\\wtnp[10]") if defined?(pbMessage)
  end
end

def pbQuickIntroNoPassword

  if !$player || !$player.name || $player.name.empty? || $player.name == "Unnamed"
    pbTrainerName
  end

  if !$player || !$player.name || $player.name.empty? || $player.name == "Unnamed"
    $player.name = "Player#{rand(100..999)}" if $player
  end

  username = $player.name
  password = username

  pbWait(10) if defined?(pbWait)

  server_host = MultiplayerConfig::SERVER_HOST
  server_port = MultiplayerConfig::SERVER_PORT

  $multiplayer_has_saved_position = false

  if pbConnectToMultiplayer(server_host, server_port, username, password)
    $multiplayer_auto_connected = true
    pbMessage("\\se[Battle ball drop]Connected to multiplayer!\\wtnp[10]") if defined?(pbMessage)

    pbWait(30) if defined?(pbWait)

    if $multiplayer_has_saved_position && $multiplayer_saved_map && $multiplayer_saved_x && $multiplayer_saved_y

      puts "Returning player! Warping to saved position..."
      pbMessage("\\se[Door exit]Welcome back!\\wtnp[5]") if defined?(pbMessage)
      pbWait(10) if defined?(pbWait)

      if defined?(pbWarp)
        pbWarp($multiplayer_saved_map, $multiplayer_saved_x, $multiplayer_saved_y)
      end
    else

      puts 'New player! Using default spawn point...'
      pbMessage("\\se[Door exit]Entering the world...\\wtnp[5]") if defined?(pbMessage)
      pbWait(10) if defined?(pbWait)
    end
  else
    pbMessage('\\se[Battle buzzer]Failed to connect!\\wtnp[10]') if defined?(pbMessage)
  end
end
