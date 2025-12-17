puts "[Multiplayer] Loading Following Pokemon renderer (will activate if plugin present)"

class Sprite_MultiplayerFollower < Sprite
    attr_accessor :player_event

    def initialize(viewport, player_event, follower_data)
      super(viewport)
      @player_event = player_event
      @follower_data = follower_data
      @disposed  =  false
      @charset = nil
      @current_direction  =  2
      @pattern = 0
      @anime_count = 0
      @last_real_x  =  @player_event.real_x
      @last_real_y  =  @player_event.real_y
      @send_out_animation = nil
      @send_out_timer = 0
      self.x = @player_event.screen_x
      self.y = @player_event.screen_y
      self.visible = false
      self.opacity = 0
      create_bitmap
      update
    end

    def start_send_out_animation

      @send_out_timer  =  20
      self.visible = true
      self.opacity = 0
      puts "[Following] Starting send-out animation for remote follower"
    end

    def create_bitmap
      return unless @follower_data
      species = @follower_data[:species]
      shiny = @follower_data[:shiny]
      form = @follower_data[:form] || 0

      begin
        pkmn_data = GameData::Species.get(species)

        filename = GameData::Species.ow_sprite_filename(species, form, nil, shiny)

        if filename && pbResolveBitmap(filename)

          @charset = AnimatedBitmap.new(filename)
          @char_width = @charset.width / 4
          @char_height = @charset.height / 4

          self.bitmap = Bitmap.new(@char_width, @char_height)

          update_charset_bitmap
        else

          icon_bitmap = pbLoadPokemonBitmapSpecies(species, form, shiny)
          if icon_bitmap
            self.bitmap = icon_bitmap.bitmap.clone
            icon_bitmap.dispose
          else

            self.bitmap = Bitmap.new(32, 32)
            self.bitmap.fill_rect(0, 0, 32, 32, Color.new(255, 100, 100, 128))
          end
        end
      rescue => e
        puts "[Following] Error loading follower sprite for #{species}: #{e.message}"
        self.bitmap = Bitmap.new(32, 32)
        self.bitmap.fill_rect(0, 0, 32, 32, Color.new(255, 100, 100, 128))
      end

      self.ox = self.bitmap.width / 2
      self.oy = self.bitmap.height
    end

    def update_charset_bitmap
      return unless @charset && self.bitmap

      self.bitmap.clear

      direction_row = case @current_direction
      when 2 then 0
      when 4 then 1
      when 6 then 2
      when 8 then 3
      else 0
      end

      src_x = @pattern * @char_width
      src_y = direction_row * @char_height
      src_rect = Rect.new(src_x, src_y, @char_width, @char_height)

      self.bitmap.blt(0, 0, @charset.bitmap, src_rect)
    end

    def update
      super

      if @disposed

        self.visible = false
        return
      end

      return unless @player_event

      if @send_out_timer > 0
        @send_out_timer -= 1

        self.opacity = (255 * (20 - @send_out_timer) / 20.0).to_i
        if @send_out_timer == 0
          self.opacity = 255
          puts "[Following] Send-out animation complete"
        end
      end

      is_moving = (@player_event.real_x != @last_real_x || @player_event.real_y != @last_real_y)

      if is_moving
        @last_real_x = @player_event.real_x
        @last_real_y = @player_event.real_y
      end

      if @current_direction != @player_event.direction
        @current_direction = @player_event.direction
        update_charset_bitmap if @charset
      end

      if is_moving && @charset
        @anime_count += 1.5
        if @anime_count >= 8
          @pattern = (@pattern + 1) % 4
          @anime_count = 0
          update_charset_bitmap
        end
      else

        if @pattern != 0
          @pattern = 0
          update_charset_bitmap if @charset
        end
      end

      behind_dir = 10 - @player_event.direction

      tile_offset_x = 0
      tile_offset_y = 0

      case behind_dir
      when 2
        tile_offset_y = 1
      when 4
        tile_offset_x  =  -1
      when 6
        tile_offset_x = 1
      when 8
        tile_offset_y = -1
      end

      target_x = @player_event.screen_x + (tile_offset_x * 32)
      target_y = @player_event.screen_y + (tile_offset_y * 32)

      dx = target_x - self.x
      dy = target_y - self.y
      distance = Math.sqrt(dx * dx + dy * dy)

      if distance > 0.5

        speed = is_moving ? 0.4 : 0.2
        self.x += dx * speed
        self.y += dy * speed
      end

      self.z = @player_event.screen_z - 1

      if @send_out_timer == 0
        self.visible = @player_event.character_name != '' && !@disposed
      end
    end

    def dispose
      return if @disposed

      @disposed = true

      self.visible = false
      self.opacity  =  0

      @charset.dispose if @charset && !@charset.disposed?
      self.bitmap.dispose if self.bitmap && !self.bitmap.disposed?

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
      @follower_sprites = {}
      @last_follower_species = {}
    end

    def update(player_events)

      return unless pbMultiplayerConnected?
      follower_data = pbMultiplayerClient.other_player_followers

      @follower_sprites.keys.each do |player_event|
        unless player_events && player_events.values.include?(player_event)
          dispose_follower(player_event)
        end
      end

      if player_events
        @last_follower_species.keys.each do |player_id|
          unless player_events.has_key?(player_id)
            @last_follower_species.delete(player_id)
          end
        end
      end

      follower_data ||= {}

      player_events.each do |player_id, player_event|
        next unless player_event
        follower_info = follower_data[player_id]

        if follower_info

          current_species = follower_info[:species]
          existing_sprite = @follower_sprites[player_event]

          species_changed  =  @last_follower_species[player_id] != current_species

          if existing_sprite && species_changed

            dispose_follower(player_event)
            new_sprite = Sprite_MultiplayerFollower.new(
              @viewport,
              player_event,
              follower_info
            )
            new_sprite.start_send_out_animation
            @follower_sprites[player_event] = new_sprite
            @last_follower_species[player_id] = current_species
          elsif existing_sprite

            existing_sprite.update
          else

            new_sprite = Sprite_MultiplayerFollower.new(
              @viewport,
              player_event,
              follower_info
            )
            new_sprite.start_send_out_animation
            @follower_sprites[player_event] = new_sprite
            @last_follower_species[player_id] = current_species
          end
        else

          existing_sprite = @follower_sprites[player_event]
          if existing_sprite
            dispose_follower(player_event)
            @last_follower_species.delete(player_id)
          end
        end
      end
    end

    def dispose_follower(player_event)
      sprite = @follower_sprites[player_event]
      if sprite
        puts "[Following] Disposing follower sprite (disposed? #{sprite.disposed?})"
        sprite.dispose unless sprite.disposed?
        @follower_sprites.delete(player_event)
        puts "[Following] Follower sprite removed from manager"
      end
    end

    def dispose
      @follower_sprites.values.each(&:dispose)
      @follower_sprites.clear
    end
  end

$multiplayer_follower_manager  =  nil

puts "[Multiplayer] Following Pokemon renderer loaded"
