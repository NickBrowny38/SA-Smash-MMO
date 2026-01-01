#===============================================================================
# MMO Graphics Fixes
# Fixes HM animations, Town Map, and other graphics for 800x600 resolution
#===============================================================================

#===============================================================================
# HM/Field Move Animation Fix
# Makes the animation span the full screen width instead of just 512px
#===============================================================================
def pbHiddenMoveAnimation(pokemon)
  return false if !pokemon

  # Calculate dimensions for full screen
  anim_height = 160  # Original height

  # Create viewport spanning full screen width
  viewport = Viewport.new(0, 0, Graphics.width, 0)
  viewport.z = 99999

  # Create background that spans full width
  bg = Sprite.new(viewport)

  # Try to load original background and scale it, or create a gradient
  original_bg = RPG::Cache.ui("Field move/bg") rescue nil
  if original_bg
    # Create a new bitmap at full width
    bg.bitmap = Bitmap.new(Graphics.width, anim_height)

    # Fill with a gradient matching the original style (orange/yellow)
    anim_height.times do |y|
      # Create gradient from orange to yellow
      ratio = y.to_f / anim_height
      r = (255 * (1 - ratio * 0.3)).to_i
      g = (180 + 60 * ratio).to_i
      b = (50 * ratio).to_i
      bg.bitmap.fill_rect(0, y, Graphics.width, 1, Color.new(r, g, b))
    end

    # Add some visual flair - horizontal lines
    (0...anim_height).step(8) do |y|
      bg.bitmap.fill_rect(0, y, Graphics.width, 1, Color.new(255, 255, 200, 100))
    end
  else
    bg.bitmap = Bitmap.new(Graphics.width, anim_height)
    bg.bitmap.fill_rect(0, 0, Graphics.width, anim_height, Color.new(255, 200, 50))
  end

  # Pokemon sprite
  sprite = PokemonSprite.new(viewport)
  sprite.setOffset(PictureOrigin::CENTER)
  sprite.setPokemonBitmap(pokemon)
  sprite.x = Graphics.width + (sprite.bitmap.width / 2)
  sprite.y = anim_height / 2
  sprite.z = 1
  sprite.visible = false

  # Strobe effects
  strobebitmap = AnimatedBitmap.new("Graphics/UI/Field move/strobes")
  strobes = []
  15.times do |i|
    strobe = BitmapSprite.new(52, 16, viewport)
    strobe.bitmap.blt(0, 0, strobebitmap.bitmap, Rect.new(0, (i % 2) * 16, 52, 16))
    strobe.z = (i.even? ? 2 : 0)
    strobe.visible = false
    strobes.push(strobe)
  end
  strobebitmap.dispose

  # Animation phases
  phase = 1
  timer_start = System.uptime
  strobes_start_x = []
  strobes_timers = []

  loop do
    Graphics.update
    Input.update
    sprite.update

    case phase
    when 1   # Expand viewport height from zero to full
      viewport.rect.y = lerp(Graphics.height / 2, (Graphics.height - anim_height) / 2,
                             0.25, timer_start, System.uptime)
      viewport.rect.height = Graphics.height - (viewport.rect.y * 2)
      bg.oy = (anim_height - viewport.rect.height) / 2
      if viewport.rect.y == (Graphics.height - anim_height) / 2
        phase = 2
        sprite.visible = true
        timer_start = System.uptime
      end

    when 2   # Slide Pokemon sprite in from right to centre
      sprite.x = lerp(Graphics.width + (sprite.bitmap.width / 2), Graphics.width / 2,
                      0.4, timer_start, System.uptime)
      if sprite.x == Graphics.width / 2
        phase = 3
        pokemon.play_cry
        timer_start = System.uptime
        strobes.each_with_index do |strobe, i|
          strobe.x = -52 - (rand(Graphics.width / 2))
          strobe.y = rand(anim_height - 16)
          strobes_start_x[i] = strobe.x
          strobes_timers[i] = System.uptime + (rand(20) / 100.0)
        end
      end

    when 3   # Pokémon sprite and strobes pause
      strobes.each_with_index do |strobe, i|
        strobe.visible = true
        strobe.x = lerp(strobes_start_x[i], Graphics.width + 52, 0.4, strobes_timers[i], System.uptime)
      end
      if System.uptime - timer_start >= 0.75
        phase = 4
        timer_start = System.uptime
      end

    when 4   # Slide Pokemon sprite off to left
      sprite.x = lerp(Graphics.width / 2, -(sprite.bitmap.width / 2), 0.4, timer_start, System.uptime)
      strobes.each_with_index do |strobe, i|
        strobe.x = lerp(strobes_start_x[i], Graphics.width + 52, 0.4, strobes_timers[i], System.uptime)
      end
      if sprite.x == -(sprite.bitmap.width / 2)
        phase = 5
        timer_start = System.uptime
      end

    when 5   # Contract viewport height to zero
      viewport.rect.y = lerp((Graphics.height - anim_height) / 2, Graphics.height / 2,
                             0.25, timer_start, System.uptime)
      viewport.rect.height = Graphics.height - (viewport.rect.y * 2)
      bg.oy = (anim_height - viewport.rect.height) / 2
      break if viewport.rect.y == Graphics.height / 2
    end
  end

  # Cleanup
  sprite.dispose
  strobes.each { |strobe| strobe.dispose }
  bg.dispose
  viewport.dispose
  return true
end

#===============================================================================
# Town Map / Region Map Fix
# Centers the map properly and adds a styled border for 800x600 resolution
#===============================================================================
class PokemonRegionMap_Scene
  alias mmo_graphics_pbStartScene pbStartScene
  def pbStartScene(as_editor = false, fly_map = false)
    result = mmo_graphics_pbStartScene(as_editor, fly_map)
    return result if !result

    # Apply MMO styling - dark overlay and centered border
    apply_mmo_styling

    return result
  end

  def apply_mmo_styling
    return unless @sprites && @viewport

    # Get the map sprite dimensions
    map_sprite = @sprites["map"]
    return unless map_sprite && map_sprite.bitmap

    map_width = map_sprite.bitmap.width
    map_height = map_sprite.bitmap.height

    # Calculate center position
    center_x = (Graphics.width - map_width) / 2
    center_y = (Graphics.height - map_height) / 2

    # Create dark overlay behind everything
    if !@sprites["mmo_dark_overlay"]
      @sprites["mmo_dark_overlay"] = Sprite.new(@viewport)
      @sprites["mmo_dark_overlay"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
      @sprites["mmo_dark_overlay"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))
      @sprites["mmo_dark_overlay"].z = -10
    end

    # Create a nice border around the map
    border_padding = 8
    if !@sprites["mmo_map_border"]
      @sprites["mmo_map_border"] = Sprite.new(@viewport)
      border_width = map_width + (border_padding * 2)
      border_height = map_height + (border_padding * 2)
      @sprites["mmo_map_border"].bitmap = Bitmap.new(border_width, border_height)

      # Draw border with gradient effect
      bmp = @sprites["mmo_map_border"].bitmap

      # Outer border (dark)
      bmp.fill_rect(0, 0, border_width, border_height, Color.new(40, 60, 80))

      # Inner border (lighter)
      bmp.fill_rect(2, 2, border_width - 4, border_height - 4, Color.new(60, 90, 120))

      # Highlight edges
      bmp.fill_rect(2, 2, border_width - 4, 2, Color.new(100, 140, 180))
      bmp.fill_rect(2, 2, 2, border_height - 4, Color.new(100, 140, 180))

      # Inner area (will be covered by map)
      bmp.fill_rect(border_padding, border_padding, map_width, map_height, Color.new(0, 0, 0, 0))

      @sprites["mmo_map_border"].x = center_x - border_padding
      @sprites["mmo_map_border"].y = center_y - border_padding
      @sprites["mmo_map_border"].z = -5
    end

    # Ensure map is properly centered
    map_sprite.x = center_x
    map_sprite.y = center_y

    # Also center map2 if it exists (extra graphics layer)
    if @sprites["map2"]
      @sprites["map2"].x = center_x
      @sprites["map2"].y = center_y
    end

    # Fix the background to not show the ugly blue
    if @sprites["background"]
      # Replace with solid dark color that matches our overlay
      @sprites["background"].bitmap.clear if @sprites["background"].bitmap
      @sprites["background"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
      @sprites["background"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(20, 30, 40))
      @sprites["background"].z = -20
    end

    # Fix the highlight/cursor sprite if it exists
    if @sprites["highlight"]
      # Adjust highlight position based on map offset
      # The highlight uses SQUARE_WIDTH (16) increments
    end

    # Fix the player icon position
    if @sprites["player"]
      @sprites["player"].x = center_x + (@map_x * SQUARE_WIDTH) + (SQUARE_WIDTH / 2)
      @sprites["player"].y = center_y + (@map_y * SQUARE_HEIGHT) + (SQUARE_HEIGHT / 2)
    end
  end

  # Override cursor movement to account for centering
  alias mmo_graphics_pbMapScene pbMapScene rescue nil
  def pbMapScene
    # Ensure player icon stays centered properly during scene
    if @sprites["player"] && @sprites["map"]
      center_x = @sprites["map"].x
      center_y = @sprites["map"].y
      @sprites["player"].x = center_x + (@map_x * SQUARE_WIDTH) + (SQUARE_WIDTH / 2)
      @sprites["player"].y = center_y + (@map_y * SQUARE_HEIGHT) + (SQUARE_HEIGHT / 2)
    end

    if self.respond_to?(:mmo_graphics_pbMapScene)
      return mmo_graphics_pbMapScene
    else
      # Default implementation if alias failed
      return nil
    end
  end
end

#===============================================================================
# Map Bottom Sprite Fix (Town Map location text)
# Adjusts text positioning for 800x600
#===============================================================================
class MapBottomSprite < Sprite
  alias mmo_graphics_refresh refresh
  def refresh
    bitmap.clear

    # Adjusted positions for 800x600 resolution
    # Keep region name at top left
    # Move location name to bottom, centered under the map
    map_center_x = Graphics.width / 2
    bottom_y = Graphics.height - 40

    textpos = [
      [@mapname, 18, 4, :left, TEXT_MAIN_COLOR, TEXT_SHADOW_COLOR],
      [@maplocation, 18, bottom_y, :left, TEXT_MAIN_COLOR, TEXT_SHADOW_COLOR],
      [@mapdetails, Graphics.width - 18, bottom_y, :right, TEXT_MAIN_COLOR, TEXT_SHADOW_COLOR]
    ]
    pbDrawTextPositions(bitmap, textpos)
  end
end

puts "[MMO Graphics Fixes] HM animation and Town Map fixes loaded for 800x600 resolution"
