module DebugMenuFix
  def self.hide_mmo_ui
    return unless $scene.is_a?(Scene_Map)

    $mmo_ui_hidden_for_debug = true

    if $scene.respond_to?(:mmo_ui_overlay) && $scene.mmo_ui_overlay
      $scene.mmo_ui_overlay.visible = false if $scene.mmo_ui_overlay.respond_to?(:visible=)
    end
    if $scene.respond_to?(:mmo_party_ui) && $scene.mmo_party_ui
      $scene.mmo_party_ui.visible = false if $scene.mmo_party_ui.respond_to?(:visible=)
    end
    if $scene.respond_to?(:mmo_key_items_bar) && $scene.mmo_key_items_bar
      $scene.mmo_key_items_bar.visible = false if $scene.mmo_key_items_bar.respond_to?(:visible=)
    end
  end

  def self.restore_mmo_ui
    return unless $scene.is_a?(Scene_Map)
    return unless $mmo_ui_hidden_for_debug

    $mmo_ui_hidden_for_debug  =  false

    if $scene.respond_to?(:mmo_ui_overlay) && $scene.mmo_ui_overlay
      $scene.mmo_ui_overlay.visible = true if $scene.mmo_ui_overlay.respond_to?(:visible=)
    end
    if $scene.respond_to?(:mmo_party_ui) && $scene.mmo_party_ui
      $scene.mmo_party_ui.visible = true if $scene.mmo_party_ui.respond_to?(:visible=)
    end
    if $scene.respond_to?(:mmo_key_items_bar) && $scene.mmo_key_items_bar
      $scene.mmo_key_items_bar.visible = true if $scene.mmo_key_items_bar.respond_to?(:visible=)
    end
  end
end

if defined?(pbDebugMenu)
  alias mmo_pbDebugMenu pbDebugMenu unless defined?(mmo_pbDebugMenu)

  def pbDebugMenu(show_all = true)
    puts "[MMO Debug Fix] Debug menu opening - hiding MMO UI"
    DebugMenuFix.hide_mmo_ui
    result = mmo_pbDebugMenu(show_all)
    puts '[MMO Debug Fix] Debug menu closed - restoring MMO UI'
    DebugMenuFix.restore_mmo_ui
    return result
  end

  puts "[MMO Debug Fix] Debug menu integration loaded - MMO UI will hide during debug"
else
  puts '[MMO Debug Fix] pbDebugMenu not defined - skipping integration'
end
