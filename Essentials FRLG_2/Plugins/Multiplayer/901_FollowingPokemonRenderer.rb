puts "[Multiplayer] Loading Following Pokemon renderer (will activate if plugin present)"

class Sprite_MultiplayerFollower < Sprite
    attr_accessor :player_event

    def initialize(viewport, player_event, follower_data)
      super(viewport)
      @player_event = player_event
      @follower_data = follower_data
      @disposed = false
      @charset = nil
      @current_direction = 2
      @pattern = 0
      @anime_count = 0
      @last_real_x = @player_event.real_x
      @last_real_y = @player_event.real_y
      @last_screen_x = @player_event.screen_x
      @last_screen_y = @player_event.screen_y
      @send_out_timer = 0
      @last_pattern = -1
      @last_dir_row = -1
      @follower_real_x = @player_event.screen_x.to_f
      @follower_real_y = @player_event.screen_y.to_f
      @target_x = @follower_real_x
      @target_y = @follower_real_y
      @position_history = []
      @history_size = 12
      @last_player_direction = @player_event.direction
      @direction_change_delay = 0
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

      direction_row = case @current_direction
      when 2 then 0
      when 4 then 1
      when 6 then 2
      when 8 then 3
      else 0
      end

      return if @last_pattern == @pattern && @last_dir_row == direction_row
      @last_pattern = @pattern
      @last_dir_row = direction_row

      self.bitmap.clear
      src_x = @pattern * @char_width
      src_y = direction_row * @char_height
      src_rect = Rect.new(src_x, src_y, @char_width, @char_height)
      self.bitmap.blt(0, 0, @charset.bitmap, src_rect)
    end

    def update
      return if @disposed
      return unless @player_event

      screen_x = @player_event.screen_x
      screen_y = @player_event.screen_y
      player_moving = (screen_x != @last_screen_x || screen_y != @last_screen_y)

      if player_moving
        @position_history.push({ x: screen_x.to_f, y: screen_y.to_f, dir: @player_event.direction })
        while @position_history.length > @history_size
          @position_history.shift
        end
        @last_screen_x = screen_x
        @last_screen_y = screen_y
      end

      follower_moving = (@follower_real_x - @target_x).abs > 0.5 || (@follower_real_y - @target_y).abs > 0.5

      if !player_moving && !follower_moving && @send_out_timer == 0
        return
      end

      super

      if @send_out_timer > 0
        @send_out_timer -= 1
        self.opacity = (255 * (20 - @send_out_timer) / 20.0).to_i
        self.opacity = 255 if @send_out_timer == 0
      end

      if @position_history.length >= @history_size
        old_pos = @position_history[0]
        @target_x = old_pos[:x]
        @target_y = old_pos[:y]
        if old_pos[:dir] && @current_direction != old_pos[:dir]
          @current_direction = old_pos[:dir]
          update_charset_bitmap if @charset
        end
      elsif @position_history.length > 0
        index = [0, @position_history.length - 4].max
        old_pos = @position_history[index]
        @target_x = old_pos[:x]
        @target_y = old_pos[:y]
        if old_pos[:dir] && @current_direction != old_pos[:dir]
          @current_direction = old_pos[:dir]
          update_charset_bitmap if @charset
        end
      else
        behind_dir = 10 - @player_event.direction
        tile_offset_x = 0
        tile_offset_y = 0
        case behind_dir
        when 2 then tile_offset_y = 1
        when 4 then tile_offset_x = -1
        when 6 then tile_offset_x = 1
        when 8 then tile_offset_y = -1
        end
        @target_x = screen_x + (tile_offset_x * 32)
        @target_y = screen_y + (tile_offset_y * 32)
        @current_direction = @player_event.direction
      end

      dx = @target_x - @follower_real_x
      dy = @target_y - @follower_real_y
      dist_sq = dx * dx + dy * dy

      if dist_sq > 1.0
        if dist_sq > 2500
          @follower_real_x = @target_x - dx * 0.3
          @follower_real_y = @target_y - dy * 0.3
        elsif dist_sq > 400
          speed = 0.25
          @follower_real_x += dx * speed
          @follower_real_y += dy * speed
        else
          speed = 0.18
          @follower_real_x += dx * speed
          @follower_real_y += dy * speed
        end

        if @charset
          @anime_count += 1.2
          if @anime_count >= 8
            @pattern = (@pattern + 1) % 4
            @anime_count = 0
            update_charset_bitmap
          end
        end
      else
        @follower_real_x = @target_x
        @follower_real_y = @target_y
        if @pattern != 0
          @pattern = 0
          update_charset_bitmap if @charset
        end
      end

      self.x = @follower_real_x.round
      self.y = @follower_real_y.round
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
      @player_event_ids = {}
    end

    def update(player_events)
      return unless pbMultiplayerConnected?
      return unless player_events

      follower_data = pbMultiplayerClient.other_player_followers || {}
      active_events = {}

      player_events.each do |player_id, player_event|
        next unless player_event
        active_events[player_event] = player_id
        follower_info = follower_data[player_id]

        existing_sprite = @follower_sprites[player_event]

        if follower_info
          current_species = follower_info[:species]
          species_changed = @last_follower_species[player_id] != current_species

          if existing_sprite
            if species_changed
              dispose_follower(player_event)
              create_follower_sprite(player_event, player_id, follower_info)
            else
              existing_sprite.update
            end
          else
            create_follower_sprite(player_event, player_id, follower_info)
          end
        elsif existing_sprite
          dispose_follower(player_event)
          @last_follower_species.delete(player_id)
        end
      end

      @follower_sprites.keys.each do |player_event|
        dispose_follower(player_event) unless active_events[player_event]
      end
    end

    def create_follower_sprite(player_event, player_id, follower_info)
      new_sprite = Sprite_MultiplayerFollower.new(@viewport, player_event, follower_info)
      new_sprite.start_send_out_animation
      @follower_sprites[player_event] = new_sprite
      @last_follower_species[player_id] = follower_info[:species]
    end

    def dispose_follower(player_event)
      sprite = @follower_sprites.delete(player_event)
      sprite.dispose if sprite && !sprite.disposed?
    end

    def dispose
      @follower_sprites.each_value { |s| s.dispose unless s.disposed? }
      @follower_sprites.clear
      @last_follower_species.clear
    end
  end

$multiplayer_follower_manager  =  nil

puts "[Multiplayer] Following Pokemon renderer loaded"
