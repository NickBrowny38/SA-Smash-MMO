class Game_RemotePlayer < Game_Character
  attr_reader :player_id
  attr_reader :username
  attr_accessor :direction

  def initialize(map, player_id, username)
    super(map)
    @player_id = player_id
    @username = username
    @character_name = "trainer_COOLTRAINER_M"
    @character_hue = 0
    @direction = 2
    @pattern = 0
    @original_pattern = 0
    @x = 0
    @y = 0
    @real_x = 0
    @real_y = 0
    @opacity = 255
    @blend_type = 0
    @target_real_x = 0
    @target_real_y = 0
    @anime_count = 0
    @step_anime = false
    @always_on_top = false
    @walk_anime = true
    @first_update = true
  end

  def name
    @username
  end

  def map_id
    return @map.map_id if @map
    return $game_map.map_id
  end

  def update_from_server_data(data)
    new_x = data[:x] || @x
    new_y = data[:y] || @y
    new_real_x = data[:real_x] || (new_x * 128)
    new_real_y = data[:real_y] || (new_y * 128)

    if @first_update || (new_x - @x).abs > 2 || (new_y - @y).abs > 2
      @x = new_x
      @y = new_y
      @real_x = new_real_x
      @real_y = new_real_y
      @target_real_x = new_real_x
      @target_real_y = new_real_y
      @first_update = false
    else
      @x = new_x
      @y = new_y
      @target_real_x = new_real_x
      @target_real_y = new_real_y
    end

    @direction = data[:direction] if data[:direction]
    @move_speed = data[:move_speed] || 3

    if data[:charset] && !data[:charset].empty?
      @character_name = data[:charset]
    end
  end

  def update
    dist_x = @target_real_x - @real_x
    dist_y = @target_real_y - @real_y

    if dist_x != 0 || dist_y != 0
      dist_sq = dist_x * dist_x + dist_y * dist_y

      if dist_sq > 65536
        # Teleport if too far
        @real_x = @target_real_x
        @real_y = @target_real_y
      else
        # Smooth easing - faster when far, slower when close
        ease = 0.25
        move_x = (dist_x * ease).round
        move_y = (dist_y * ease).round
        # Ensure minimum movement of 1 pixel when there's distance
        move_x = (dist_x > 0 ? 1 : -1) if move_x == 0 && dist_x != 0
        move_y = (dist_y > 0 ? 1 : -1) if move_y == 0 && dist_y != 0
        @real_x += move_x
        @real_y += move_y
        # Snap to target when very close
        @real_x = @target_real_x if dist_x.abs < 4
        @real_y = @target_real_y if dist_y.abs < 4
      end

      # Walk animation
      @anime_count += 1
      if @anime_count >= 12 - @move_speed
        @pattern = (@pattern + 1) % 4
        @anime_count = 0
      end
    else
      @pattern = 0
      @anime_count = 0
    end
  end

  def moving?
    @real_x != @target_real_x || @real_y != @target_real_y
  end
end

class Sprite_RemotePlayer < Sprite_Character
  attr_reader :username_sprite

  def initialize(viewport, character)
    super(viewport, character)
    @reflection = Sprite_Reflection.new(self, viewport) if !@reflection && defined?(Sprite_Reflection)
    create_username_sprite(viewport)
    @last_username_x = nil
    @last_username_y = nil
  end

  def create_username_sprite(viewport)
    @username_sprite = Sprite.new(viewport)
    @username_sprite.z = 9999

    username = @character.username
    bitmap = Bitmap.new(300, 40)

    pbSetSystemFont(bitmap)
    bitmap.font.size = 18
    bitmap.font.color = Color.new(0, 0, 0, 180)
    bitmap.draw_text(1, 11, 298, 24, username, 1)

    bitmap.font.color = Color.new(255, 255, 255, 255)
    bitmap.draw_text(0, 10, 300, 24, username, 1)

    @username_sprite.bitmap = bitmap
    @username_sprite.ox = bitmap.width / 2
    @username_sprite.oy = bitmap.height
  end

  def update
    super
    return if !@username_sprite

    if self.x != @last_username_x || self.y != @last_username_y
      @username_sprite.x = self.x
      @username_sprite.y = self.y - 45
      @username_sprite.opacity = self.opacity
      @username_sprite.visible = self.visible
      @last_username_x = self.x
      @last_username_y = self.y
    end
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
    @remote_players = {}
    @remote_sprites = {}
    @frame_counter = 0
    @cached_map_id = $game_map.map_id
    @player_ids_cache = []
    $multiplayer_current_map_id ||= @cached_map_id
  end

  def update
    return unless pbMultiplayerConnected?

    current_map_id = $game_map.map_id
    @frame_counter += 1

    if @cached_map_id != current_map_id
      clear_all_players
      @cached_map_id = current_map_id
      $multiplayer_current_map_id = current_map_id
    end

    all_remote_players = pbMultiplayerClient.remote_players
    active_ids = {}

    all_remote_players.each do |player_id, player_data|
      next unless player_data[:map_id] == current_map_id
      active_ids[player_id] = true

      player = @remote_players[player_id]
      if player
        player.update_from_server_data(player_data)
      else
        add_remote_player(player_data)
      end
    end

    @player_ids_cache = @remote_players.keys
    @player_ids_cache.each do |player_id|
      remove_remote_player(player_id) unless active_ids[player_id]
    end

    @remote_players.each_value { |p| p.update }
    @remote_sprites.each_value { |s| s.update }
  end

  def clear_all_players
    @remote_sprites.each_value do |sprite|
      next unless sprite && !sprite.disposed?
      sprite.visible = false
      sprite.dispose
    end
    @remote_sprites.clear
    @remote_players.clear
  end

  def add_remote_player(player_data)
    player_id = player_data[:id]
    return if @remote_players[player_id]

    remote_player = Game_RemotePlayer.new($game_map, player_id, player_data[:username])
    remote_player.update_from_server_data(player_data)

    remote_sprite = Sprite_RemotePlayer.new(@viewport, remote_player)
    remote_sprite.visible = true
    remote_sprite.opacity = 255

    @remote_players[player_id] = remote_player
    @remote_sprites[player_id] = remote_sprite
  end

  def remove_remote_player(player_id)
    sprite = @remote_sprites.delete(player_id)
    if sprite && !sprite.disposed?
      sprite.visible = false
      sprite.dispose
    end
    @remote_players.delete(player_id)
  end

  def dispose
    @remote_sprites.each_value { |s| s.dispose unless s.disposed? }
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
        charset: player.character_name,
        map_id: @cached_map_id
      }
      add_remote_player(player_data)
    end
  end
end
