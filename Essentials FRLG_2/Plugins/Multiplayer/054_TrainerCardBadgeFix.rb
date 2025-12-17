#===============================================================================
# Fix trainer card badge display for integer badges (1/0) from server
# In Ruby, 0 is truthy! So we must explicitly check for non-zero values
#===============================================================================

class PokemonTrainerCard_Scene
  alias mmo_badge_pbDrawTrainerCardFront pbDrawTrainerCardFront

  def pbDrawTrainerCardFront
    mmo_badge_pbDrawTrainerCardFront

    # Fix badge display for multiplayer mode
    if defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?
      overlay = @sprites["overlay"].bitmap

      # Clear old badge area
      overlay.fill_rect(72, 310, 384, 32, Color.new(0, 0, 0, 0))

      # Redraw badges with correct integer check
      x = 72
      region = pbGetCurrentRegion(0)
      imagePositions = []
      8.times do |i|
        badge_value = $player.badges[i + (region * 8)]
        # IMPORTANT: Check for 1 or true, not just truthiness (0 is truthy in Ruby!)
        if badge_value == 1 || badge_value == true
          imagePositions.push(["Graphics/UI/Trainer Card/icon_badges", x, 310, i * 32, region * 32, 32, 32])
        end
        x += 48
      end
      pbDrawImagePositions(overlay, imagePositions)
    end
  end
end

puts "[Trainer Card Badge Fix] Fixed badge display to work with integer badges from server"
