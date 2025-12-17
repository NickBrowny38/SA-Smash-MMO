$multiplayer_auto_connected = false

def pbAutoConnectMultiplayer
  return unless pbIsMultiplayerMode?
  return if $multiplayer_auto_connected
  return unless $player

  server_host = MultiplayerConfig::SERVER_HOST
  server_port = MultiplayerConfig::SERVER_PORT
  username = $player.name

  if username.nil? || username.empty? || username == "Unnamed"
    puts "Cannot connect: No valid player name set (name: #{username || 'nil'})"
    return
  end

  puts '=' * 50
  puts "MULTIPLAYER AUTO-CONNECT"
  puts "=" * 50
  puts "Server: #{server_host}:#{server_port}"
  puts "Username: #{username}"
  puts "Connecting..."

  begin
    if pbConnectToMultiplayer(server_host, server_port, username)
      puts "✓ CONNECTED TO MULTIPLAYER SERVER!"
      puts "=" * 50
      $multiplayer_auto_connected = true

      pbMessage("\\se[Battle ball drop]Connected to multiplayer!\\wtnp[10]") if defined?(pbMessage)
    else
      puts "✗ Failed to connect to multiplayer server"
      puts "=" * 50

      sleep(2)
      if pbConnectToMultiplayer(server_host, server_port, username)
        puts '✓ CONNECTED ON RETRY!'
        $multiplayer_auto_connected = true
        pbMessage('\\se[Battle ball drop]Connected to multiplayer!\\wtnp[10]') if defined?(pbMessage)
      else
        puts '✗ Connection failed after retry'
      end
    end
  rescue => e
    puts "Error connecting to multiplayer: #{e.message}"
    puts e.backtrace.join("\n")
  end
end

EventHandlers.add(:on_player_change, :multiplayer_auto_connect,
  proc { |sender, *args|
    next unless pbIsMultiplayerMode?
    pbAutoConnectMultiplayer
  }
)

EventHandlers.add(:on_enter_map, :multiplayer_connect_on_map,
  proc {
    next unless pbIsMultiplayerMode?
    pbAutoConnectMultiplayer
  }
)

EventHandlers.add(:on_game_start, :multiplayer_connect_new_game,
  proc {
    next unless pbIsMultiplayerMode?

    20.times do      Graphics.update if defined?(Graphics)
      sleep(0.05)
    end
    pbAutoConnectMultiplayer
  }
)

EventHandlers.add(:on_game_load, :multiplayer_connect_on_load,
  proc {

    next unless pbIsMultiplayerMode?

    20.times do      Graphics.update if defined?(Graphics)
      sleep(0.05)
    end
    pbAutoConnectMultiplayer

    60.times do      Graphics.update if defined?(Graphics)
      sleep(0.05)
      break if $multiplayer_has_saved_position
    end

    if $multiplayer_has_saved_position && $multiplayer_saved_map && $multiplayer_saved_x && $multiplayer_saved_y
      puts "Loading saved position from server..."
      pbWarp($multiplayer_saved_map, $multiplayer_saved_x, $multiplayer_saved_y) if defined?(pbWarp)
    end
  }
)

def pbManualMultiplayerConnect
  $multiplayer_auto_connected  =  false
  pbAutoConnectMultiplayer
end
