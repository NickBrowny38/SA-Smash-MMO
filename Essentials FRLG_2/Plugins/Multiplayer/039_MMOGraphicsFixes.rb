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
# Complete redesign for 800x600 resolution with proper centering and styling
#===============================================================================
class PokemonRegionMap_Scene
  # Override the coordinate conversion to account for map centering
  # The -SQUARE/2 offset centers the sprite on the tile (sprite origin is top-left)
  def point_x_to_screen_x(x)
    map_offset_x = (Graphics.width - @sprites["map"].bitmap.width) / 2
    return map_offset_x + (x * SQUARE_WIDTH) - (SQUARE_WIDTH / 2)
  end

  def point_y_to_screen_y(y)
    map_offset_y = (Graphics.height - @sprites["map"].bitmap.height) / 2
    return map_offset_y + (y * SQUARE_HEIGHT) - (SQUARE_HEIGHT / 2)
  end

  alias mmo_graphics_pbStartScene pbStartScene
  def pbStartScene(as_editor = false, fly_map = false)
    # Create a black screen FIRST with very high z to cover everything during setup
    @pre_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @pre_viewport.z = 999999  # Higher than everything
    @pre_overlay = Sprite.new(@pre_viewport)
    @pre_overlay.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @pre_overlay.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0))
    @pre_overlay.z = 999999
    Graphics.update

    # Call base scene - this will show the ugly blue borders but they're hidden behind our overlay
    result = mmo_graphics_pbStartScene(as_editor, fly_map)

    return cleanup_and_return(false) if !result

    # Apply MMO styling BEFORE removing overlay
    apply_mmo_styling

    # Reposition all point sprites (fly destinations)
    reposition_all_sprites

    # Force a graphics update to ensure all sprites are properly positioned
    Graphics.update

    # NOW fade out the overlay to reveal the properly styled scene
    8.times do
      @pre_overlay.opacity -= 32
      @pre_overlay.opacity = 0 if @pre_overlay.opacity < 0
      Graphics.update
    end

    # Clean up pre-overlay
    cleanup_pre_overlay

    return result
  end

  def cleanup_pre_overlay
    if @pre_overlay
      @pre_overlay.bitmap.dispose if @pre_overlay.bitmap && !@pre_overlay.bitmap.disposed?
      @pre_overlay.dispose if !@pre_overlay.disposed?
      @pre_overlay = nil
    end
    if @pre_viewport
      @pre_viewport.dispose if !@pre_viewport.disposed?
      @pre_viewport = nil
    end
  end

  def cleanup_and_return(result)
    cleanup_pre_overlay
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

    # Fix the background first - solid dark color
    if @sprites["background"]
      @sprites["background"].visible = false
    end

    # Create new clean background
    if !@sprites["mmo_bg"]
      @sprites["mmo_bg"] = Sprite.new(@viewport)
      @sprites["mmo_bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
      # Dark blue-gray gradient background
      Graphics.height.times do |y|
        ratio = y.to_f / Graphics.height
        r = (20 + 15 * ratio).to_i
        g = (30 + 20 * ratio).to_i
        b = (45 + 25 * ratio).to_i
        @sprites["mmo_bg"].bitmap.fill_rect(0, y, Graphics.width, 1, Color.new(r, g, b))
      end
      @sprites["mmo_bg"].z = -100
    end

    # Create a nice border around the map
    border_padding = 6
    if !@sprites["mmo_map_border"]
      @sprites["mmo_map_border"] = Sprite.new(@viewport)
      border_width = map_width + (border_padding * 2)
      border_height = map_height + (border_padding * 2)
      @sprites["mmo_map_border"].bitmap = Bitmap.new(border_width, border_height)

      bmp = @sprites["mmo_map_border"].bitmap

      # Outer shadow
      bmp.fill_rect(0, 0, border_width, border_height, Color.new(0, 0, 0, 100))

      # Main border (blue-ish frame like Pokemon style)
      bmp.fill_rect(1, 1, border_width - 2, border_height - 2, Color.new(56, 88, 136))

      # Inner highlight
      bmp.fill_rect(2, 2, border_width - 4, 2, Color.new(104, 144, 184))
      bmp.fill_rect(2, 2, 2, border_height - 4, Color.new(104, 144, 184))

      # Inner shadow
      bmp.fill_rect(border_width - 4, 4, 2, border_height - 6, Color.new(32, 56, 96))
      bmp.fill_rect(4, border_height - 4, border_width - 6, 2, Color.new(32, 56, 96))

      # Clear center for map
      bmp.fill_rect(border_padding, border_padding, map_width, map_height, Color.new(0, 0, 0, 0))

      @sprites["mmo_map_border"].x = center_x - border_padding
      @sprites["mmo_map_border"].y = center_y - border_padding
      @sprites["mmo_map_border"].z = -5
    end

    # Ensure map is properly centered
    map_sprite.x = center_x
    map_sprite.y = center_y
    map_sprite.z = 0

    # Also center map2 if it exists (extra graphics layer)
    if @sprites["map2"]
      @sprites["map2"].x = center_x
      @sprites["map2"].y = center_y
      @sprites["map2"].z = 1
    end
  end

  def reposition_all_sprites
    return unless @sprites && @sprites["map"]

    # Reposition player icon
    if @sprites["player"]
      @sprites["player"].x = point_x_to_screen_x(@map_x)
      @sprites["player"].y = point_y_to_screen_y(@map_y)
      @sprites["player"].z = 20
    end

    # Reposition cursor
    if @sprites["cursor"]
      @sprites["cursor"].x = point_x_to_screen_x(@map_x)
      @sprites["cursor"].y = point_y_to_screen_y(@map_y)
      @sprites["cursor"].z = 25
    end

    # Reposition all fly point sprites
    @sprites.each do |key, sprite|
      next unless key.start_with?("point")
      # These were positioned using the old point_x/y_to_screen functions
      # They need to be recalculated - but we don't have their original coords
      # The original code iterates LEFT..RIGHT, TOP..BOTTOM
      # We'll leave these as they should be handled by the coordinate functions now
    end
  end

  alias mmo_graphics_pbEndScene pbEndScene
  def pbEndScene
    # Clean fade out
    mmo_graphics_pbEndScene
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
