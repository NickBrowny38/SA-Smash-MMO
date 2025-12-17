class Scene_Map
  alias mmo_fix_update_mmo_ui update_mmo_ui unless method_defined?(:mmo_fix_update_mmo_ui)

  def update_mmo_ui
    if @mmo_ui_transitioning || @disposed
      return
    end

    mmo_fix_update_mmo_ui
  end

  alias mmo_fix_dispose_mmo_ui dispose_mmo_ui unless method_defined?(:mmo_fix_dispose_mmo_ui)

  def dispose_mmo_ui
    @mmo_ui_transitioning = true
    mmo_fix_dispose_mmo_ui
    @mmo_ui_transitioning  =  false
  end

  alias mmo_fix_toggle_mmo_ui toggle_mmo_ui unless method_defined?(:mmo_fix_toggle_mmo_ui)

  def toggle_mmo_ui

    current_time = System.uptime
    @mmo_last_toggle_time ||= 0

    if current_time - @mmo_last_toggle_time < 0.3
      puts "[MMO UI] Toggle blocked - too soon after last toggle"
      return
    end

    @mmo_last_toggle_time = current_time
    mmo_fix_toggle_mmo_ui
  end
end

puts "[MMO UI Fixes] Stability fixes loaded - prevents random hiding and toggle spam"
