class Scene_Map
  alias robust_toggle_mmo_ui toggle_mmo_ui if method_defined?(:toggle_mmo_ui)

  def toggle_mmo_ui
    unless pbIsMultiplayerMode?
      puts "[MMO UI] Not in multiplayer mode - toggle ignored"
      return
    end

    current_time  =  System.uptime
    @mmo_last_toggle_time ||= 0

    if current_time - @mmo_last_toggle_time < 0.3
      puts '[MMO UI] Toggle blocked - too soon after last toggle'
      return
    end

    @mmo_last_toggle_time = current_time

    if defined?($mmo_ui_hidden_for_debug) && $mmo_ui_hidden_for_debug
      puts "[MMO UI] Toggle blocked - UI hidden for debug menu"
      pbMultiplayerNotify("Cannot toggle while debug menu is active", 2.0) if defined?(pbMultiplayerNotify)
      return
    end

    if !@mmo_ui_overlay || !@mmo_party_ui || !@mmo_key_items_bar
      puts "[MMO UI] UI components missing - reinitializing"
      initialize_mmo_ui if respond_to?(:initialize_mmo_ui)

      if !@mmo_ui_overlay || !@mmo_party_ui || !@mmo_key_items_bar
        puts "[MMO UI] Failed to initialize UI components"
        pbMultiplayerNotify('MMO UI unavailable', 2.0) if defined?(pbMultiplayerNotify)
        return
      end
    end

    @mmo_ui_visible = !@mmo_ui_visible
    puts "[MMO UI] Toggling UI to: #{@mmo_ui_visible ? 'VISIBLE' : 'HIDDEN'}"

    begin
      @mmo_ui_overlay.visible = @mmo_ui_visible if @mmo_ui_overlay
      @mmo_party_ui.visible = @mmo_ui_visible if @mmo_party_ui
      @mmo_key_items_bar.visible = @mmo_ui_visible if @mmo_key_items_bar

      puts '[MMO UI] Visibility applied successfully'
    rescue => e
      puts "[MMO UI] Error setting visibility: #{e.message}"
      puts e.backtrace[0..5].join('\n')
    end

    status  =  @mmo_ui_visible ? "shown" : "hidden"
    pbMultiplayerNotify("MMO UI #{status}", 2.0) if defined?(pbMultiplayerNotify)

    if @mmo_ui_visible
      refresh_mmo_party_ui if respond_to?(:refresh_mmo_party_ui)
      refresh_mmo_key_items if respond_to?(:refresh_mmo_key_items)
    end
  end

  alias robust_update_mmo_ui update_mmo_ui if method_defined?(:update_mmo_ui)

  def update_mmo_ui

    return if @disposed || @mmo_ui_transitioning

    if pbIsMultiplayerMode?

      @mmo_ui_visible = true if @mmo_ui_visible.nil?

      if !@mmo_ui_overlay || !@mmo_party_ui || !@mmo_key_items_bar
        puts "[MMO UI] CRITICAL: UI components disappeared - attempting recovery"
        initialize_mmo_ui if respond_to?(:initialize_mmo_ui)
      end

      if @mmo_ui_overlay && @mmo_ui_overlay.respond_to?(:disposed?) && @mmo_ui_overlay.disposed?
        puts "[MMO UI] CRITICAL: UI overlay was disposed - recreating"
        initialize_mmo_ui if respond_to?(:initialize_mmo_ui)
      end

      if @mmo_ui_visible

        if @mmo_ui_overlay && @mmo_ui_overlay.respond_to?(:visible)
          unless @mmo_ui_overlay.visible
            puts '[MMO UI] ALERT: Overlay hidden when it should be visible! Restoring...'
            @mmo_ui_overlay.visible = true
          end
        end

        if @mmo_party_ui && @mmo_party_ui.respond_to?(:visible)
          unless @mmo_party_ui.visible
            puts "[MMO UI] ALERT: Party UI hidden when it should be visible! Restoring..."
            @mmo_party_ui.visible = true
          end
        end

        if @mmo_key_items_bar && @mmo_key_items_bar.respond_to?(:visible)
          unless @mmo_key_items_bar.visible
            puts "[MMO UI] ALERT: Key items bar hidden when it should be visible! Restoring..."
            @mmo_key_items_bar.visible  =  true
          end
        end
      end
    end

    robust_update_mmo_ui if defined?(robust_update_mmo_ui)
  end

  def restore_mmo_ui_after_battle
    puts "[MMO UI] Restoring UI after battle"

    if !@mmo_ui_overlay || !@mmo_party_ui || !@mmo_key_items_bar
      puts "[MMO UI] Components missing - reinitializing"
      initialize_mmo_ui if respond_to?(:initialize_mmo_ui)
    end

    if @mmo_ui_visible
      @mmo_ui_overlay.visible = true if @mmo_ui_overlay
      @mmo_party_ui.visible = true if @mmo_party_ui
      @mmo_key_items_bar.visible = true if @mmo_key_items_bar
      puts "[MMO UI] Forced visibility ON after battle"
    end

    refresh_mmo_party_ui if respond_to?(:refresh_mmo_party_ui)
    refresh_mmo_key_items if respond_to?(:refresh_mmo_key_items)
  end
end

class MMOUIOverlay
  alias robust_update update if method_defined?(:update)

  def update

    robust_update if defined?(robust_update)

    begin
      if defined?(MMOBattleOverlay) && MMOBattleOverlay.in_mmo_battle?

        if @visible && @sprites
          @sprites.each do |key, sprite|
            if sprite && !sprite.disposed? && sprite.respond_to?(:visible)
              sprite.visible = true unless sprite.visible
            end
          end
        end
      end
    rescue

    end
  end
end

puts '[MMO UI Robust Fix] Enhanced toggle and anti-hiding system loaded'
