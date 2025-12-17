puts "Loading Multiplayer Integration (005_Integration.rb) - transparent in singleplayer mode..."

class Scene_Map
  alias multiplayer_original_createSpritesets createSpritesets
  alias multiplayer_original_disposeSpritesets disposeSpritesets
  alias multiplayer_original_dispose dispose
  alias multiplayer_original_updateSpritesets updateSpritesets
  alias multiplayer_original_transfer_player transfer_player
  alias multiplayer_original_spriteset spriteset unless method_defined?(:multiplayer_original_spriteset)
  alias multiplayer_original_main main unless method_defined?(:multiplayer_original_main)

  attr_reader :remote_player_manager

  def spriteset(map_id = -1)
    return multiplayer_original_spriteset(map_id) unless pbIsMultiplayerMode?

    return nil unless @spritesets
    multiplayer_original_spriteset(map_id)
  end

  def createSpritesets

    if !pbIsMultiplayerMode?
      multiplayer_original_createSpritesets
      return
    end

    if @spritesets && !@spritesets.empty?
      puts "Spritesets already created - skipping createSpritesets to prevent duplicates"
      return
    end

    if @map_renderer && !@map_renderer.disposed?
      puts "Disposing existing map_renderer from EMERGENCY creation..."
      @map_renderer.dispose
      @map_renderer = nil
    end

    if @spritesetGlobal
      puts "Disposing existing spritesetGlobal from EMERGENCY creation..."
      @spritesetGlobal.dispose
      @spritesetGlobal = nil
    end

    if @remote_player_manager
      puts "Disposing existing remote_player_manager from EMERGENCY creation..."
      @remote_player_manager.dispose
      @remote_player_manager = nil
    end

    pbInitMultiplayerNotifications if defined?(pbInitMultiplayerNotifications)

    puts "Creating fresh spritesets via multiplayer_original_createSpritesets..."
    multiplayer_original_createSpritesets

  end

  def disposeSpritesets

    if !pbIsMultiplayerMode?
      multiplayer_original_disposeSpritesets
      return
    end

    if @remote_player_manager
      puts "[MULTIPLAYER] disposeSpritesets: Disposing remote player manager (manager will handle sprite removal)"
      @remote_player_manager.dispose
      @remote_player_manager = nil
    end

    multiplayer_original_disposeSpritesets
  end

  def dispose

    if !pbIsMultiplayerMode?
      multiplayer_original_dispose
      return
    end

    if @remote_player_manager
      puts "[MULTIPLAYER] dispose: Disposing remote player manager (manager will handle sprite removal)"
      @remote_player_manager.dispose
      @remote_player_manager = nil
    end

    multiplayer_original_dispose
  end

  def updateSpritesets(refresh = false)

    if !pbIsMultiplayerMode?
      multiplayer_original_updateSpritesets(refresh)
      return
    end

    if !@map_renderer || (@map_renderer && @map_renderer.disposed?)
      puts "EMERGENCY: Creating map_renderer in updateSpritesets..."
      @map_renderer = TilemapRenderer.new(Spriteset_Map.viewport)
      puts "map_renderer created: #{@map_renderer.class}"
    end

    if !@spritesetGlobal
      puts "EMERGENCY: Creating spritesetGlobal in updateSpritesets..."
      @spritesetGlobal = Spriteset_Global.new
      puts "spritesetGlobal created: #{@spritesetGlobal.class}"
    end

    multiplayer_original_updateSpritesets(refresh)

    if pbMultiplayerConnected? && @spritesets && @map_renderer
      if !@remote_player_manager
        @remote_player_manager  =  MultiplayerRemotePlayerManager.new($game_map, Spriteset_Map.viewport)

        if @spritesets[@map_id]
          player_sprite = @spritesets[@map_id].character_sprites.find { |s| s.character == $game_player }
          player_sprite.update if player_sprite
        end
      end
      @remote_player_manager.update
    elsif @remote_player_manager
      @remote_player_manager.dispose
      @remote_player_manager  =  nil
    end
  end

  def transfer_player(cancel_swimming = true)

    if !pbIsMultiplayerMode?
      multiplayer_original_transfer_player(cancel_swimming)
      return
    end

    if pbMultiplayerConnected?
      puts "Map transfer - saving position to server..."
      pbMultiplayerClient.send_player_data
    end

    if @remote_player_manager
      @remote_player_manager.dispose
      @remote_player_manager  =  nil
    end

    multiplayer_original_transfer_player(cancel_swimming)

  end

  def main

    if !pbIsMultiplayerMode?
      multiplayer_original_main
      return
    end

    multiplayer_original_main
  end

  alias multiplayer_original_graphics_update_check graphics_update_check if method_defined?(:graphics_update_check)

  puts '[MULTIPLAYER] miniupdate patch DISABLED FOR TESTING'

  if false && method_defined?(:miniupdate)
    alias multiplayer_original_miniupdate miniupdate
    puts '[MULTIPLAYER] Successfully aliased Scene_Map#miniupdate'

    def miniupdate

      multiplayer_original_miniupdate

      if pbIsMultiplayerMode? && $multiplayer_notifications
        $multiplayer_notifications.draw
      end
    end
  else
    puts "[MULTIPLAYER] miniupdate not patched (disabled for testing)"
  end
end

MenuHandlers.add(:pause_menu, :multiplayer_change_account, {
  "name"      => _INTL("Change Account"),
  "order"     => 100,
  'condition' => proc { next pbIsMultiplayerMode? && pbMultiplayerConnected? },
  "effect"    => proc { |menu|
    menu.pbEndScene
    pbChangeMultiplayerAccount
    menu.pbStartScene
    next false
  }
})

def pbMultiplayerMenu
  commands = []
  cmd_connect = -1
  cmd_disconnect = -1
  cmd_chat = -1
  cmd_players = -1
  cmd_cancel = -1

  if pbMultiplayerConnected?
    commands[cmd_disconnect  =  commands.length]  =  _INTL("Disconnect")
    commands[cmd_chat = commands.length] = _INTL("Chat")
    commands[cmd_players = commands.length] = _INTL("Players Online")
  else
    commands[cmd_connect = commands.length] = _INTL('Connect to Server')
  end

  commands[cmd_cancel = commands.length] = _INTL("Cancel")

  loop do    command = pbMessage(_INTL("Multiplayer Menu"), commands, -1)
    break if command == cmd_cancel || command < 0

    if command == cmd_connect
      pbMultiplayerConnectDialog
    elsif command == cmd_disconnect
      pbDisconnectFromMultiplayer
      pbMessage(_INTL("Disconnected from server."))
      break
    elsif command == cmd_chat
      pbMultiplayerChatDialog
    elsif command == cmd_players
      pbMultiplayerPlayersDialog
    end
  end
end

def pbMultiplayerConnectDialog

  server_host = '193.31.31.187'
  server_port = 5000

  username = pbEnterText(_INTL('Username:'), 0, 20, $player.name)
  return if !username || username.empty?

  pbMessage(_INTL("Connecting to server..."))

  if pbConnectToMultiplayer(server_host, server_port, username)
    pbMessage(_INTL('Connected successfully!'))
  else
    pbMessage(_INTL('Failed to connect to server.'))
  end
end

def pbMultiplayerChatDialog
  return unless pbMultiplayerConnected?

  message = pbEnterText(_INTL("Enter message:"), 0, 100)
  return if !message || message.empty?

  pbMultiplayerClient.send_chat_message(message)
end

def pbMultiplayerPlayersDialog
  return unless pbMultiplayerConnected?

  players = pbMultiplayerClient.remote_players
  if players.empty?
    pbMessage(_INTL("No other players online."))
  else
    text = _INTL("Players Online: {1}\n", players.size)
    players.each do |id, player|
      map_name = pbGetMapNameFromId(player[:map_id])
      text += _INTL("{1} - {2}\n", player[:username], map_name)
    end
    pbMessage(text)
  end
end

EventHandlers.add(:on_game_start, :multiplayer_init,
  proc {

    if pbIsMultiplayerMode?
      $multiplayer_client = MultiplayerClient.new if !$multiplayer_client
    end
  }
)

EventHandlers.add(:on_game_save, :multiplayer_disconnect,
  proc {

  }
)

EventHandlers.add(:on_game_load, :multiplayer_reinit,
  proc {

    if pbIsMultiplayerMode?
      $multiplayer_client = MultiplayerClient.new if !$multiplayer_client
    end
  }
)

if $DEBUG
  def pbQuickMultiplayerConnect(host = "localhost", port = 5000, username = nil)
    username ||= $player.name
    pbConnectToMultiplayer(host, port, username)
  end
end
