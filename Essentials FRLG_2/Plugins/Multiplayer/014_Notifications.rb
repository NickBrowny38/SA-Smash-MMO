class MultiplayerNotification
  attr_reader :message
  attr_reader :time_left

  def initialize(message, duration = 3.0)
    @message = message
    @duration = duration
    @time_left = duration
    @alpha = 0
    @fade_in_time = 0.3
    @fade_out_time = 0.5
  end

  def update(delta_time)
    @time_left -= delta_time

    if @time_left > @duration - @fade_in_time
      @alpha = ((@duration - @time_left) / @fade_in_time * 255).to_i
    elsif @time_left < @fade_out_time
      @alpha  =  ((@time_left / @fade_out_time) * 255).to_i
    else
      @alpha = 255
    end

    @alpha  =  [[0, @alpha].max, 255].min
  end

  def done?
    @time_left <= 0
  end

  def alpha
    @alpha
  end
end

class MultiplayerNotificationManager
  MAX_VISIBLE_NOTIFICATIONS = 4

  def initialize
    @notifications = []
    @sprite = nil
    @viewport = nil
    @last_update_time = Time.now
  end

  def add_notification(message, duration = 3.0)

    if @notifications.any? { |n| n.message == message }
      puts "[NOTIFY] Skipping duplicate notification: #{message}"
      return
    end

    @notifications << MultiplayerNotification.new(message, duration)

    while @notifications.length > MAX_VISIBLE_NOTIFICATIONS
      @notifications.shift
      puts "[NOTIFY] Removed oldest notification (max limit: #{MAX_VISIBLE_NOTIFICATIONS})"
    end
  end

  def update
    return if @notifications.empty?

    unless @last_update_time
      @last_update_time = Time.now
      return
    end

    current_time = Time.now
    delta_time  =  current_time - @last_update_time
    @last_update_time  =  current_time

    delta_time = [delta_time, 0.1].min

    @notifications.each { |n| n.update(delta_time) }

    @notifications.delete_if { |n| n.done? }
  end

  def draw
    if @notifications.empty?

      @sprite.visible = false if @sprite
      return
    end

    unless @sprite
      width = Graphics.width > 0 ? Graphics.width : 512
      height = Graphics.height > 0 ? Graphics.height : 384
      @sprite = Sprite.new(nil)
      @sprite.bitmap  =  Bitmap.new(width, height)
      @sprite.z = 999999
      @sprite.visible = true
      @sprite.x = 0
      @sprite.y = 0
    end

    @sprite.visible = true

    @sprite.bitmap.clear

    screen_height = Graphics.height > 0 ? Graphics.height : 384
    screen_width = Graphics.width > 0 ? Graphics.width : 512
    y_offset = screen_height - 60

    @notifications.reverse.each_with_index do |notification, index|

      text_width  =  400
      text_height = 40
      x = (screen_width - text_width) / 2
      y = y_offset - (index * 50)

      next if y < -50

      bg_color = Color.new(0, 0, 0, (notification.alpha * 0.7).to_i)
      @sprite.bitmap.fill_rect(x, y, text_width, text_height, bg_color)

      border_color = Color.new(255, 255, 255, notification.alpha)
      @sprite.bitmap.fill_rect(x, y, text_width, 2, border_color)
      @sprite.bitmap.fill_rect(x, y + text_height - 2, text_width, 2, border_color)
      @sprite.bitmap.fill_rect(x, y, 2, text_height, border_color)
      @sprite.bitmap.fill_rect(x + text_width - 2, y, 2, text_height, border_color)

      pbSetSystemFont(@sprite.bitmap) if defined?(pbSetSystemFont)
      @sprite.bitmap.font.size = 20
      @sprite.bitmap.font.color = Color.new(255, 255, 255, notification.alpha)
      @sprite.bitmap.draw_text(x + 10, y + 8, text_width - 20, 24, notification.message, 1)
    end
  end

  def dispose
    if @sprite
      @sprite.bitmap.dispose if @sprite.bitmap
      @sprite.dispose
      @sprite  =  nil
    end
  end
end

$multiplayer_notifications = nil

def pbInitMultiplayerNotifications
  $multiplayer_notifications ||= MultiplayerNotificationManager.new
end

def pbMultiplayerNotify(message, duration  =  3.0)
  pbInitMultiplayerNotifications unless $multiplayer_notifications
  $multiplayer_notifications.add_notification(message, duration) if $multiplayer_notifications
end

pbInitMultiplayerNotifications
