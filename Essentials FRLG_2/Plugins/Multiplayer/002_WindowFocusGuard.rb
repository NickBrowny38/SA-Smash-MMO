unless defined?(pbWindowHasFocus?)
  def pbWindowHasFocus?
    begin
      if defined?(Win32API)
        get_foreground_window = Win32API.new('user32', 'GetForegroundWindow', [], 'L')
        get_window_thread = Win32API.new('user32', 'GetWindowThreadProcessId', ['L', 'P'], 'L')
        get_current_process = Win32API.new('kernel32', 'GetCurrentProcessId', [], 'L')

        foreground_window = get_foreground_window.call
        return true if foreground_window == 0

        process_id = [0].pack('L')
        get_window_thread.call(foreground_window, process_id)
        foreground_process_id = process_id.unpack('L')[0]
        current_process_id = get_current_process.call

        return foreground_process_id == current_process_id
      end
    rescue
      return true
    end
    return true
  end
end

module Input
  class << self
    unless method_defined?(:press_without_focus_check?)
      alias press_without_focus_check? press?
      alias trigger_without_focus_check? trigger?
      alias repeat_without_focus_check? repeat?
      alias release_without_focus_check? release?
      alias count_without_focus_check? count
      alias dir4_without_focus_check dir4
      alias dir8_without_focus_check dir8
    end

    def press?(key)
      return false unless pbWindowHasFocus?
      return press_without_focus_check?(key)
    end

    def trigger?(key)
      return false unless pbWindowHasFocus?
      return trigger_without_focus_check?(key)
    end

    def repeat?(key)
      return false unless pbWindowHasFocus?
      return repeat_without_focus_check?(key)
    end

    def release?(key)
      return false unless pbWindowHasFocus?
      return release_without_focus_check?(key)
    end

    def count(key)
      return 0 unless pbWindowHasFocus?
      return count_without_focus_check?(key)
    end

    def dir4
      return 0 unless pbWindowHasFocus?
      return dir4_without_focus_check
    end

    def dir8
      return 0 unless pbWindowHasFocus?
      return dir8_without_focus_check
    end

    if method_defined?(:triggerex?)
      unless method_defined?(:triggerex_without_focus_check?)
        alias triggerex_without_focus_check? triggerex?
      end

      def triggerex?(key)
        return false unless pbWindowHasFocus?
        return triggerex_without_focus_check?(key)
      end
    end
  end
end

puts 'Window focus guard loaded - input will be blocked when game window is not focused'
