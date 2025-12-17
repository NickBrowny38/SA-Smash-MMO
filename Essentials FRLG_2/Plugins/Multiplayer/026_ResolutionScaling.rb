module MMOResolution
  TARGET_WIDTH = 800
  TARGET_HEIGHT = 600

  UI_TOP_HEIGHT = 40
  UI_RIGHT_WIDTH  =  160
  UI_BOTTOM_HEIGHT = 0

  GAME_WIDTH = TARGET_WIDTH - UI_RIGHT_WIDTH
  GAME_HEIGHT = TARGET_HEIGHT - UI_TOP_HEIGHT - UI_BOTTOM_HEIGHT

  @enabled  =  false
  @original_screen_width = nil
  @original_screen_height = nil

  def self.enabled?
    return @enabled
  end

  def self.enable
    return if @enabled

    @enabled = true
    puts "[MMO Resolution] Enabled #{TARGET_WIDTH}x#{TARGET_HEIGHT} (Game: #{GAME_WIDTH}x#{GAME_HEIGHT})"
    puts "[MMO Resolution] Window resolution is controlled by mkxp.json"
  end

  def self.disable
    return unless @enabled

    @enabled = false
    puts "[MMO Resolution] Disabled"
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
