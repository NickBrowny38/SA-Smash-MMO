module MultiplayerProtocol
  VERSION  =  defined?(MultiplayerVersion) ? MultiplayerVersion::VERSION : "1.2.0"

  GAME_ID = "essentials_frlg_v1.0"

  module MessageType
    CONNECT           = "connect"
    DISCONNECT        = "disconnect"
    POSITION_UPDATE   = "position_update"
    PLAYER_LIST       = "player_list"
    PLAYER_JOINED     = "player_joined"
    PLAYER_LEFT       = "player_left"
    CHAT_MESSAGE       =  'chat_message'
    HEARTBEAT         = 'heartbeat'
    ERROR             = "error"
  end

  def self.create_message(type, data = {})
    {
      type: type,
      timestamp: Time.now.to_f,
      data: data
    }
  end

  def self.serialize(message)
    JSON.generate(message) + "\n"
  end

  def self.deserialize(json_string)
    JSON.parse(json_string, symbolize_names: true)
  rescue JSON::ParserError => e
    puts "Failed to parse message: #{e.message}"
    nil
  end

  def self.connect_message(username, password = nil)
    create_message(MessageType::CONNECT, {
      username: username,
      password: password,
      version: VERSION,
      game_id: GAME_ID
    })
  end

  def self.position_update_message(player_data)
    msg_data = {
      map_id: player_data[:map_id],
      x: player_data[:x],
      y: player_data[:y],
      real_x: player_data[:real_x],
      real_y: player_data[:real_y],
      direction: player_data[:direction],
      pattern: player_data[:pattern],
      move_speed: player_data[:move_speed],
      movement_type: player_data[:movement_type],
      charset: player_data[:charset],
      follower: player_data[:follower]
    }
    # Include money and badge_count if present (for real-time sync)
    msg_data[:money] = player_data[:money] if player_data[:money]
    msg_data[:badge_count] = player_data[:badge_count] if player_data[:badge_count]
    create_message(MessageType::POSITION_UPDATE, msg_data)
  end

  def self.player_data_from_game_player(player, game_player)
    {
      map_id: game_player.map.map_id,
      x: game_player.x,
      y: game_player.y,
      real_x: game_player.real_x,
      real_y: game_player.real_y,
      direction: game_player.direction,
      pattern: game_player.pattern,
      move_speed: game_player.move_speed,
      movement_type: game_player.move_speed_real,
      charset: game_player.character_name
    }
  end
end
