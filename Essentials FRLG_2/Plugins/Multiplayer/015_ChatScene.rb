$multiplayer_chat_history ||= []

class Scene_MultiplayerChat
  MAX_VISIBLE_MESSAGES  =  15

  def initialize(initial_text = "")
    @chat = pbMultiplayerChat
    @input_text = initial_text
    @cursor_pos = initial_text.length

    @message_history = $multiplayer_chat_history
    @history_index = -1
    @current_draft = ''
  end

  def main
    @viewport  =  Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @done = false

    create_sprites

    10.times do      Graphics.update
      Input.update
    end

    Graphics.transition
    loop do      Graphics.update
      Input.update
      update
      break if @done
    end

    10.times do      Graphics.update
      Input.update
    end

    dispose_sprites

    10.times do      Input.update
    end
  end

  def create_sprites
    create_background
    create_message_display
    create_input_box
  end

  def create_background

    @bg_sprite  =  Sprite.new(@viewport)
    @bg_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @bg_sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))
    @bg_sprite.z = 0
  end

  def create_message_display

    @message_sprite = Sprite.new(@viewport)
    msg_height  =  Graphics.height - 80
    @message_sprite.bitmap = Bitmap.new(Graphics.width - 20, msg_height)
    @message_sprite.x = 10
    @message_sprite.y  =  10
    @message_sprite.z = 1

    draw_messages
  end

  def draw_messages
    return unless @message_sprite && @message_sprite.bitmap

    @message_sprite.bitmap.clear

    return unless @chat

    messages = @chat.instance_variable_get(:@messages) || []
    visible = messages.last(MAX_VISIBLE_MESSAGES)

    pbSetSystemFont(@message_sprite.bitmap)
    @message_sprite.bitmap.font.size = 18

    y  =  0
    visible.each do |msg|
      username = msg[:username] || ""
      text = msg[:text] || ""

      color = get_username_color(username)
      @message_sprite.bitmap.font.color = color
      @message_sprite.bitmap.draw_text(0, y, @message_sprite.bitmap.width, 24, username)

      @message_sprite.bitmap.font.color = Color.new(255, 255, 255)
      username_width = @message_sprite.bitmap.text_size(username).width + 10
      @message_sprite.bitmap.draw_text(username_width, y,
                                       @message_sprite.bitmap.width - username_width, 24, text)

      y += 24
    end
  end

  def get_username_color(username)
    case username.upcase
    when /\[ADMIN\]/
      Color.new(255, 85, 85)
    when /\[MOD\]/
      Color.new(85, 255, 85)
    when /\[SERVER\]/, /\[SYSTEM\]/
      Color.new(85, 255, 255)
    else
      hash  =  username.hash.abs
      Color.new(170 + (hash % 85), 170 + ((hash * 7) % 85), 170 + ((hash * 13) % 85))
    end
  end

  def create_input_box

    input_height = 40
    input_width = Graphics.width - 40

    @input_sprite = Sprite.new(@viewport)
    @input_sprite.bitmap = Bitmap.new(input_width, input_height)
    @input_sprite.x = 20
    @input_sprite.y = Graphics.height - input_height - 15
    @input_sprite.z = 2

    draw_input_box
  end

  def draw_input_box
    return unless @input_sprite && @input_sprite.bitmap

    bmp  =  @input_sprite.bitmap
    bmp.clear

    bmp.fill_rect(0, 0, bmp.width, bmp.height, Color.new(0, 0, 0, 200))

    bmp.fill_rect(0, 0, bmp.width, 2, Color.new(255, 255, 255, 100))
    bmp.fill_rect(0, bmp.height-2, bmp.width, 2, Color.new(0, 0, 0, 150))

    pbSetSystemFont(bmp)
    bmp.font.size = 18
    bmp.font.color = Color.new(255, 255, 255)

    text = @input_text || ""
    bmp.draw_text(10, 8, bmp.width - 20, 24, text)

    if @show_cursor
      cursor_x = 10
      if @cursor_pos && @cursor_pos > 0
        before_cursor = text[0...@cursor_pos] || ""
        cursor_x += bmp.text_size(before_cursor).width
      end
      bmp.fill_rect(cursor_x, 10, 2, 20, Color.new(255, 255, 255))
    end
  end

  def update
    update_cursor_blink
    handle_input
  end

  def update_cursor_blink
    @cursor_timer ||= 0
    @cursor_timer += 1

    if @cursor_timer >= 20
      @show_cursor = !@show_cursor
      @cursor_timer = 0
      draw_input_box
    end
  end

  def handle_input

    if Input.triggerex?(0x0D)
      send_message
      @done = true
      return
    end

    # Only ESC closes chat - NOT X key (Input::BACK) since X is needed for typing
    if Input.triggerex?(0x1B)  # ESC key only
      @done = true
      return
    end

    if Input.triggerex?(0x08)
      handle_backspace
      return
    end

    if Input.repeat?(Input::LEFT)
      @cursor_pos = [@cursor_pos - 1, 0].max
      @show_cursor = true
      @cursor_timer = 0
      draw_input_box
      return
    end

    if Input.repeat?(Input::RIGHT)
      @cursor_pos = [@cursor_pos + 1, @input_text.length].min
      @show_cursor = true
      @cursor_timer = 0
      draw_input_box
      return
    end

    if Input.trigger?(Input::UP)
      navigate_history_up
      return
    end

    if Input.trigger?(Input::DOWN)
      navigate_history_down
      return
    end

    char = get_character_input
    if char && @input_text.length < 200
      insert_character(char)
    end
  end

  def handle_backspace
    return if @cursor_pos == 0 || @input_text.empty?

    @input_text  =  @input_text[0...@cursor_pos-1] + @input_text[@cursor_pos..-1]
    @cursor_pos -= 1
    @cursor_pos = [@cursor_pos, 0].max
    draw_input_box
  end

  def insert_character(char)
    @input_text  =  @input_text[0...@cursor_pos] + char + @input_text[@cursor_pos..-1]
    @cursor_pos += 1
    draw_input_box
  end

  def get_character_input

    shift_held = false
    if defined?($GetKeyState)
      shift_held = ($GetKeyState.call(0x10) & 0x8000) != 0
    end

    special_keys = {
      0xBF => '/',
      0xBA => ';',
      0xDE => '\'',
      0xDB => '[',
      0xDD => ']',
      0xBC => ',',
      0xBE => '.',
      0xBD => '-',
      0xBB => '=',
      0xC0 => '`',
      0xDC => '\\'
    }

    if defined?($GetKeyState)
      special_keys.each do |vk_code, base_char|

        if ($GetKeyState.call(vk_code) & 0x8000) != 0

          @last_special_keys ||= {}
          if !@last_special_keys[vk_code]
            @last_special_keys[vk_code] = true
            char = shift_held ? shift_char(base_char) : base_char
            return char
          end
        else
          @last_special_keys[vk_code]  =  false if @last_special_keys
        end
      end
    end

    (0x20..0x7E).each do |key|
      if Input.triggerex?(key)
        char = key.chr

        if key >= 0x41 && key <= 0x5A

          char = shift_held ? char.upcase : char.downcase
        elsif shift_held

          char = shift_char(char)
        end

        return char
      end
    end

    nil
  end

  def shift_char(char)
    return char.upcase if char =~ /[a-z]/

    case char
    when '1' then '!'
    when '2' then '@'
    when '3' then '#'
    when '4' then '$'
    when '5' then '%'
    when '6' then '^'
    when '7' then '&'
    when '8' then '*'
    when '9' then '('
    when '0' then ')'
    when '-' then '_'
    when '=' then '+'
    when '[' then '{'
    when ']' then '}'
    when '\\' then '|'
    when ';' then ':'
    when '\'' then '"'
    when ',' then '<'
    when '.' then '>'
    when '/' then '?'
    when '`' then '~'
    else char
    end
  end

  def navigate_history_up
    return if @message_history.empty?

    if @history_index == -1
      @current_draft  =  @input_text
    end

    @history_index = [@history_index + 1, @message_history.length - 1].min

    @input_text = @message_history[@message_history.length - 1 - @history_index].dup
    @cursor_pos = @input_text.length
    @show_cursor = true
    @cursor_timer = 0
    draw_input_box
  end

  def navigate_history_down
    return if @history_index == -1

    @history_index -= 1

    if @history_index == -1

      @input_text = @current_draft
    else

      @input_text  =  @message_history[@message_history.length - 1 - @history_index].dup
    end

    @cursor_pos = @input_text.length
    @show_cursor = true
    @cursor_timer = 0
    draw_input_box
  end

  def send_message
    return if @input_text.empty?

    if defined?(ChatFilter)
      filtered_text = ChatFilter.filter(@input_text)
      if filtered_text.nil?

        pbMultiplayerChat.add_message("[SYSTEM]", "Message blocked by chat filter.", "RED") if defined?(pbMultiplayerChat)
        @input_text  =  ""
        @cursor_pos = 0
        return
      end
      @input_text = filtered_text
    end

    pbMultiplayerClient.send_chat_message(@input_text) if pbMultiplayerConnected?

    @message_history << @input_text.dup

    @message_history.shift if @message_history.length > 50

    @history_index = -1
    @current_draft  =  ""

    @input_text = ""
    @cursor_pos = 0
  end

  def dispose_sprites
    if @bg_sprite
      @bg_sprite.bitmap.dispose if @bg_sprite.bitmap
      @bg_sprite.dispose
    end

    if @message_sprite
      @message_sprite.bitmap.dispose if @message_sprite.bitmap
      @message_sprite.dispose
    end

    if @input_sprite
      @input_sprite.bitmap.dispose if @input_sprite.bitmap
      @input_sprite.dispose
    end

    @viewport.dispose if @viewport
  end
end

def pbOpenMultiplayerChat(initial_text = "")
  return unless pbMultiplayerConnected?
  scene = Scene_MultiplayerChat.new(initial_text)
  scene.main
end
