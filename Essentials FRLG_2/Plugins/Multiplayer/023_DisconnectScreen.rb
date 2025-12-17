class Scene_Disconnect
  def initialize(reason = nil)
    @reason = reason || "Connection to server lost"
    @viewport = nil
    @sprites  =  {}
  end

  def pbStartScene
    @viewport  =  Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999

    @sprites["overlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
    @sprites["overlay"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 200))

    window_width = 400
    window_height = 250
    window_x = (Graphics.width - window_width) / 2
    window_y = (Graphics.height - window_height) / 2

    @sprites['window'] = BitmapSprite.new(window_width, window_height, @viewport)
    @sprites["window"].x = window_x
    @sprites["window"].y = window_y

    bitmap  =  @sprites["window"].bitmap
    bitmap.fill_rect(0, 0, window_width, window_height, Color.new(40, 40, 60))
    bitmap.fill_rect(4, 4, window_width - 8, window_height - 8, Color.new(240, 240, 255))
    bitmap.fill_rect(8, 8, window_width - 16, window_height - 16, Color.new(60, 60, 80))

    icon_x  =  window_width / 2 - 20
    icon_y = 30
    bitmap.fill_rect(icon_x, icon_y, 40, 40, Color.new(200, 50, 50))

    base = pbTextBitmap("X", Graphics.width)
    base.font.size = 48
    base.font.bold = true
    base.font.color = Color.new(255, 255, 255)
    pbDrawTextPositions(bitmap, [[_INTL("×"), window_width / 2, icon_y + 5, 2, Color.new(255, 255, 255), Color.new(100, 20, 20)]])

    pbDrawTextPositions(bitmap, [
      [_INTL('CONNECTION LOST'), window_width / 2, 85, 2, Color.new(255, 100, 100), Color.new(20, 20, 30)]
    ])

    text_y = 120
    reason_lines = wrap_text(@reason, window_width - 40)
    reason_lines.each_with_index do |line, i|
      pbDrawTextPositions(bitmap, [
        [line, window_width / 2, text_y + (i * 25), 2, Color.new(230, 230, 230), Color.new(20, 20, 30)]
      ])
    end

    pbDrawTextPositions(bitmap, [
      [_INTL("Press Action to return to title"), window_width / 2, window_height - 50, 2, Color.new(200, 200, 200), Color.new(20, 20, 30)]
    ])

    pbFadeInAndShow(@sprites)
  end

  def pbEndScene
    pbFadeOutAndHide(@sprites)
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose if @viewport
  end

  def pbWaitForInput
    loop do      Graphics.update
      Input.update

      if @sprites["window"] && Graphics.frame_count % 60 < 30

      end

      if Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
        break
      end
    end
  end

  private

  def wrap_text(text, max_width)

    words = text.split(' ')
    lines = []
    current_line = ""

    words.each do |word|
      test_line = current_line.empty? ? word : "#{current_line} #{word}"
      if test_line.length * 7 < max_width
        current_line = test_line
      else
        lines << current_line unless current_line.empty?
        current_line = word
      end
    end
    lines << current_line unless current_line.empty?

    return lines
  end
end

def pbDisconnectScreen(reason = nil)
  scene = Scene_Disconnect.new(reason)
  scene.pbStartScene
  scene.pbWaitForInput
  scene.pbEndScene
end

module MultiplayerDisconnectHandler
  def self.handle_disconnect(reason = nil)
    puts "[MULTIPLAYER] Handling disconnect: #{reason}"

    pbMultiplayerClient.disconnect if pbMultiplayerClient

    pbDisconnectScreen(reason)

    $scene  =  pbCallTitle if $scene
  end
end
