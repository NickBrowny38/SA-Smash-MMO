MenuHandlers.add(:pause_menu, :quit_game, {
  "name"      => _INTL("Quit Game"),
  "order"     => 90,
  'effect'    => proc { |menu|
    menu.pbHideMenu
    if pbConfirmMessage(_INTL("Are you sure you want to quit the game?"))
      if pbIsMultiplayerMode?
        puts 'Quitting multiplayer mode (no local save)...'
        menu.pbEndScene

        # === CLEANUP MMO UI BEFORE QUITTING ===
        puts "[MMO Quit] Cleaning up MMO UI and map scene..."

        # Helper to forcefully hide and dispose a sprite
        hide_and_dispose = proc do |sprite|
          next unless sprite && sprite.respond_to?(:disposed?) && !sprite.disposed?
          sprite.visible = false if sprite.respond_to?(:visible=)
          sprite.opacity = 0 if sprite.respond_to?(:opacity=)
          sprite.bitmap.dispose if sprite.respond_to?(:bitmap) && sprite.bitmap && !sprite.bitmap.disposed?
          sprite.dispose
        end

        # Dispose MMO UI overlay
        if defined?($mmo_ui_overlay) && $mmo_ui_overlay
          puts "[MMO Quit] Disposing overlay..."
          if $mmo_ui_overlay.respond_to?(:sprites)
            $mmo_ui_overlay.sprites.each_value { |s| hide_and_dispose.call(s) }
          end
          if $mmo_ui_overlay.respond_to?(:viewport) && $mmo_ui_overlay.viewport
            $mmo_ui_overlay.viewport.dispose rescue nil
          end
          $mmo_ui_overlay.dispose rescue nil
          $mmo_ui_overlay = nil
        end

        # Dispose MMO party UI
        if defined?($mmo_party_ui) && $mmo_party_ui
          puts "[MMO Quit] Disposing party UI..."
          if $mmo_party_ui.respond_to?(:sprites)
            $mmo_party_ui.sprites.each_value { |s| hide_and_dispose.call(s) }
          end
          $mmo_party_ui.dispose rescue nil
          $mmo_party_ui = nil
        end

        # Dispose MMO key items bar
        if defined?($mmo_key_items_bar) && $mmo_key_items_bar
          puts "[MMO Quit] Disposing key items bar..."
          if $mmo_key_items_bar.respond_to?(:sprites)
            $mmo_key_items_bar.sprites.each_value { |s| hide_and_dispose.call(s) }
          end
          $mmo_key_items_bar.dispose rescue nil
          $mmo_key_items_bar = nil
        end

        # Also dispose from Scene_Map instance variables
        if $scene.is_a?(Scene_Map)
          [:@mmo_ui_overlay, :@mmo_party_ui, :@mmo_key_items_bar].each do |var|
            if $scene.instance_variable_defined?(var)
              obj = $scene.instance_variable_get(var)
              if obj
                if obj.respond_to?(:sprites)
                  obj.sprites.each_value { |s| hide_and_dispose.call(s) }
                end
                obj.dispose rescue nil
                $scene.instance_variable_set(var, nil)
              end
            end
          end
          $scene.instance_variable_set(:@mmo_ui_initialized, false)
        end

        # Force graphics update multiple times
        3.times { Graphics.update }
        # === END CLEANUP ===

        if pbMultiplayerConnected?
          puts 'Disconnecting from server...'
          pbDisconnectFromMultiplayer
        end

        pbSetGameMode(GameMode::SINGLEPLAYER)

        $scene = pbCallTitle
        next true
      else

        puts 'Quitting singleplayer mode...'
        menu.pbEndScene

        scene = PokemonSave_Scene.new
        screen = PokemonSaveScreen.new(scene)
        if screen.pbSaveScreen

          $scene = pbCallTitle
        else

          $scene = Scene_Map.new
        end
        next true
      end
    end
    menu.pbRefresh
    menu.pbShowMenu
    next false
  }
})
