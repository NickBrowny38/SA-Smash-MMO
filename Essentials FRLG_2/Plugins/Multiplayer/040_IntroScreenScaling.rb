# Center title screen for 800x600 resolution
# Title assets are designed for 512x384, so we need to offset them
class IntroEventScene < EventScene
  # Calculate the offset to center 512x384 content in 800x600 window
  def mmo_title_x_offset
    (Graphics.width - 512) / 2  # (800 - 512) / 2 = 144
  end

  def mmo_title_y_offset
    (Graphics.height - 384) / 2  # (600 - 384) / 2 = 108
  end

  alias mmo_open_title_screen open_title_screen unless method_defined?(:mmo_open_title_screen)

  def open_title_screen(_scene, *args)
    onUpdate.clear
    onCTrigger.clear

    x_offset = mmo_title_x_offset
    y_offset = mmo_title_y_offset

    # Set background image centered
    @pic.name = "Graphics/Titles/" + TITLE_BG_IMAGE
    @pic.setXY(0, x_offset, y_offset)
    @pic.moveOpacity(0, FADE_TICKS, 255)

    # Set "Press Enter" image centered
    @pic2.name = "Graphics/Titles/" + TITLE_START_IMAGE
    # TITLE_START_IMAGE_X and TITLE_START_IMAGE_Y are relative to the title screen
    press_enter_x = TITLE_START_IMAGE_X + x_offset
    press_enter_y = TITLE_START_IMAGE_Y + y_offset
    @pic2.setXY(0, press_enter_x, press_enter_y)
    @pic2.setVisible(0, true)
    @pic2.moveOpacity(0, FADE_TICKS, 255)

    pictureWait
    pbBGMPlay($data_system.title_bgm)
    onUpdate.set(method(:title_screen_update))
    onCTrigger.set(method(:close_title_screen))
  end

  # Also center splash screens
  alias mmo_open_splash open_splash unless method_defined?(:mmo_open_splash)

  def open_splash(_scene, *args)
    onCTrigger.clear
    @pic.name = "Graphics/Titles/" + SPLASH_IMAGES[@index]
    @pic.setXY(0, mmo_title_x_offset, mmo_title_y_offset)
    @pic.moveOpacity(0, FADE_TICKS, 255)
    pictureWait
    @timer = System.uptime
    onUpdate.set(method(:splash_update))
    onCTrigger.set(method(:close_splash))
  end
end

puts "[MMO Intro] Intro screen centered for 800x600 resolution"
