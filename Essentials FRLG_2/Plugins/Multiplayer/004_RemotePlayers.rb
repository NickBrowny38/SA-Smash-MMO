class Game_RemotePlayer < Game_Character
  attr_reader :player_id
  attr_reader :username

  def initialize(map, player_id, username)
    super(map)
    @player_id  =  player_id
    @username = username
    @character_name = "trainer_COOLTRAINER_M"
    @character_hue = 0
    @direction = 2
    @pattern = 0
    @original_pattern = 0
    @x = 0
    @y = 0
    @real_x  =  0
    @real_y = 0
    @opacity = 255
    @blend_type = 0
    @target_real_x = 0
    @target_real_y = 0
    @anime_count = 0
    @step_anime  =  false
    @always_on_top = false
    @walk_anime  =  true
    @first_update = true
    @last_update_time = nil
    @delta_t = 0
    @moved_last_frame = false
    @moved_this_frame = false
  end

  def name
    @username
  end

  def map_id
    return @map.map_id if @map
    return $game_map.map_id
  end

  def update_from_server_data(data)

    target_x = data[:x] || @x
    target_y = data[:y] || @y

    target_real_x = data[:real_x] || (target_x * 128)
    target_real_y = data[:real_y] || (target_y * 128)

    if @first_update

      @x  =  target_x
      @y = target_y
      @real_x = target_real_x
      @real_y = target_real_y
      @target_real_x = target_real_x
      @target_real_y = target_real_y
      @pattern = @original_pattern
      @anime_count = 0
      @first_update = false
    elsif (target_x - @x).abs > 2 || (target_y - @y).abs > 2

      @x = target_x
      @y  =  target_y
      @real_x = target_real_x
      @real_y  =  target_real_y
      @target_real_x  =  target_real_x
      @target_real_y = target_real_y
      @pattern  =  @original_pattern
      @anime_count = 0
    else

      @x = target_x
      @y = target_y
      @target_real_x = target_real_x
      @target_real_y = target_real_y

      if (@real_x != @target_real_x || @real_y != @target_real_y) && !@moved_this_frame
        @anime_count = 0
      end
    end

    @direction = data[:direction] if data[:direction]
    @move_speed = data[:move_speed] || 3

    if data[:charset] && !data[:charset].empty?

      begin
        test_path = "Graphics/Characters/#{data[:charset]}"
        if FileTest.exist?(test_path + ".png") || FileTest.exist?(test_path)
          @character_name = data[:charset]
        else
          puts "[MULTIPLAYER] Ignoring invalid charset: #{data[:charset]} - file not found"
        end
      rescue => e
        puts "[MULTIPLAYER] Error validating charset: #{e.message}"
      end
    end
  end

  def update

    time_now  =  System.uptime
    @last_update_time = time_now if !@last_update_time || @last_update_time > time_now
    @delta_t = time_now - @last_update_time
    @last_update_time = time_now
    return if @delta_t > 0.25

    @moved_last_frame = @moved_this_frame
    @moved_this_frame = false

    if @real_x != @target_real_x || @real_y != @target_real_y

      dist_x = @target_real_x - @real_x
      dist_y = @target_real_y - @real_y
      distance  =  Math.sqrt(dist_x * dist_x + dist_y * dist_y)

      if distance > 128
        speed = 0.3
      elsif distance > 64
        speed = 0.25
      else
        speed = 0.20
      end

      if dist_x.abs > 2
        move_x = (dist_x * speed).round
        move_x = 1 if move_x.abs < 1 && dist_x.abs > 0
        @real_x += move_x
      else
        @real_x = @target_real_x
      end

      if dist_y.abs > 2
        move_y = (dist_y * speed).round
        move_y = 1 if move_y.abs < 1 && dist_y.abs > 0
        @real_y += move_y
      else
        @real_y = @target_real_y
      end

      @moved_this_frame = true

      @anime_count += @delta_t if @walk_anime || @step_anime
    end

    update_pattern
  end

  def moving?
    return @real_x != @target_real_x || @real_y != @target_real_y
  end
end

class Sprite_RemotePlayer < Sprite_Character
  attr_reader :username_sprite

  def initialize(viewport, character)
    super(viewport, character)

    if !@reflection
      @reflection = Sprite_Reflection.new(self, viewport) if defined?(Sprite_Reflection)
    end

    create_username_sprite(viewport)
  end

  def create_username_sprite(viewport)
    @username_sprite = Sprite.new(viewport)
    @username_sprite.z = 9999

    username = @character.username
    bitmap  =  Bitmap.new(300, 40)

    pbSetSystemFont(bitmap)
    bitmap.font.size = 18
    text_width = bitmap.text_size(username).width
    bitmap.font.color = Color.new(0, 0, 0, 180)
    bitmap.draw_text(1, 11, 298, 24, username, 1)

    bitmap.font.color  =  Color.new(255, 255, 255, 255)
    bitmap.draw_text(0, 10, 300, 24, username, 1)

    @username_sprite.bitmap  =  bitmap
    @username_sprite.ox = bitmap.width / 2
    @username_sprite.oy = bitmap.height
  end

  def update
    super
    update_username_position
  end

  def update_username_position
    return unless @username_sprite

    @username_sprite.x = self.x
    @username_sprite.y  =  self.y - 45
    @username_sprite.opacity = self.opacity
    @username_sprite.visible = self.visible
  end

  def dispose

    if @username_sprite && !@username_sprite.disposed?
      if @username_sprite.bitmap && !@username_sprite.bitmap.disposed?
        @username_sprite.bitmap.dispose
      end
      @username_sprite.dispose
    end

    super
  end
end

class MultiplayerRemotePlayerManager
  def initialize(map, viewport)
    @map = map
    @viewport = viewport
    @remote_players  =  {}
    @remote_sprites = {}
    @update_skip_frames = 0

    $multiplayer_current_map_id ||= $game_map.map_id
  end

  def update
    return unless pbMultiplayerConnected?

    current_map_id = $game_map.map_id

    if $multiplayer_current_map_id != current_map_id
      puts "[MULTIPLAYER] Map changed from #{$multiplayer_current_map_id} to #{current_map_id} - clearing all sprites"

      @remote_sprites.each do |player_id, sprite|
        if sprite && !sprite.disposed?
          sprite.visible = false
          sprite.opacity  =  0
          sprite.username_sprite.visible = false if sprite.username_sprite
          sprite.username_sprite.opacity = 0 if sprite.username_sprite
          sprite.dispose
        end
      end
      @remote_sprites.clear
      @remote_players.clear
      $multiplayer_current_map_id = current_map_id

      Graphics.update

    end

    all_remote_players = pbMultiplayerClient.remote_players

    @remote_players.keys.dup.each do |player_id|
      player_data = all_remote_players[player_id]

      if !player_data
        puts "[MULTIPLAYER] Removing player #{player_id} - left server"
        remove_remote_player(player_id)
        Graphics.update
      elsif player_data[:map_id] != current_map_id
        puts "[MULTIPLAYER] Removing player #{@remote_players[player_id].username} (#{player_id}) - on map #{player_data[:map_id]}, we're on #{current_map_id}"
        remove_remote_player(player_id)
        Graphics.update
      end
    end

    server_players = pbMultiplayerClient.get_remote_players_on_map(current_map_id)

    server_players.each do |player_data|
      player_id = player_data[:id]
      player_map_id = player_data[:map_id]

      if player_map_id != current_map_id
        puts "[MULTIPLAYER] Skipping player #{player_data[:username]} - server says map #{player_map_id} but we're on #{current_map_id}"

        remove_remote_player(player_id) if @remote_players[player_id]
        next
      end

      if @remote_players[player_id]

        @remote_players[player_id].update_from_server_data(player_data)
      else

        puts "[MULTIPLAYER] Adding player #{player_data[:username]} (#{player_id}) to map #{current_map_id}"
        add_remote_player(player_data)
      end
    end

    @remote_players.values.each(&:update)

    @remote_sprites.values.each(&:update)

    fresh_player_data = pbMultiplayerClient.remote_players
    @remote_sprites.keys.dup.each do |player_id|
      player_data  =  fresh_player_data[player_id]

      if !player_data
        puts "[MULTIPLAYER] FINAL VALIDATION: Removing sprite #{player_id} - player no longer exists"
        remove_remote_player(player_id)
        Graphics.update
      elsif player_data[:map_id] != current_map_id
        puts "[MULTIPLAYER] FINAL VALIDATION: Removing sprite #{player_id} - on map #{player_data[:map_id]}, we're on #{current_map_id}"
        remove_remote_player(player_id)
        Graphics.update
      end
    end
  end

  def add_remote_player(player_data)
    player_id = player_data[:id]
    username = player_data[:username]
    player_map_id  =  player_data[:map_id]
    current_map_id = $game_map.map_id

    if player_map_id != current_map_id
      puts "[MULTIPLAYER] REJECTED adding player #{username} (#{player_id}) - they're on map #{player_map_id}, we're on #{current_map_id}"
      return
    end

    remote_player  =  Game_RemotePlayer.new($game_map, player_id, username)
    remote_player.update_from_server_data(player_data)

    remote_sprite = Sprite_RemotePlayer.new(@viewport, remote_player)

    remote_sprite.visible = true
    remote_sprite.opacity = 255

    remote_sprite.update

    @remote_players[player_id] = remote_player
    @remote_sprites[player_id] = remote_sprite

    puts "[DEBUG] Created sprite for #{username}: visible=#{remote_sprite.visible}, opacity=#{remote_sprite.opacity}, char=#{remote_player.character_name}, map=#{player_map_id}"
  end

  def remove_remote_player(player_id)
    if @remote_sprites[player_id]
      sprite = @remote_sprites[player_id]

      sprite.visible = false
      sprite.opacity = 0
      sprite.username_sprite.visible = false if sprite.username_sprite

      sprite.dispose
      @remote_sprites.delete(player_id)
    end

    if @remote_players[player_id]
      @remote_players.delete(player_id)
    end
  end

  def dispose

    @remote_sprites.values.each(&:dispose)
    @remote_sprites.clear
    @remote_players.clear
  end

  def refresh

    old_players = @remote_players.dup
    dispose

    old_players.each do |player_id, player|
      player_data = {
        id: player_id,
        username: player.username,
        x: player.x,
        y: player.y,
        real_x: player.real_x,
        real_y: player.real_y,
        direction: player.direction,
        pattern: player.pattern,
        move_speed: player.move_speed,
        charset: player.character_name
      }
      add_remote_player(player_data)
    end
  end
end
