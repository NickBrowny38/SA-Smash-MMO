module ChatFilter
  BLOCKED_WORDS = [
    /n[i1!]gg[e3a@][r]*[sz]*/i,
    /n[i1!]gg[o0a@]/i,
    /ch[i1!]nk/i,
    /sp[i1!]c/i,
    /k[i1!]k[e3]/i,
    /w[e3]tb[a@]ck/i,
    /g[o0][o0]k/i,
    /r[a@]gh[e3][a@]d/i,

    /f[a@]gg[o0]t/i,
    /f[a@]g[sz]/i,
    /tr[a@]nn[yi1]/i,

    /r[a@]p[e3][^r]/i,
    /r[a@]p[i1!]st/i,
    /p[e3]d[o0]/i,
    /ch[i1!]ld\s*p[o0]rn/i,
    /m[o0]l[e3]st/i,

    /n[a@]z[i1!]/i,
    /h[i1!]tl[e3]r/i,
    /g[e3]n[o0]c[i1!]d[e3]/i,
    /lynch/i,
    /sl[a@]v[e3]ry/i,
    /h[o0]l[o0]c[a@]ust/i,

    /k[yi1]ll\s*y[o0]urs[e3]lf/i,
    /k\s*y\s*s/i,
    /su[i1!]c[i1!]d[e3]/i,
    /d[i1!][e3]\s*[i1!]n\s*[a@]/i,

    /r[e3]t[a@]rd/i,
    /r[e3]t[a@]rd[e3]d/i,
    /[a@]ut[i1!]st[i1!]c/i,
    /m[o0]ng[o0]l[o0]id/i
  ]

  def self.filter(text)

    BLOCKED_WORDS.each do |pattern|
      if text.match?(pattern)
        return nil
      end
    end

    return text
  end

  def self.is_blocked?(text)
    filter(text).nil?
  end
end

class MultiplayerChat
  MAX_MESSAGES  =  100
  VISIBLE_LINES = 10
  MESSAGE_DISPLAY_TIME = 1000  # Increased from 600 to last longer
  CHAT_WIDTH = 450
  LINE_HEIGHT = 20
  MAX_MESSAGE_LENGTH = 200  # Maximum characters per message

  # History mode settings (like Minecraft when pressing T)
  HISTORY_VISIBLE_LINES = 20
  HISTORY_HEIGHT_BUFFER = 60  # Extra space from bottom of screen

  COMMANDS = [:help, :msg, :m, :w, :tell, :reply, :r, :online, :who, :list,
              :time, :spawn, :home, :sethome, :ping, :stats, :badge, :badges,
              :playtime, :ignore, :unignore, :mute, :unmute, :kick, :warn,
              :ban, :unban, :give, :tp, :teleport, :summon, :setspawn, :settime,
              :broadcast, :announce, :heal, :setmoney, :maintenance]

  def initialize
    @messages = []
    @input_active = false
    @sprites = {}
    @scroll_offset = 0
    @chat_hidden  =  false
    @fade_messages = true
    @history_mode = false  # New: expanded history mode
  end

  def add_message(username, text, color = nil)
    # Truncate message if too long
    text = text[0...MAX_MESSAGE_LENGTH] if text.length > MAX_MESSAGE_LENGTH

    text_color = parse_color(color) || Color.new(255, 255, 255)

    # Check if message needs wrapping
    wrapped_lines = wrap_text(text, username)

    if wrapped_lines.length == 1
      # Single line message
      @messages.push({
        username: username,
        text: text,
        timestamp: Graphics.frame_count,
        color: text_color
      })
    else
      # Multi-line message - add first line with username, rest without
      wrapped_lines.each_with_index do |line, index|
        @messages.push({
          username: (index == 0 ? username : ""),
          text: line,
          timestamp: Graphics.frame_count,
          color: text_color
        })
      end
    end

    @messages.shift if @messages.length > MAX_MESSAGES

    @scroll_offset = 0 unless @input_active

    # Ensure sprite is visible when new messages arrive
    if @sprite
      @sprite.visible = true
      draw
    end
  end

  def wrap_text(text, username)
    return [text] if text.empty?

    # Calculate available width for text (total width - margins - username width)
    # We need to check actual username width if we have a sprite
    available_width = CHAT_WIDTH - 40  # Base margins and padding

    if @sprite && @sprite.bitmap
      pbSetSystemFont(@sprite.bitmap)
      @sprite.bitmap.font.size = 16
      username_width = @sprite.bitmap.text_size(username + ": ").width
      available_width = CHAT_WIDTH - username_width - 30
    end

    lines = []
    current_line = ""
    words = text.split(' ')

    words.each do |word|
      test_line = current_line.empty? ? word : "#{current_line} #{word}"

      # Check if adding this word exceeds width
      if @sprite && @sprite.bitmap
        test_width = @sprite.bitmap.text_size(test_line).width
        if test_width > available_width && !current_line.empty?
          lines << current_line
          current_line = word
        else
          current_line = test_line
        end
      else
        # Fallback: estimate ~60 characters per line
        if test_line.length > 60 && !current_line.empty?
          lines << current_line
          current_line = word
        else
          current_line = test_line
        end
      end
    end

    lines << current_line unless current_line.empty?
    lines
  end

  def parse_color(color_name)
    return nil unless color_name

    case color_name.to_s.upcase
    when 'RED'
      Color.new(255, 85, 85)
    when 'YELLOW'
      Color.new(255, 255, 85)
    when "GREEN"
      Color.new(85, 255, 85)
    when 'BLUE'
      Color.new(85, 170, 255)
    when "MAGENTA"
      Color.new(255, 85, 255)
    when "CYAN"
      Color.new(85, 255, 255)
    when 'ORANGE'
      Color.new(255, 170, 0)
    when "WHITE"
      Color.new(255, 255, 255)
    when "GRAY", "GREY"
      Color.new(170, 170, 170)
    else
      Color.new(255, 255, 255)
    end
  end

  def toggle_chat
    @chat_hidden  =  !@chat_hidden
    @hide_time = Graphics.frame_count if @chat_hidden

    if @sprite
      if @chat_hidden

        @sprite.visible  =  false
        @sprite.bitmap.clear if @sprite.bitmap
      else

        @sprite.visible = true
        draw
      end
    end
  end

  def scroll_up
    return if @messages.empty?
    @scroll_offset ||= 0
    current_visible_lines = (@history_mode || @input_active) ? HISTORY_VISIBLE_LINES : VISIBLE_LINES
    @scroll_offset = [@scroll_offset + 1, @messages.length - current_visible_lines].min
    @scroll_offset = [0, @scroll_offset].max
  end

  def scroll_down
    @scroll_offset ||= 0
    @scroll_offset = [@scroll_offset - 1, 0].max
  end

  def toggle_history_mode
    @history_mode = !@history_mode
    @scroll_offset = 0 unless @history_mode
    draw if @sprite
  end

  def open_input
    return if @input_active
    @input_active = true
    @history_mode = true  # Enable history mode when opening input
    @scroll_offset = 0

    pbOpenMultiplayerChat if defined?(pbOpenMultiplayerChat)

    @input_active = false
    @history_mode = false  # Disable history mode when closing input
  end

  def input_with_tab_completion
    current_input  =  ""
    tab_suggestions = []
    tab_index  =  0
    last_tab_time = 0

    text  =  pbKeyboardInput("Chat:", 200, "", 0x54)
    return nil unless text

    if text.start_with?('/')

      parts  =  text.split(' ')
      command_part = parts[0][1..-1].downcase

      matches  =  COMMANDS.select { |cmd| cmd.to_s.start_with?(command_part) }

      if matches.length == 1

        text = "/#{matches[0]} #{parts[1..-1].join(' ')}".strip
      elsif matches.length > 1 && command_part.length > 0

        suggestion_text = "Suggestions: " + matches.map { |cmd| "/#{cmd}" }.join(", ")
        add_message("[SYSTEM]", suggestion_text, "YELLOW")
      end
    end

    return text
  end

  def update

    if defined?(MouseInput)
      scroll_delta = MouseInput.update_scroll
      if scroll_delta > 0
        scroll_up
      elsif scroll_delta < 0
        scroll_down
      end
    end

    if defined?(Input.scroll_v)
      if Input.scroll_v > 0
        scroll_up
      elsif Input.scroll_v < 0
        scroll_down
      end
    end

    # In Minecraft, messages are NEVER deleted from history
    # They only fade from view, but remain scrollable
    # So we don't reject old messages anymore
  end

  def initialize_sprite(viewport)
    return if @sprite
    @viewport = viewport
    @sprite = Sprite.new(@viewport)
    # Create larger bitmap to accommodate history mode
    @sprite.bitmap = Bitmap.new(CHAT_WIDTH, HISTORY_VISIBLE_LINES * LINE_HEIGHT + 10)
    @sprite.z = 99999

    # Position at bottom-left instead of top-left
    @sprite.x = 10
    @sprite.y = Graphics.height - (VISIBLE_LINES * LINE_HEIGHT + 10) - 10
  end

  def draw
    return unless @sprite

    if @chat_hidden
      @sprite.visible = false
      return
    end

    if @messages.empty?
      @sprite.visible = false
      return
    end

    visible_messages = get_visible_messages

    # Only hide if no messages at all
    if visible_messages.empty?
      @sprite.visible = false
      return
    end

    @sprite.visible = true
    @sprite.bitmap.clear if @sprite.bitmap

    # Use history mode settings when active (more lines visible)
    current_visible_lines = (@history_mode || @input_active) ? HISTORY_VISIBLE_LINES : VISIBLE_LINES

    # In normal mode (not history/input), count messages that should show background
    # This makes the background match the actual visible content like Minecraft
    actual_message_count = visible_messages.length

    if !@history_mode && !@input_active && @scroll_offset == 0
      current_frame = Graphics.frame_count
      # Count messages that haven't started fading yet OR are still partially visible
      actual_message_count = visible_messages.count { |msg|
        age = current_frame - msg[:timestamp]
        # Show background for messages that are still visible (not completely faded)
        age < MESSAGE_DISPLAY_TIME * 2
      }

      # If all messages have completely faded, hide the chat
      if actual_message_count == 0
        @sprite.visible = false
        return
      end
    end

    # Background height based on actual visible messages
    bg_height = [actual_message_count * LINE_HEIGHT + 10, current_visible_lines * LINE_HEIGHT + 10].min

    # Adjust Y position based on mode
    if @history_mode || @input_active
      @sprite.y = Graphics.height - (HISTORY_VISIBLE_LINES * LINE_HEIGHT + 10) - HISTORY_HEIGHT_BUFFER
    else
      # In normal mode, position based on actual message count for smooth appearance
      @sprite.y = Graphics.height - bg_height - 10
    end

    # Background alpha - always start fresh, don't carry over fade state
    bg_alpha = (@input_active || @history_mode) ? 200 : 140

    # In normal mode, fade background based on NEWEST (most recent) message's fade state
    # This way fresh messages always show full opacity background
    if !@history_mode && !@input_active && @scroll_offset == 0 && !visible_messages.empty?
      current_frame = Graphics.frame_count
      # Find the NEWEST message (last in array) to determine background fade
      newest_msg = visible_messages.last
      age = current_frame - newest_msg[:timestamp]

      # Only fade if the newest message is fading
      if age > MESSAGE_DISPLAY_TIME
        fade_progress = (age - MESSAGE_DISPLAY_TIME).to_f / MESSAGE_DISPLAY_TIME
        fade_progress = [fade_progress, 1.0].min  # Cap at 1.0
        # Fade background proportionally
        bg_alpha = (bg_alpha * (1.0 - fade_progress)).to_i
        bg_alpha = [bg_alpha, 0].max
      end
    end

    # Draw gradient background only for the actual height needed
    (0...bg_height).each do |y|
      gradient_factor = y.to_f / bg_height

      r = (0 + (20 * gradient_factor)).to_i
      g  =  (0 + (20 * gradient_factor)).to_i
      b = (15 + (35 * gradient_factor)).to_i
      @sprite.bitmap.fill_rect(0, y, CHAT_WIDTH, 1, Color.new(r, g, b, bg_alpha))
    end

    # Borders with fading alpha - ensure minimum visibility
    top_border_alpha = [[180 * bg_alpha / 140, 180].min, 10].max
    side_border_alpha = [[160 * bg_alpha / 140, 160].min, 10].max
    bottom_border_alpha = [[200 * bg_alpha / 140, 200].min, 10].max

    @sprite.bitmap.fill_rect(0, 0, CHAT_WIDTH, 3, Color.new(100, 150, 255, top_border_alpha))
    @sprite.bitmap.fill_rect(0, 3, CHAT_WIDTH, 1, Color.new(70, 120, 230, bg_alpha))

    @sprite.bitmap.fill_rect(0, bg_height - 3, CHAT_WIDTH, 3, Color.new(0, 0, 0, bottom_border_alpha))
    @sprite.bitmap.fill_rect(0, bg_height - 4, CHAT_WIDTH, 1, Color.new(50, 100, 200, [[100 * bg_alpha / 140, 100].min, 10].max))

    @sprite.bitmap.fill_rect(0, 0, 2, bg_height, Color.new(80, 130, 240, side_border_alpha))
    @sprite.bitmap.fill_rect(CHAT_WIDTH - 2, 0, 2, bg_height, Color.new(80, 130, 240, side_border_alpha))

    pbSetSystemFont(@sprite.bitmap)
    @sprite.bitmap.font.size = 16

    visible_messages.reverse.each_with_index do |msg, index|

      y_pos = (bg_height - LINE_HEIGHT - 5) - (index * LINE_HEIGHT)
      break if y_pos < 5

      # Minecraft behavior: messages fade ONLY when not in history/input mode and not scrolling
      alpha = 255
      if !@history_mode && !@input_active && @scroll_offset == 0
        age = Graphics.frame_count - msg[:timestamp]
        if age > MESSAGE_DISPLAY_TIME
          fade_progress = (age - MESSAGE_DISPLAY_TIME).to_f / MESSAGE_DISPLAY_TIME
          alpha  =  (255 * (1.0 - fade_progress)).to_i
          alpha = [0, [255, alpha].min].max
        end
      end

      message_color = msg[:color].clone
      message_color.alpha = alpha
      shadow_color = Color.new(0, 0, 0, alpha)
      x_offset = 8

      # Handle wrapped lines (empty username means continuation)
      if msg[:username].empty?
        # Continuation line - no username, just indented text
        text_x_offset = x_offset + 8  # Small indent for wrapped lines

        @sprite.bitmap.font.color = shadow_color
        @sprite.bitmap.draw_text(text_x_offset + 1, y_pos + 1, CHAT_WIDTH - text_x_offset - 20, LINE_HEIGHT, msg[:text])

        @sprite.bitmap.font.color = message_color
        @sprite.bitmap.draw_text(text_x_offset, y_pos, CHAT_WIDTH - text_x_offset - 20, LINE_HEIGHT, msg[:text])
      else
        # Normal line with username
        username_color = determine_username_color(msg[:username], alpha)

        @sprite.bitmap.font.color = shadow_color
        @sprite.bitmap.draw_text(x_offset + 1, y_pos + 1, CHAT_WIDTH - 20, LINE_HEIGHT, msg[:username])

        @sprite.bitmap.font.color = username_color
        username_width = @sprite.bitmap.text_size(msg[:username]).width
        @sprite.bitmap.draw_text(x_offset, y_pos, CHAT_WIDTH - 20, LINE_HEIGHT, msg[:username])

        @sprite.bitmap.font.color = Color.new(200, 200, 200, alpha)
        @sprite.bitmap.draw_text(x_offset + username_width, y_pos, 20, LINE_HEIGHT, ':')

        @sprite.bitmap.font.color = shadow_color
        @sprite.bitmap.draw_text(x_offset + username_width + 12, y_pos + 1, CHAT_WIDTH - username_width - 30, LINE_HEIGHT, msg[:text])

        @sprite.bitmap.font.color = message_color
        @sprite.bitmap.draw_text(x_offset + username_width + 11, y_pos, CHAT_WIDTH - username_width - 30, LINE_HEIGHT, msg[:text])
      end
    end

    # Show scroll indicator
    if @scroll_offset > 0
      scroll_text = " SCROLLED (#{@scroll_offset} up) "
      scroll_bg_width = @sprite.bitmap.text_size(scroll_text).width + 10
      scroll_x = (CHAT_WIDTH - scroll_bg_width) / 2

      @sprite.bitmap.fill_rect(scroll_x, 2, scroll_bg_width, 18, Color.new(255, 200, 0, 200))
      @sprite.bitmap.fill_rect(scroll_x, 20, scroll_bg_width, 2, Color.new(200, 150, 0, 180))

      @sprite.bitmap.font.color = Color.new(0, 0, 0, 255)
      @sprite.bitmap.draw_text(scroll_x, 2, scroll_bg_width, 18, scroll_text, 1)
    end

    # Show history mode indicator
    if @history_mode && !@input_active
      history_text = " HISTORY MODE (Press Y to close) "
      history_bg_width = @sprite.bitmap.text_size(history_text).width + 10
      history_x = (CHAT_WIDTH - history_bg_width) / 2

      @sprite.bitmap.fill_rect(history_x, bg_height - 20, history_bg_width, 18, Color.new(100, 150, 255, 200))
      @sprite.bitmap.fill_rect(history_x, bg_height - 22, history_bg_width, 2, Color.new(70, 120, 230, 180))

      @sprite.bitmap.font.color = Color.new(255, 255, 255, 255)
      @sprite.bitmap.draw_text(history_x, bg_height - 20, history_bg_width, 18, history_text, 1)
    end

    if @chat_hidden && defined?(@hide_time) && Graphics.frame_count - @hide_time < 60
      hide_text = "[CHAT HIDDEN - Press H to show]"
      @sprite.bitmap.font.color = Color.new(255, 255, 100, 200)
      @sprite.bitmap.draw_text(0, CHAT_WIDTH / 2, CHAT_WIDTH, LINE_HEIGHT, hide_text, 1)
    end
  end

  def determine_username_color(username, alpha)
    case username.upcase
    when /\[ADMIN\]/
      Color.new(255, 50, 50, alpha)
    when /\[MOD\]/
      Color.new(255, 100, 100, alpha)
    when /\[SERVER\]/, /\[SYSTEM\]/
      Color.new(100, 200, 255, alpha)
    when /\[ANNOUNCEMENT\]/
      Color.new(255, 200, 50, alpha)
    else

      hash = username.hash.abs
      hue = hash % 360

      Color.new(
        200 + (hash % 55),
        150 + ((hash * 7) % 105),
        100 + ((hash * 13) % 155),
        alpha
      )
    end
  end

  def get_visible_messages
    # Use more lines when in history mode or input active
    current_visible_lines = (@history_mode || @input_active) ? HISTORY_VISIBLE_LINES : VISIBLE_LINES

    start_index = [@messages.length - current_visible_lines - @scroll_offset, 0].max
    end_index = [@messages.length - @scroll_offset, @messages.length].min

    return [] if start_index >= end_index

    @messages[start_index...end_index]
  end

  def dispose
    if @sprite
      @sprite.bitmap.dispose if @sprite.bitmap
      @sprite.dispose
      @sprite  =  nil
    end
    @viewport = nil
  end

  def visible?
    !@messages.empty? && !@chat_hidden
  end
end

$multiplayer_chat = nil

def pbMultiplayerChat
  $multiplayer_chat ||= MultiplayerChat.new
  return $multiplayer_chat
end
