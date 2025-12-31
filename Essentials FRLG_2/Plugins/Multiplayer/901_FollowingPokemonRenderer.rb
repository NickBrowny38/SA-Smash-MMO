puts "[Multiplayer] Loading Following Pokemon renderer"

class Sprite_MultiplayerFollower < Sprite
  attr_accessor :player_event

  TILE_SIZE = 128  # World units per tile

  def initialize(viewport, player_event, follower_data)
    super(viewport)
    @player_event = player_event
    @follower_data = follower_data
    @disposed = false
    @charset = nil
    @pattern = 0
    @anime_count = 0
    @send_out_timer = 0
    @last_pattern = -1
    @last_dir_row = -1
    # Start behind player
    off = behind_offset(@player_event.direction || 2)
    @world_x = @player_event.real_x + off[0]
    @world_y = @player_event.real_y + off[1]
    @target_x = @world_x
    @target_y = @world_y
    @direction = @player_event.direction || 2
    # Track player position to detect actual movement vs just turning
    @last_player_x = @player_event.real_x
    @last_player_y = @player_event.real_y
    self.visible = false
    self.opacity = 0
    create_bitmap
  end

  def behind_offset(dir)
    case dir
    when 2 then [0, -TILE_SIZE]    # facing down -> behind is up
    when 4 then [TILE_SIZE, 0]     # facing left -> behind is right
    when 6 then [-TILE_SIZE, 0]    # facing right -> behind is left
    when 8 then [0, TILE_SIZE]     # facing up -> behind is down
    else [0, -TILE_SIZE]
    end
  end

  def start_send_out_animation
    @send_out_timer = 20
    self.visible = true
    self.opacity = 0
  end

  def create_bitmap
    return unless @follower_data
    species = @follower_data[:species]
    shiny = @follower_data[:shiny]
    form = @follower_data[:form] || 0

    begin
      filename = GameData::Species.ow_sprite_filename(species, form, nil, shiny)
      if filename && pbResolveBitmap(filename)
        @charset = AnimatedBitmap.new(filename)
        @char_width = @charset.width / 4
        @char_height = @charset.height / 4
        self.bitmap = Bitmap.new(@char_width, @char_height)
        update_sprite_frame
      else
        icon = pbLoadPokemonBitmapSpecies(species, form, shiny)
        if icon
          self.bitmap = icon.bitmap.clone
          @char_width = self.bitmap.width
          @char_height = self.bitmap.height
          icon.dispose
        else
          self.bitmap = Bitmap.new(32, 32)
          @char_width = 32
          @char_height = 32
        end
      end
    rescue
      self.bitmap = Bitmap.new(32, 32)
      @char_width = 32
      @char_height = 32
    end

    self.ox = @char_width / 2
    self.oy = @char_height
  end

  def update_sprite_frame
    return unless @charset && self.bitmap
    dir_row = case @direction
              when 2 then 0
              when 4 then 1
              when 6 then 2
              when 8 then 3
              else 0
              end
    return if @last_pattern == @pattern && @last_dir_row == dir_row
    @last_pattern = @pattern
    @last_dir_row = dir_row
    self.bitmap.clear
    src_rect = Rect.new(@pattern * @char_width, dir_row * @char_height, @char_width, @char_height)
    self.bitmap.blt(0, 0, @charset.bitmap, src_rect)
  end

  def update
    return if @disposed || !@player_event

    # Send out animation
    if @send_out_timer > 0
      @send_out_timer -= 1
      self.opacity = 255 - (@send_out_timer * 12)
      self.opacity = 255 if @send_out_timer == 0
    end

    player_dir = @player_event.direction || 2
    player_x = @player_event.real_x
    player_y = @player_event.real_y

    # Only update target position when player actually moves (not just turns)
    player_moved = (player_x != @last_player_x || player_y != @last_player_y)
    if player_moved
      off = behind_offset(player_dir)
      @target_x = player_x + off[0]
      @target_y = player_y + off[1]
      @last_player_x = player_x
      @last_player_y = player_y
    end

    dx = @target_x - @world_x
    dy = @target_y - @world_y
    dist_sq = dx * dx + dy * dy

    if dist_sq > 16
      if dist_sq > 147456  # Teleport if > 3 tiles away
        @world_x = @target_x
        @world_y = @target_y
      else
        # Smooth easing
        ease = 0.28
        move_x = (dx * ease).round
        move_y = (dy * ease).round
        move_x = (dx > 0 ? 1 : -1) if move_x == 0 && dx != 0
        move_y = (dy > 0 ? 1 : -1) if move_y == 0 && dy != 0
        @world_x += move_x
        @world_y += move_y
        @world_x = @target_x if dx.abs < 4
        @world_y = @target_y if dy.abs < 4
      end

      # Face direction of movement
      if dx.abs > dy.abs
        @direction = dx > 0 ? 6 : 4
      elsif dy != 0
        @direction = dy > 0 ? 2 : 8
      end

      # Animate
      @anime_count += 1
      if @anime_count >= 10
        @pattern = (@pattern + 1) % 4
        @anime_count = 0
        update_sprite_frame if @charset
      end
    else
      # Idle - face same direction as player
      if @pattern != 0
        @pattern = 0
        update_sprite_frame if @charset
      end
      if @direction != player_dir
        @direction = player_dir
        update_sprite_frame if @charset
      end
    end

    # Convert world coords to screen coords
    map = $game_map
    screen_y = ((@world_y - map.display_y) / Game_Map::Y_SUBPIXELS).round
    self.x = ((@world_x - map.display_x) / Game_Map::X_SUBPIXELS).round + Game_Map::TILE_WIDTH / 2
    self.y = screen_y + Game_Map::TILE_HEIGHT
    # Z-index: match Game_Character.screen_z calculation
    self.z = screen_y + (@char_height || 32) - 1
    self.visible = @send_out_timer == 0 && @player_event.character_name != ''
  end

  def dispose
    return if @disposed
    @disposed = true
    self.visible = false
    @charset&.dispose
    self.bitmap&.dispose
    @player_event = nil
    super
  end

  def disposed?
    @disposed
  end
end

class MultiplayerFollowerManager
  def initialize(viewport)
    @viewport = viewport
    @sprites = {}
    @species_cache = {}
  end

  def update(player_events)
    return unless pbMultiplayerConnected? && player_events

    follower_data = pbMultiplayerClient.other_player_followers
    return unless follower_data

    active = {}

    player_events.each do |player_id, event|
      next unless event
      active[player_id] = true
      info = follower_data[player_id]
      sprite = @sprites[player_id]

      if info
        if sprite
          if @species_cache[player_id] != info[:species]
            sprite.dispose
            @sprites[player_id] = create_sprite(event, info)
            @species_cache[player_id] = info[:species]
          else
            sprite.update
          end
        else
          @sprites[player_id] = create_sprite(event, info)
          @species_cache[player_id] = info[:species]
        end
      elsif sprite
        sprite.dispose
        @sprites.delete(player_id)
        @species_cache.delete(player_id)
      end
    end

    # Clean up sprites for players no longer present
    @sprites.keys.each do |id|
      unless active[id]
        @sprites[id].dispose
        @sprites.delete(id)
        @species_cache.delete(id)
      end
    end
  end

  def create_sprite(event, info)
    sprite = Sprite_MultiplayerFollower.new(@viewport, event, info)
    sprite.start_send_out_animation
    sprite
  end

  def dispose
    @sprites.each_value { |s| s.dispose unless s.disposed? }
    @sprites.clear
    @species_cache.clear
  end
end

$multiplayer_follower_manager = nil

puts "[Multiplayer] Following Pokemon renderer loaded"
