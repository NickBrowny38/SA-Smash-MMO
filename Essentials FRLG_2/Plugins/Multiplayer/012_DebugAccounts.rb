DEBUG_ACCOUNTS = [
  {username: "Player1", password: "test1"},
  {username: "Player2", password: "test2"},
  {username: "Player3", password: "test3"},
  {username: "Player4", password: "test4"},
  {username: "Player5", password: "test5"}
]

def pbDebugAccountLogin(account_index)
  begin
    account = DEBUG_ACCOUNTS[account_index]
    return false unless account

    username = account[:username]
    password = account[:password]

    Game.start_new

    $multiplayer_has_saved_position = false
    $multiplayer_auto_connected = false

    $player.name = username if $player

    server_host = "193.31.31.187"
    server_port = 5000

    puts "Debug login: #{username}"

    if pbConnectToMultiplayer(server_host, server_port, username, password)
      $multiplayer_auto_connected = true

      60.times do        Graphics.update if defined?(Graphics)
        pbMultiplayerClient.update if pbMultiplayerConnected?
        sleep(0.05)
        break if $multiplayer_has_saved_position
      end

      if $multiplayer_has_saved_position && $multiplayer_saved_map && $multiplayer_saved_x && $multiplayer_saved_y
        puts 'Returning player! Warping to saved position...'
        $game_temp.player_new_map_id = $multiplayer_saved_map
        $game_temp.player_new_x = $multiplayer_saved_x
        $game_temp.player_new_y = $multiplayer_saved_y
        $game_temp.player_new_direction = 2
      else
        puts "New player! Starting at default position..."
        $game_temp.player_new_map_id = 3
        $game_temp.player_new_x = 10
        $game_temp.player_new_y = 7
        $game_temp.player_new_direction = 2
      end

      $scene = Scene_Map.new
      return true
    else
      pbMessage(_INTL('Failed to connect to server!'))
      return false
    end
  rescue => e
    pbMessage(_INTL("Error: {1}", e.message))
    puts "Error: #{e.message}"
    return false
  end
end

MenuHandlers.add(:debug_menu, :multiplayer_debug_login, {
  "name"        => _INTL("Quick Login (Multiplayer)"),
  "parent"      => :main,
  "description" => _INTL("Quickly login with a test account"),
  'effect'      => proc {
    commands = []
    DEBUG_ACCOUNTS.each_with_index do |account, i|
      commands.push(_INTL("{1} ({2})", account[:username], i + 1))
    end
    commands.push(_INTL("Cancel"))

    choice = pbShowCommands(nil, commands, -1)

    if choice >= 0 && choice < DEBUG_ACCOUNTS.length
      pbDebugAccountLogin(choice)
    end
  }
})
