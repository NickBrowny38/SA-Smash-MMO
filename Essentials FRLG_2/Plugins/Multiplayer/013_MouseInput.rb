module MouseInput
  WM_MOUSEWHEEL = 0x020A

  @last_scroll_delta  =  0
  @scroll_delta  =  0

  @mouse_buttons = {}

  begin
    $GetCursorPos = Win32API.new('user32', 'GetCursorPos', 'p', 'i')
    $ScreenToClient = Win32API.new('user32', 'ScreenToClient', 'lp', 'i')
    $GetMessageExtraInfo  =  Win32API.new('user32', 'GetMessageExtraInfo', '', 'l')
    $GetAsyncKeyState = Win32API.new('user32', 'GetAsyncKeyState', 'i', 'i')
    GetActiveWindow = Win32API.new('user32', 'GetActiveWindow', '', 'l')

    $PeekMessage = Win32API.new('user32', 'PeekMessageA', 'pllll', 'i')

    puts "[Mouse Input] Win32API mouse support enabled"
    @mouse_available = true
  rescue => e
    puts "[Mouse Input] Win32API mouse support not available: #{e.message}"
    @mouse_available  =  false
  end

  def self.available?
    @mouse_available
  end

  def self.get_position
    return [0, 0] unless @mouse_available

    begin
      pos  =  [0, 0].pack('ll')
      $GetCursorPos.call(pos)
      x, y  =  pos.unpack('ll')

      hwnd = GetActiveWindow.call
      client_pos = [x, y].pack('ll')
      $ScreenToClient.call(hwnd, client_pos)
      x, y = client_pos.unpack('ll')

      return [x, y]
    rescue
      return [0, 0]
    end
  end

  def self.mouse_x
    pos = get_position
    return pos[0]
  end

  def self.mouse_y
    pos = get_position
    return pos[1]
  end

  def self.pos
    get_position
  end

  def self.click?(button = 0)
    return false unless @mouse_available

    vk_code = case button
    when 0 then 0x01
    when 1 then 0x02
    when 2 then 0x04
    else return false
    end

    begin

      pressed  =  ($GetAsyncKeyState.call(vk_code) & 0x8000) != 0

      if pressed && !@mouse_buttons[button]
        @mouse_buttons[button] = true
        return true
      elsif !pressed
        @mouse_buttons[button]  =  false
      end

      return false
    rescue
      return false
    end
  end

  def self.left_click?
    click?(0)
  end

  def self.right_click?
    click?(1)
  end

  def self.middle_click?
    click?(2)
  end

  def self.press?(button = 0)
    return false unless @mouse_available

    vk_code = case button
    when 0 then 0x01
    when 1 then 0x02
    when 2 then 0x04
    else return false
    end

    begin
      return ($GetAsyncKeyState.call(vk_code) & 0x8000) != 0
    rescue
      return false
    end
  end

  def self.update_scroll
    return 0 unless @mouse_available

    begin

      msg = "\0" * 28

      if $PeekMessage.call(msg, 0, WM_MOUSEWHEEL, WM_MOUSEWHEEL, 1) != 0

        wparam = msg[8, 4].unpack('L')[0]
        delta  =  (wparam >> 16) & 0xFFFF

        delta = delta > 32767 ? delta - 65536 : delta

        if delta > 0
          return 1
        elsif delta < 0
          return -1
        end
      end

      return 0
    rescue => e
      puts "[Mouse Input] Error checking scroll: #{e.message}"
      return 0
    end
  end

  def self.get_scroll_simple
    return 0 unless @mouse_available

    begin

      return 0
    rescue
      return 0
    end
  end
end

puts "[Mouse Input] Mouse input module loaded"
