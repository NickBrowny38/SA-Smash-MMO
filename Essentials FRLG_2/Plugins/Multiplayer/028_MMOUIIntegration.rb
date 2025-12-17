class Scene_Map
  attr_accessor :mmo_ui_overlay
  attr_accessor :mmo_party_ui
  attr_accessor :mmo_key_items_bar

  def initialize_mmo_ui
    return if @mmo_ui_initialized

    puts '[MMO UI] Initializing MMO UI overlay...'

    @mmo_ui_overlay = MMOUIOverlay.new
    @mmo_party_ui = MMOPartyUI.new
    @mmo_key_items_bar = MMOKeyItemsBar.new

    # Expose as global variables for auto-updater and other systems
    $mmo_ui_overlay = @mmo_ui_overlay
    $mmo_party_ui = @mmo_party_ui
    $mmo_key_items_bar = @mmo_key_items_bar

    @mmo_party_ui.refresh_party if @mmo_party_ui
    @mmo_key_items_bar.refresh_items if @mmo_key_items_bar

    @mmo_ui_initialized = true
    @mmo_ui_visible = true

    setup_mmo_mouse_input

    puts "[MMO UI] MMO UI overlay initialized successfully"
  end

  def setup_mmo_mouse_input

    @mmo_last_mouse_state = [false, false, false]
  end

  def dispose_mmo_ui

    @mmo_ui_overlay.dispose if @mmo_ui_overlay && !@mmo_ui_overlay.disposed?
    @mmo_party_ui.dispose if @mmo_party_ui && !@mmo_party_ui.disposed?
    @mmo_key_items_bar.dispose if @mmo_key_items_bar && !@mmo_key_items_bar.disposed?

    @mmo_ui_initialized = false
  end

  def update_mmo_ui

    if @mmo_ui_initialized && @mmo_ui_visible
      @mmo_ui_overlay.update if @mmo_ui_overlay
      @mmo_party_ui.update if @mmo_party_ui
      @mmo_key_items_bar.update if @mmo_key_items_bar

      update_mmo_mouse_input

      @mmo_party_refresh_timer ||= 0
      @mmo_party_refresh_timer += 1
      if @mmo_party_refresh_timer >= 60
        @mmo_party_ui.refresh_party if @mmo_party_ui
        @mmo_party_refresh_timer  =  0
      end
    end

    if Input.triggerex?(0x74)
      toggle_mmo_ui
    end
  end

  def update_mmo_mouse_input
    return unless defined?(MouseInput)

    mouse_x = MouseInput.mouse_x
    mouse_y = MouseInput.mouse_y
    left_click = MouseInput.left_click?
    right_click = MouseInput.right_click?

    if left_click && !@mmo_last_mouse_state[0]
      handle_mmo_mouse_click(mouse_x, mouse_y, 1)
    end

    if right_click && !@mmo_last_mouse_state[1]
      handle_mmo_mouse_click(mouse_x, mouse_y, 2)
    end

    @mmo_last_mouse_state = [left_click, right_click, false]
  end

  def handle_mmo_mouse_click(x, y, button)

    if @mmo_party_ui && @mmo_party_ui.handle_mouse_click(x, y, button)
      return
    end

    if @mmo_key_items_bar && @mmo_key_items_bar.handle_mouse_click(x, y, button)
      return
    end

  end

  def toggle_mmo_ui

    if defined?($mmo_ui_hidden_for_debug) && $mmo_ui_hidden_for_debug
      puts "[MMO UI] Toggle blocked - UI hidden for debug menu"
      pbMultiplayerNotify("Cannot toggle while debug menu is active", 2.0) if defined?(pbMultiplayerNotify)
      return
    end

    @mmo_ui_visible  =  !@mmo_ui_visible
    puts "[MMO UI] Toggling UI to: #{@mmo_ui_visible ? 'visible' : 'hidden'}"

    if @mmo_ui_overlay && @mmo_ui_overlay.respond_to?(:visible=)
      @mmo_ui_overlay.visible = @mmo_ui_visible
      puts "[MMO UI] Set overlay visible=#{@mmo_ui_visible}"
    end
    if @mmo_party_ui && @mmo_party_ui.respond_to?(:visible=)
      @mmo_party_ui.visible  =  @mmo_ui_visible
      puts "[MMO UI] Set party_ui visible=#{@mmo_ui_visible}"
    end
    if @mmo_key_items_bar && @mmo_key_items_bar.respond_to?(:visible=)
      @mmo_key_items_bar.visible = @mmo_ui_visible
      puts "[MMO UI] Set key_items_bar visible=#{@mmo_ui_visible}"
    end

    status = @mmo_ui_visible ? "shown" : "hidden"
    pbMultiplayerNotify("MMO UI #{status}", 2.0) if defined?(pbMultiplayerNotify)
  end

  def refresh_mmo_party_ui
    @mmo_party_ui.refresh_party if @mmo_party_ui
  end

  def refresh_mmo_key_items
    @mmo_key_items_bar.refresh_items if @mmo_key_items_bar
  end
end

module MouseInput
  @left_was_down = false
  @right_was_down = false

  class << self
    def left_click?
      current = left_down?
      result = current && !@left_was_down
      @left_was_down = current
      return result
    end

    def right_click?
      current  =  right_down?
      result = current && !@right_was_down
      @right_was_down = current
      return result
    end

    def left_down?

      return GetAsyncKeyState.call(0x01) & 0x8000 != 0 if defined?(GetAsyncKeyState)
      return false
    end

    def right_down?

      return GetAsyncKeyState.call(0x02) & 0x8000 != 0 if defined?(GetAsyncKeyState)
      return false
    end
  end
end

EventHandlers.add(:on_enter_map, :mmo_ui_init,
  proc {

    if $scene.is_a?(Scene_Map) &&
       defined?($multiplayer_client) &&
       $multiplayer_client &&
       $multiplayer_client.connected? &&
       $scene.respond_to?(:initialize_mmo_ui)
      $scene.initialize_mmo_ui
    end
  }
)

EventHandlers.add(:on_frame_update, :mmo_ui_update,
  proc {
    if $scene.is_a?(Scene_Map) && $scene.respond_to?(:update_mmo_ui)
      $scene.update_mmo_ui
    end
  }
)

EventHandlers.add(:on_leave_map, :mmo_ui_dispose,
  proc {
    if $scene.is_a?(Scene_Map) && $scene.respond_to?(:dispose_mmo_ui)
      $scene.dispose_mmo_ui
    end
  }
)

EventHandlers.add(:on_party_changed, :refresh_mmo_party_ui,
  proc {
    if $scene.is_a?(Scene_Map) && $scene.respond_to?(:refresh_mmo_party_ui)
      $scene.refresh_mmo_party_ui
    end
  }
)

puts "[MMO UI Integration] MMO UI integration loaded - Press F5 to toggle UI"
