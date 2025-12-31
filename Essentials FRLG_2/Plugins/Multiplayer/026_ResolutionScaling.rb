module MMOResolution
  TARGET_WIDTH = 800
  TARGET_HEIGHT = 600

  UI_TOP_HEIGHT = 40
  UI_RIGHT_WIDTH = 160
  UI_BOTTOM_HEIGHT = 0

  GAME_WIDTH = TARGET_WIDTH - UI_RIGHT_WIDTH
  GAME_HEIGHT = TARGET_HEIGHT - UI_TOP_HEIGHT - UI_BOTTOM_HEIGHT

  @enabled = false
  @cached_scale = nil
  @scale_check_time = 0

  def self.enabled?
    return @enabled
  end

  def self.enable
    return if @enabled
    @enabled = true
    @cached_scale = nil
    puts "[MMO Resolution] Enabled #{TARGET_WIDTH}x#{TARGET_HEIGHT} (Game: #{GAME_WIDTH}x#{GAME_HEIGHT})"
  end

  def self.disable
    return unless @enabled
    @enabled = false
    @cached_scale = nil
    puts "[MMO Resolution] Disabled"
  end

  def self.window_scale
    now = System.uptime rescue Time.now.to_f
    if @cached_scale.nil? || (now - @scale_check_time) > 0.5
      @cached_scale = calculate_window_scale
      @scale_check_time = now
    end
    @cached_scale
  end

  def self.calculate_window_scale
    game_width = Graphics.width rescue TARGET_WIDTH
    game_height = Graphics.height rescue TARGET_HEIGHT

    begin
      if defined?(Win32API)
        get_client_rect = Win32API.new('user32', 'GetClientRect', 'lp', 'i')
        get_active_window = Win32API.new('user32', 'GetActiveWindow', '', 'l')
        hwnd = get_active_window.call
        return 1.0 if hwnd == 0
        rect = [0, 0, 0, 0].pack('l4')
        get_client_rect.call(hwnd, rect)
        left, top, right, bottom = rect.unpack('l4')
        window_width = right - left
        window_height = bottom - top
        return 1.0 if window_width <= 0 || window_height <= 0
        scale_x = window_width.to_f / game_width
        scale_y = window_height.to_f / game_height
        return [scale_x, scale_y].min
      end
    rescue => e
      puts "[MMO Resolution] Scale detection error: #{e.message}"
    end
    1.0
  end

  def self.scale_mouse_position(raw_x, raw_y)
    if defined?(Input) && Input.respond_to?(:mouse_x)
      return [Input.mouse_x, Input.mouse_y]
    end
    scale = window_scale
    scale = 1.0 if scale <= 0
    return [(raw_x / scale).to_i, (raw_y / scale).to_i]
  end

  def self.get_mouse_position
    if defined?(Input) && Input.respond_to?(:mouse_x)
      return [Input.mouse_x, Input.mouse_y]
    end
    if defined?(MouseInput)
      raw_x, raw_y = MouseInput.mouse_x, MouseInput.mouse_y
      return scale_mouse_position(raw_x, raw_y)
    end
    [0, 0]
  end

  def self.game_viewport_rect
    return Rect.new(0, UI_TOP_HEIGHT, GAME_WIDTH, GAME_HEIGHT)
  end

  def self.party_ui_rect
    return Rect.new(GAME_WIDTH, UI_TOP_HEIGHT, UI_RIGHT_WIDTH, GAME_HEIGHT)
  end

  def self.key_items_bar_rect
    return Rect.new(0, 0, TARGET_WIDTH, UI_TOP_HEIGHT)
  end
end

EventHandlers.add(:on_game_map_setup, :mmo_resolution,
  proc { |map_id|

    if defined?($multiplayer_client) && $multiplayer_client && $multiplayer_client.connected?
      MMOResolution.enable unless MMOResolution.enabled?
    end
  }
)

EventHandlers.add(:on_title_screen_start, :mmo_resolution_disable,
  proc {
    MMOResolution.disable if MMOResolution.enabled?
  }
)

puts "[MMO Resolution] Scaling system loaded - #{MMOResolution::TARGET_WIDTH}x#{MMOResolution::TARGET_HEIGHT}"
