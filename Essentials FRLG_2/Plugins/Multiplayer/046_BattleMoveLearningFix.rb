class Battle::Scene
  alias mmo_battle_pbForgetMove pbForgetMove

  def pbForgetMove(pkmn, moveToLearn)
    ret = -1

    in_mmo_mode = defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?

    if in_mmo_mode
      # Don't use Graphics.freeze in MMO mode - it causes the screen to not show
      # Just open the summary screen directly
      scene = PokemonSummary_Scene.new
      screen = PokemonSummaryScreen.new(scene)
      ret = screen.pbStartForgetScreen([pkmn], 0, moveToLearn)

      # Force graphics update to show the result
      Graphics.update
      Input.update
    else
      pbFadeOutIn do
        scene = PokemonSummary_Scene.new
        screen = PokemonSummaryScreen.new(scene)
        ret = screen.pbStartForgetScreen([pkmn], 0, moveToLearn)
      end
    end

    return ret
  end
end

class PokemonSummary_Scene
  alias mmo_battle_pbStartScene pbStartScene

  def pbStartScene(party, partyindex = 0, inbattle = false)
    in_mmo_mode = defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?
    in_actual_battle = $game_temp && $game_temp.in_battle

    if in_mmo_mode && in_actual_battle && !inbattle
      @inbattle = true
    end

    if in_mmo_mode && in_actual_battle
      @battle_learn_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @battle_learn_viewport.z = 300000
      @battle_learn_mode = true
      # Note: Graphics.freeze is handled by 038_MMOUIFixes
      # We set @battle_learn_mode flag so 038 skips Graphics.transition
    end

    mmo_battle_pbStartScene(party, partyindex, inbattle || (@inbattle || false))

    if @battle_learn_viewport && @sprites
      # Assign all sprites to battle viewport
      # The viewport at z=300000 ensures everything renders above battle scene (z=99999)
      @sprites.each do |key, sprite|
        next unless sprite && !sprite.disposed?
        sprite.viewport = @battle_learn_viewport if sprite.respond_to?(:viewport=)
      end

      # Ensure overlay sprites have correct z WITHIN the viewport
      # Lower z = renders first (background), higher z = renders later (foreground)
      if @sprites["mmo_overlay_bg"]
        @sprites["mmo_overlay_bg"].z = 1  # Render first (dark background)
      end
      if @sprites["mmo_border"]
        @sprites["mmo_border"].z = 2  # Render second (border)
      end
      # Summary UI sprites at z=200000+ render last (on top)

      # NOW transition with all viewports properly set up
      Graphics.transition(0)
    end
  end

  alias mmo_battle_pbEndScene pbEndScene

  def pbEndScene
    mmo_battle_pbEndScene

    if @battle_learn_viewport
      @battle_learn_viewport.dispose
      @battle_learn_viewport = nil
    end
  end
end

puts "[Battle Move Learning Fix] Move learning screen properly centered in battles"
