def pbTestMultiplayerConnection
  puts "=" * 60
  puts "MULTIPLAYER CONNECTION TEST"
  puts "=" * 60

  require 'socket' if !defined?(TCPSocket)

  server_host = "193.31.31.187"
  server_port = 5000

  puts "Testing connection to #{server_host}:#{server_port}..."

  begin
    socket = TCPSocket.new(server_host, server_port)
    puts '✓ TCP connection successful!'

    test_msg = JSON.generate({
      type: "connect",
      timestamp: Time.now.to_f,
      data: {
        username: "TestUser#{rand(1000)}",
        version: "1.0.0"
      }
    }) + "\n"

    puts "Sending test message..."
    socket.write(test_msg)

    puts "Waiting for response..."
    response = socket.gets(timeout: 5) rescue nil

    if response
      puts "✓ Received response: #{response}"
      parsed = JSON.parse(response, symbolize_names: true) rescue nil
      if parsed
        puts "✓ Response type: #{parsed[:type]}"
        puts "✓ Response data: #{parsed[:data]}"
      end
    else
      puts "✗ No response received (timeout)"
    end

    socket.close
    puts "✓ Connection test complete"
  rescue Errno::ECONNREFUSED
    puts "✗ Connection refused - server not accepting connections"
  rescue Errno::ETIMEDOUT
    puts '✗ Connection timeout - server not responding'
  rescue => e
    puts "✗ Error: #{e.class} - #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end

  puts "=" * 60
end

def pbMultiplayerStatus
  puts "=" * 60
  puts "MULTIPLAYER STATUS"
  puts "=" * 60
  puts "Connected: #{pbMultiplayerConnected? ? 'YES' : 'NO'}"
  if pbMultiplayerConnected?
    puts "Username: #{pbMultiplayerClient.username}"
    puts "Remote players: #{pbMultiplayerClient.remote_players.size}"
    pbMultiplayerClient.remote_players.each do |id, player|
      puts "  - #{player[:username]} (Map #{player[:map_id]}, Pos: #{player[:x]},#{player[:y]})"
    end
  end
  puts "Player name: #{$player ? $player.name : 'Not set'}"
  puts "Auto-connected flag: #{$multiplayer_auto_connected}"
  puts "=" * 60
end

def pbForceReconnect
  puts "Forcing reconnect..."
  pbDisconnectFromMultiplayer if pbMultiplayerConnected?
  $multiplayer_auto_connected  =  false
  pbAutoConnectMultiplayer
end

def pbTestPositionUpdate
  return unless pbMultiplayerConnected?

  puts "Sending test position update..."
  pbMultiplayerClient.send_position_update
  puts "Position update sent!"
end

if $DEBUG
  puts "Multiplayer debug commands available:"
  puts '  pbTestMultiplayerConnection - Test server connection'
  puts "  pbMultiplayerStatus - Show connection status"
  puts '  pbForceReconnect - Force reconnect to server'
  puts '  pbTestPositionUpdate - Send position update'
  puts "  pbManualMultiplayerConnect - Manually trigger auto-connect"
end
