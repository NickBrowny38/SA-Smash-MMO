#===============================================================================
# Battle Dialog Fix for MMO Overlay
# Ensures Yes/No dialogs appear properly above the constrained battle viewport
# This is a TARGETED fix - only patches battle-specific dialog methods
#===============================================================================

module MMOBattleDialogFix
  # High z-order viewport for battle dialogs
  @dialog_viewport = nil

  def self.get_dialog_viewport
    # Only create viewport during MMO battle mode
    return nil unless in_mmo_battle?

    # Create or return existing viewport
    if @dialog_viewport.nil? || @dialog_viewport.disposed?
      @dialog_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @dialog_viewport.z = 200000  # Very high z to be above everything
    end

    @dialog_viewport
  end

  def self.dispose_dialog_viewport
    if @dialog_viewport && !@dialog_viewport.disposed?
      @dialog_viewport.dispose
    end
    @dialog_viewport = nil
  end

  def self.in_mmo_battle?
    return false unless defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?
    return false unless defined?($game_temp) && $game_temp
    return $game_temp.in_battle == true
  end

  # Calculate centered battle area bounds
  def self.battle_bounds
    # Battle is constrained to 512x384 centered in 800x600
    battle_w = 512
    battle_h = 384
    offset_x = (Graphics.width - battle_w) / 2   # 144
    offset_y = (Graphics.height - battle_h) / 2  # 108
    return { x: offset_x, y: offset_y, w: battle_w, h: battle_h }
  end
end

#===============================================================================
# Patch Battle::Scene to ensure command windows appear in visible battle area
#===============================================================================
class Battle::Scene
  # Patch pbShowCommands to position windows correctly in MMO battles
  if !method_defined?(:mmo_dialog_pbShowCommands)
    alias mmo_dialog_pbShowCommands pbShowCommands

    def pbShowCommands(msg, commands, defaultValue = 0)
      # In MMO mode, we need to ensure the command window is positioned within
      # the visible battle viewport (centered 512x384 area) but NOT clipped by it
      if MMOBattleDialogFix.in_mmo_battle?
        pbWaitMessage
        pbShowWindow(MESSAGE_BOX)
        dw = @sprites["messageWindow"]
        dw.text = msg

        # Create command window with NO VIEWPORT so it's not clipped by battle viewport
        cw = Window_CommandPokemon.new(commands)
        cw.viewport = nil  # CRITICAL: No viewport = renders at screen level, not clipped

        # Get battle bounds for positioning (in screen coordinates)
        bounds = MMOBattleDialogFix.battle_bounds

        # Position command window in screen coordinates
        # Place it at the right side of the battle area, above the message box
        cw.height = bounds[:h] - dw.height if cw.height > bounds[:h] - dw.height
        cw.x = bounds[:x] + bounds[:w] - cw.width  # Right side of battle area
        cw.y = bounds[:y] + bounds[:h] - cw.height - dw.height  # Above message window
        cw.z = 200000  # Very high z to render above everything
        cw.index = 0

        PBDebug.log_message(msg) if defined?(PBDebug)
        loop do
          cw.visible = (!dw.busy?)
          pbUpdate(cw)
          dw.update
          if Input.trigger?(Input::BACK) && defaultValue >= 0
            if dw.busy?
              pbPlayDecisionSE if dw.pausing?
              dw.resume
            else
              pbPlayCancelSE
              cw.dispose
              return defaultValue
            end
          elsif Input.trigger?(Input::USE)
            if dw.busy?
              pbPlayDecisionSE if dw.pausing?
              dw.resume
            else
              pbPlayDecisionSE
              ret = cw.index
              cw.dispose
              return ret
            end
          end
        end
      end

      # Default behavior for non-MMO mode
      mmo_dialog_pbShowCommands(msg, commands, defaultValue)
    end
  end

  # Patch pbDisplayConfirmMessage for Yes/No dialogs (the actual method name)
  if !method_defined?(:mmo_dialog_pbDisplayConfirmMessage)
    alias mmo_dialog_pbDisplayConfirmMessage pbDisplayConfirmMessage

    def pbDisplayConfirmMessage(msg)
      # In MMO mode, use pbShowCommands with proper positioning
      if MMOBattleDialogFix.in_mmo_battle?
        return pbShowCommands(msg, [_INTL("Yes"), _INTL("No")], 1) == 0
      end

      # Default behavior for non-MMO mode
      mmo_dialog_pbDisplayConfirmMessage(msg)
    end
  end
end

#===============================================================================
# Clean up dialog viewport when battle ends
#===============================================================================
EventHandlers.add(:on_end_battle, :mmo_cleanup_dialog_viewport,
  proc { |decision, canLose|
    MMOBattleDialogFix.dispose_dialog_viewport
  }
)

puts "[Battle Dialog Fix] Targeted battle Yes/No dialog fix loaded"
puts "[Battle Dialog Fix] Patches Battle::Scene#pbShowCommands and #pbDisplayConfirmMessage"
