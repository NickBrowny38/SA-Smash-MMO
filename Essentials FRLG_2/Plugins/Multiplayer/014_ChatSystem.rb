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
  MESSAGE_DISPLAY_TIME = 600
  CHAT_WIDTH = 450
  LINE_HEIGHT = 20

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
  end

  def add_message(username, text, color = nil)

    text_color = parse_color(color) || Color.new(255, 255, 255)

    @messages.push({
      username: username,
      text: text,
      timestamp: Graphics.frame_count,
      color: text_color
    })

    @messages.shift if @messages.length > MAX_MESSAGES

    @scroll_offset = 0 unless @input_active

    draw if @sprite
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
    @scroll_offset = [@scroll_offset + 1, @messages.length - VISIBLE_LINES].min
    @scroll_offset = [0, @scroll_offset].max
  end

  def scroll_down
    @scroll_offset ||= 0
    @scroll_offset = [@scroll_offset - 1, 0].max
  end

  def open_input
    return if @input_active
    @input_active = true
    @scroll_offset = 0

    pbOpenMultiplayerChat if defined?(pbOpenMultiplayerChat)

    @input_active = false
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

    return if @input_active || @scroll_offset > 0

    if @fade_messages
      current_frame  =  Graphics.frame_count
      @messages.reject! { |msg| current_frame - msg[:timestamp] > MESSAGE_DISPLAY_TIME * 2 }
    end
  end

  def initialize_sprite(viewport)
    return if @sprite
    @viewport = viewport
    @sprite = Sprite.new(@viewport)
    @sprite.bitmap = Bitmap.new(CHAT_WIDTH, VISIBLE_LINES * LINE_HEIGHT + 10)
    @sprite.z = 99999

    @sprite.x = 10
    @sprite.y = 10
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

    @sprite.visible = true
    @sprite.bitmap.clear if @sprite.bitmap

    visible_messages = get_visible_messages
    return if visible_messages.empty?

    bg_alpha = @input_active ? 200 : 140
    bg_height = [visible_messages.length * LINE_HEIGHT + 10, @sprite.bitmap.height].min

    (0...bg_height).each do |y|
      gradient_factor = y.to_f / bg_height

      r = (0 + (20 * gradient_factor)).to_i
      g  =  (0 + (20 * gradient_factor)).to_i
      b = (15 + (35 * gradient_factor)).to_i
      @sprite.bitmap.fill_rect(0, y, CHAT_WIDTH, 1, Color.new(r, g, b, bg_alpha))
    end

    @sprite.bitmap.fill_rect(0, 0, CHAT_WIDTH, 3, Color.new(100, 150, 255, 180))
    @sprite.bitmap.fill_rect(0, 3, CHAT_WIDTH, 1, Color.new(70, 120, 230, 140))

    @sprite.bitmap.fill_rect(0, bg_height - 3, CHAT_WIDTH, 3, Color.new(0, 0, 0, 200))
    @sprite.bitmap.fill_rect(0, bg_height - 4, CHAT_WIDTH, 1, Color.new(50, 100, 200, 100))

    @sprite.bitmap.fill_rect(0, 0, 2, bg_height, Color.new(80, 130, 240, 160))
    @sprite.bitmap.fill_rect(CHAT_WIDTH - 2, 0, 2, bg_height, Color.new(80, 130, 240, 160))

    pbSetSystemFont(@sprite.bitmap)
    @sprite.bitmap.font.size = 16

    visible_messages.reverse.each_with_index do |msg, index|

      y_pos = (bg_height - LINE_HEIGHT - 5) - (index * LINE_HEIGHT)
      break if y_pos < 5

      alpha = 255
      if @fade_messages && !@input_active && @scroll_offset == 0
        age = Graphics.frame_count - msg[:timestamp]
        if age > MESSAGE_DISPLAY_TIME
          fade_progress = (age - MESSAGE_DISPLAY_TIME).to_f / MESSAGE_DISPLAY_TIME
          alpha  =  (255 * (1.0 - fade_progress)).to_i
          alpha = [0, [255, alpha].min].max
        end
      end

      username_color  =  determine_username_color(msg[:username], alpha)
      message_color = msg[:color].clone
      message_color.alpha = alpha

      shadow_color = Color.new(0, 0, 0, alpha)
      x_offset = 8

      @sprite.bitmap.font.color  =  shadow_color
      @sprite.bitmap.draw_text(x_offset + 1, y_pos + 1, CHAT_WIDTH - 20, LINE_HEIGHT, msg[:username])

      @sprite.bitmap.font.color = username_color
      username_width = @sprite.bitmap.text_size(msg[:username]).width
      @sprite.bitmap.draw_text(x_offset, y_pos, CHAT_WIDTH - 20, LINE_HEIGHT, msg[:username])

      @sprite.bitmap.font.color = Color.new(200, 200, 200, alpha)
      @sprite.bitmap.draw_text(x_offset + username_width, y_pos, 20, LINE_HEIGHT, ':')

      @sprite.bitmap.font.color  =  shadow_color
      @sprite.bitmap.draw_text(x_offset + username_width + 12, y_pos + 1, CHAT_WIDTH - username_width - 30, LINE_HEIGHT, msg[:text])

      @sprite.bitmap.font.color = message_color
      @sprite.bitmap.draw_text(x_offset + username_width + 11, y_pos, CHAT_WIDTH - username_width - 30, LINE_HEIGHT, msg[:text])
    end

    if @scroll_offset > 0
      scroll_text = " SCROLLED (#{@scroll_offset} up) "
      scroll_bg_width = @sprite.bitmap.text_size(scroll_text).width + 10
      scroll_x = (CHAT_WIDTH - scroll_bg_width) / 2

      @sprite.bitmap.fill_rect(scroll_x, 2, scroll_bg_width, 18, Color.new(255, 200, 0, 200))
      @sprite.bitmap.fill_rect(scroll_x, 20, scroll_bg_width, 2, Color.new(200, 150, 0, 180))

      @sprite.bitmap.font.color = Color.new(0, 0, 0, 255)
      @sprite.bitmap.draw_text(scroll_x, 2, scroll_bg_width, 18, scroll_text, 1)
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
    start_index = [@messages.length - VISIBLE_LINES - @scroll_offset, 0].max
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
