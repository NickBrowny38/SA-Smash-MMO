module Input
  TAB = 9

  B_KEY = 66

  R_KEY = 82

  class << self
    unless method_defined?(:multiplayer_press?)
      alias multiplayer_press? press?
    end

    def press?(button)
      if button == TAB || button == B_KEY || button == R_KEY
        return false unless multiplayer_window_focused?
      end

      case button
      when TAB
        return GetAsyncKeyState.call(0x09) & 0x8000 != 0
      when B_KEY
        return GetAsyncKeyState.call(0x42) & 0x8000 != 0
      when R_KEY
        return GetAsyncKeyState.call(0x52) & 0x8000 != 0
      else
        return multiplayer_press?(button)
      end
    end

    unless method_defined?(:multiplayer_trigger?)
      alias multiplayer_trigger? trigger?
    end

    def trigger?(button)

      if button == TAB || button == B_KEY || button == R_KEY
        return false unless multiplayer_window_focused?
      end

      case button
      when TAB, B_KEY, R_KEY

        @previous_states ||= {}
        result = press?(button) && !@previous_states[button]
        @previous_states[button] = press?(button)
        return result
      else

        return false if @in_multiplayer_trigger
        begin
          @in_multiplayer_trigger = true
          return multiplayer_trigger?(button)
        ensure
          @in_multiplayer_trigger = false
        end
      end
    end
  end

  @previous_states = {}
end

GetAsyncKeyState = Win32API.new('user32', 'GetAsyncKeyState', 'i', 'i')
GetForegroundWindow  =  Win32API.new('user32', 'GetForegroundWindow', [], 'l')
FindWindowEx  =  Win32API.new('user32', 'FindWindowEx', 'llpp', 'l')
GetWindowText = Win32API.new('user32', 'GetWindowText', 'lpl', 'l')
GetWindowThreadProcessId  =  Win32API.new('user32', 'GetWindowThreadProcessId', 'lp', 'l')
GetCurrentProcessId = Win32API.new('kernel32', 'GetCurrentProcessId', [], 'l')

def multiplayer_window_focused?
  begin

    fg_window = GetForegroundWindow.call
    return true if fg_window == 0

    process_id_buffer = [0].pack('L')
    GetWindowThreadProcessId.call(fg_window, process_id_buffer)
    fg_process_id = process_id_buffer.unpack('L')[0]

    our_process_id  =  GetCurrentProcessId.call

    return fg_process_id == our_process_id
  rescue => e

    puts "[MULTIPLAYER] Window focus check error: #{e.message}"
    return true
  end
end
