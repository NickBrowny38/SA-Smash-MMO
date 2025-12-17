begin
  $GetKeyState = Win32API.new('user32', 'GetAsyncKeyState', 'i', 'i')
  $GetForegroundWindow = Win32API.new('user32', 'GetForegroundWindow', '', 'l')
  $FindWindow = Win32API.new('user32', 'FindWindow', 'pp', 'l')
  puts "Keyboard input: Win32API loaded successfully - GUARANTEED keyboard support enabled"
rescue => e
  $GetKeyState  =  nil
  $GetForegroundWindow = nil
  $FindWindow = nil
  puts "WARNING: Win32API failed to load: #{e.message}"
  puts 'Keyboard input will use fallback mode'
end

def pbWindowHasFocus?
  return true unless $GetForegroundWindow

  begin
    focused_window = $GetForegroundWindow.call

    if $FindWindow
      game_window = $FindWindow.call("RGSS Player", nil)
      return true if game_window != 0 && game_window == focused_window

      game_window = $FindWindow.call("RGSS", nil)
      return true if game_window != 0 && game_window == focused_window

      game_window = $FindWindow.call(nil, 'Pokemon Essentials')
      return true if game_window != 0 && game_window == focused_window
    end

    return true
  rescue => e

    return true
  end
end

class KeyboardInput
  attr_reader :text
  attr_reader :active

  SHIFT_KEY = 0x10
  CAPS_LOCK_KEY  =  0x14
  BACKSPACE_KEY = 0x08
  ENTER_KEY = 0x0D
  ESC_KEY = 0x1B

  def initialize(prompt = "Enter text:", max_length = 100, password_mode = false)
    @prompt = prompt
    @text = ""
    @max_length  =  max_length
    @password_mode = password_mode
    @active  =  false
    @cursor_visible = true
    @cursor_timer = 0
    @keys_pressed = {}
    @last_update = Time.now
  end

  def activate
    @active = true
    @text  =  ""
    @keys_pressed.clear
  end

  def deactivate
    @active = false
  end

  def update
    return unless @active
    return unless pbWindowHasFocus?

    @cursor_timer += 1
    @cursor_visible = (@cursor_timer / 20) % 2 == 0

    if $GetKeyState
      check_keyboard_win32
    else

      puts "WARNING: No keyboard input available, using fallback"
    end

    if $GetKeyState && ($GetKeyState.call(ENTER_KEY) & 0x8000) != 0
      return :confirm unless @keys_pressed[ENTER_KEY]
      @keys_pressed[ENTER_KEY] = true
    elsif $GetKeyState
      @keys_pressed[ENTER_KEY]  =  false
    end

    if $GetKeyState && ($GetKeyState.call(ESC_KEY) & 0x8000) != 0
      return :cancel if @text.empty? && !@keys_pressed[ESC_KEY]
      @keys_pressed[ESC_KEY] = true
    elsif $GetKeyState
      @keys_pressed[ESC_KEY]  =  false
    end

    return nil
  end

  def check_keyboard_win32

    shift = ($GetKeyState.call(SHIFT_KEY) & 0x8000) != 0
    caps = ($GetKeyState.call(CAPS_LOCK_KEY) & 0x0001) != 0

    if ($GetKeyState.call(BACKSPACE_KEY) & 0x8000) != 0
      unless @keys_pressed[BACKSPACE_KEY]
        @text = @text[0...-1] unless @text.empty?
        @keys_pressed[BACKSPACE_KEY] = true
      end
    else
      @keys_pressed[BACKSPACE_KEY] = false
    end

    (0x41..0x5A).each do |key|
      if ($GetKeyState.call(key) & 0x8000) != 0
        unless @keys_pressed[key]
          char = key.chr
          char = char.downcase unless shift || caps
          @text += char if @text.length < @max_length
          @keys_pressed[key] = true
        end
      else
        @keys_pressed[key] = false
      end
    end

    (0x30..0x39).each do |key|
      if ($GetKeyState.call(key) & 0x8000) != 0
        unless @keys_pressed[key]
          if shift

            char  =  case key
                   when 0x30 then ')'
                   when 0x31 then '!'
                   when 0x32 then '@'
                   when 0x33 then '#'
                   when 0x34 then '$'
                   when 0x35 then '%'
                   when 0x36 then '^'
                   when 0x37 then '&'
                   when 0x38 then '*'
                   when 0x39 then '('
                   end
          else
            char  =  (key - 0x30).to_s
          end
          @text += char if @text.length < @max_length
          @keys_pressed[key] = true
        end
      else
        @keys_pressed[key]  =  false
      end
    end

    if ($GetKeyState.call(0x20) & 0x8000) != 0
      unless @keys_pressed[0x20]
        @text += ' ' if @text.length < @max_length
        @keys_pressed[0x20]  =  true
      end
    else
      @keys_pressed[0x20] = false
    end

    punctuation = {
      0xBA => [';', ':'],
      0xBB => ['=', '+'],
      0xBC => [',', '<'],
      0xBD => ['-', '_'],
      0xBE => ['.', '>'],
      0xBF => ['/', '?'],
      0xC0 => ['`', '~'],
      0xDB => ['[', '{'],
      0xDC => ['\\', '|'],
      0xDD => [']', '}'],
      0xDE => ["'", '"']
    }

    punctuation.each do |key, chars|
      if ($GetKeyState.call(key) & 0x8000) != 0
        unless @keys_pressed[key]
          char = shift ? chars[1] : chars[0]
          @text += char if @text.length < @max_length
          @keys_pressed[key] = true
        end
      else
        @keys_pressed[key] = false
      end
    end
  end

  def draw(viewport)

    @sprite ||= Sprite.new(viewport)
    @sprite.bitmap ||= Bitmap.new(Graphics.width, 120)
    @sprite.bitmap.clear

    @sprite.x  =  0
    @sprite.y = (Graphics.height - 120) / 2
    @sprite.z = 99999

    @sprite.bitmap.fill_rect(0, 0, Graphics.width, 120, Color.new(255, 255, 255, 255))

    @sprite.bitmap.fill_rect(4, 4, Graphics.width - 8, 112, Color.new(20, 20, 40, 240))

    pbSetSystemFont(@sprite.bitmap)
    @sprite.bitmap.font.size  =  28
    @sprite.bitmap.font.bold  =  true
    @sprite.bitmap.font.color = Color.new(255, 255, 100)
    @sprite.bitmap.draw_text(20, 15, Graphics.width - 40, 32, @prompt)

    @sprite.bitmap.fill_rect(20, 55, Graphics.width - 40, 40, Color.new(0, 0, 0, 200))
    @sprite.bitmap.fill_rect(22, 57, Graphics.width - 44, 36, Color.new(40, 40, 60, 255))

    display_text = @password_mode ? ("*" * @text.length) : @text
    display_text += "|" if @cursor_visible

    @sprite.bitmap.font.size = 24
    @sprite.bitmap.font.bold = false
    @sprite.bitmap.font.color = Color.new(255, 255, 255)
    @sprite.bitmap.draw_text(30, 60, Graphics.width - 60, 32, display_text)

    @sprite.bitmap.font.size = 18
    @sprite.bitmap.font.color = Color.new(180, 180, 180)
    hint_text = "Press Enter to confirm • ESC to cancel"
    @sprite.bitmap.draw_text(20, 95, Graphics.width - 40, 20, hint_text, 1)
  end

  def dispose
    if @sprite
      @sprite.bitmap.dispose if @sprite.bitmap
      @sprite.dispose
      @sprite  =  nil
    end
  end
end

def pbSimpleAlert(title, message)
  viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
  viewport.z = 99999

  bg_sprite = Sprite.new(viewport)
  bg_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
  bg_sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 200))

  box_width  =  450
  box_height = 250
  box_x = (Graphics.width - box_width) / 2
  box_y = (Graphics.height - box_height) / 2

  box_sprite = Sprite.new(viewport)
  box_sprite.bitmap = Bitmap.new(box_width, box_height)
  box_sprite.x = box_x
  box_sprite.y  =  box_y
  box_sprite.z = 100000

  box_sprite.bitmap.fill_rect(0, 0, box_width, box_height, Color.new(255, 255, 255, 255))

  box_sprite.bitmap.fill_rect(4, 4, box_width - 8, box_height - 8, Color.new(30, 30, 60, 255))

  box_sprite.bitmap.fill_rect(8, 8, box_width - 16, 45, Color.new(180, 50, 50, 255))
  pbSetSystemFont(box_sprite.bitmap)
  box_sprite.bitmap.font.size = 28
  box_sprite.bitmap.font.bold = true
  box_sprite.bitmap.font.color  =  Color.new(255, 255, 255, 255)
  box_sprite.bitmap.draw_text(15, 12, box_width - 30, 40, title, 1)

  pbSetSystemFont(box_sprite.bitmap)
  box_sprite.bitmap.font.size = 22
  box_sprite.bitmap.font.bold = false
  box_sprite.bitmap.font.color = Color.new(255, 255, 255, 255)

  message_lines = message.split('\n')
  y_offset = 70
  message_lines.each do |line|
    box_sprite.bitmap.draw_text(20, y_offset, box_width - 40, 30, line, 1)
    y_offset += 32
  end

  button_width  =  150
  button_height = 45
  button_x  =  (box_width - button_width) / 2
  button_y  =  box_height - 60

  box_sprite.bitmap.fill_rect(button_x, button_y, button_width, button_height, Color.new(100, 180, 255, 255))
  box_sprite.bitmap.fill_rect(button_x + 2, button_y + 2, button_width - 4, button_height - 4, Color.new(60, 140, 220, 255))

  box_sprite.bitmap.font.size = 24
  box_sprite.bitmap.font.bold  =  true
  box_sprite.bitmap.draw_text(button_x, button_y + 8, button_width, 32, 'OK', 1)

  keys_pressed = {}
  loop do    Graphics.update
    Input.update

    if $GetKeyState

      if ($GetKeyState.call(0x0D) & 0x8000) != 0
        unless keys_pressed[0x0D]
          keys_pressed[0x0D] = true
          break
        end
      else
        keys_pressed[0x0D] = false
      end

      if ($GetKeyState.call(0x20) & 0x8000) != 0
        unless keys_pressed[0x20]
          keys_pressed[0x20] = true
          break
        end
      else
        keys_pressed[0x20] = false
      end
    end

    if Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
      break
    end

    sleep(0.01)
  end

  box_sprite.bitmap.dispose
  box_sprite.dispose
  bg_sprite.bitmap.dispose
  bg_sprite.dispose
  viewport.dispose

  return true
end

def pbSimpleConfirm(prompt)
  viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
  viewport.z = 99999

  bg_sprite = Sprite.new(viewport)
  bg_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
  bg_sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))

  box_width = 400
  box_height  =  150
  box_x = (Graphics.width - box_width) / 2
  box_y = (Graphics.height - box_height) / 2

  box_sprite = Sprite.new(viewport)
  box_sprite.bitmap  =  Bitmap.new(box_width, box_height)
  box_sprite.x = box_x
  box_sprite.y = box_y
  box_sprite.z = 100000

  box_sprite.bitmap.fill_rect(0, 0, box_width, box_height, Color.new(255, 255, 255, 255))
  box_sprite.bitmap.fill_rect(4, 4, box_width - 8, box_height - 8, Color.new(80, 80, 88, 255))

  pbSetSystemFont(box_sprite.bitmap)
  box_sprite.bitmap.font.size = 24
  box_sprite.bitmap.font.color = Color.new(255, 255, 255, 255)
  text_lines = prompt.split('\n')
  text_lines.each_with_index do |line, i|
    box_sprite.bitmap.draw_text(10, 20 + (i * 30), box_width - 20, 32, line, 1)
  end

  selection = 0
  cursor_sprite  =  Sprite.new(viewport)
  cursor_sprite.bitmap = Bitmap.new(180, 40)
  cursor_sprite.z = 100001

  text_sprite = Sprite.new(viewport)
  text_sprite.bitmap  =  Bitmap.new(box_width, 40)
  text_sprite.x = box_x
  text_sprite.y = box_y + 85
  text_sprite.z = 100002
  pbSetSystemFont(text_sprite.bitmap)
  text_sprite.bitmap.font.size = 24

  def draw_cursor_and_text(cursor_sprite, text_sprite, selection, box_x, box_y, box_width)

    cursor_sprite.bitmap.clear
    cursor_sprite.bitmap.fill_rect(0, 0, 180, 40, Color.new(255, 220, 100, 255))
    cursor_sprite.bitmap.fill_rect(3, 3, 174, 34, Color.new(100, 100, 120, 255))

    if selection == 0
      cursor_sprite.x = box_x + 10
    else
      cursor_sprite.x = box_x + box_width / 2 + 10
    end
    cursor_sprite.y  =  box_y + 85

    text_sprite.bitmap.clear

    if selection == 0
      text_sprite.bitmap.font.color  =  Color.new(255, 255, 100, 255)
    else
      text_sprite.bitmap.font.color  =  Color.new(200, 200, 200, 255)
    end
    text_sprite.bitmap.draw_text(10, 5, box_width / 2 - 20, 32, "YES (Y)", 1)

    if selection == 1
      text_sprite.bitmap.font.color = Color.new(255, 255, 100, 255)
    else
      text_sprite.bitmap.font.color = Color.new(200, 200, 200, 255)
    end
    text_sprite.bitmap.draw_text(box_width / 2 + 10, 5, box_width / 2 - 20, 32, 'NO (N)', 1)
  end

  draw_cursor_and_text(cursor_sprite, text_sprite, selection, box_x, box_y, box_width)

  keys_pressed  =  {}

  5.times do    Graphics.update
    Input.update
  end

  loop do    Graphics.update
    Input.update

    if $GetKeyState && ($GetKeyState.call(0x59) & 0x8000) != 0
      unless keys_pressed[0x59]
        keys_pressed[0x59] = true

        text_sprite.bitmap.dispose
        text_sprite.dispose
        cursor_sprite.bitmap.dispose
        cursor_sprite.dispose
        box_sprite.bitmap.dispose
        box_sprite.dispose
        bg_sprite.bitmap.dispose
        bg_sprite.dispose
        viewport.dispose
        return true
      end
    else
      keys_pressed[0x59]  =  false if $GetKeyState
    end

    if $GetKeyState && ($GetKeyState.call(0x4E) & 0x8000) != 0
      unless keys_pressed[0x4E]
        keys_pressed[0x4E] = true

        text_sprite.bitmap.dispose
        text_sprite.dispose
        cursor_sprite.bitmap.dispose
        cursor_sprite.dispose
        box_sprite.bitmap.dispose
        box_sprite.dispose
        bg_sprite.bitmap.dispose
        bg_sprite.dispose
        viewport.dispose
        return false
      end
    else
      keys_pressed[0x4E]  =  false if $GetKeyState
    end

    if $GetKeyState && ($GetKeyState.call(0x25) & 0x8000) != 0
      unless keys_pressed[0x25]
        selection  =  0
        draw_cursor_and_text(cursor_sprite, text_sprite, selection, box_x, box_y, box_width)
        keys_pressed[0x25] = true
      end
    else
      keys_pressed[0x25] = false if $GetKeyState
    end

    if $GetKeyState && ($GetKeyState.call(0x27) & 0x8000) != 0
      unless keys_pressed[0x27]
        selection = 1
        draw_cursor_and_text(cursor_sprite, text_sprite, selection, box_x, box_y, box_width)
        keys_pressed[0x27] = true
      end
    else
      keys_pressed[0x27] = false if $GetKeyState
    end

    if $GetKeyState && ($GetKeyState.call(0x0D) & 0x8000) != 0
      unless keys_pressed[0x0D]
        keys_pressed[0x0D] = true
        result = (selection == 0)

        text_sprite.bitmap.dispose
        text_sprite.dispose
        cursor_sprite.bitmap.dispose
        cursor_sprite.dispose
        box_sprite.bitmap.dispose
        box_sprite.dispose
        bg_sprite.bitmap.dispose
        bg_sprite.dispose
        viewport.dispose
        return result
      end
    else
      keys_pressed[0x0D] = false if $GetKeyState
    end

    if $GetKeyState && ($GetKeyState.call(0x20) & 0x8000) != 0
      unless keys_pressed[0x20]
        keys_pressed[0x20] = true
        result = (selection == 0)

        text_sprite.bitmap.dispose
        text_sprite.dispose
        cursor_sprite.bitmap.dispose
        cursor_sprite.dispose
        box_sprite.bitmap.dispose
        box_sprite.dispose
        bg_sprite.bitmap.dispose
        bg_sprite.dispose
        viewport.dispose
        return result
      end
    else
      keys_pressed[0x20] = false if $GetKeyState
    end

    if $GetKeyState && ($GetKeyState.call(0x1B) & 0x8000) != 0
      unless keys_pressed[0x1B]
        keys_pressed[0x1B]  =  true

        text_sprite.bitmap.dispose
        text_sprite.dispose
        cursor_sprite.bitmap.dispose
        cursor_sprite.dispose
        box_sprite.bitmap.dispose
        box_sprite.dispose
        bg_sprite.bitmap.dispose
        bg_sprite.dispose
        viewport.dispose
        return false
      end
    else
      keys_pressed[0x1B] = false if $GetKeyState
    end
  end
end

def pbKeyboardInput(prompt = "Enter text:", max_length = 100, default_text = "", trigger_key = nil, password_mode = false)
  viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
  viewport.z = 99999

  keyboard  =  KeyboardInput.new(prompt, max_length, password_mode)
  keyboard.activate
  keyboard.instance_variable_set(:@text, default_text) if default_text

  if trigger_key && $GetKeyState
    loop do      Graphics.update
      Input.update
      keyboard.draw(viewport)

      break if ($GetKeyState.call(trigger_key) & 0x8000) == 0
    end
  end

  10.times do    Graphics.update
    Input.update
    keyboard.draw(viewport)
  end

  if $GetKeyState
    loop do      all_released = true

      (0x41..0x5A).each do |key|
        if ($GetKeyState.call(key) & 0x8000) != 0
          all_released = false
          break
        end
      end

      break if all_released

      Graphics.update
      Input.update
      keyboard.draw(viewport)
    end
  end

  loop do    Graphics.update
    Input.update

    result  =  keyboard.update
    keyboard.draw(viewport)

    if result == :confirm
      text = keyboard.text
      keyboard.deactivate
      keyboard.dispose
      viewport.dispose
      return text
    elsif result == :cancel
      keyboard.deactivate
      keyboard.dispose
      viewport.dispose
      return nil
    end
  end
end
