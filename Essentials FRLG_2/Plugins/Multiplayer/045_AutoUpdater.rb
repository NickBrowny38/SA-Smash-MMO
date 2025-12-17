# Enhanced Auto-Updater System for Pokemon FRLG MMO
# Features: Progress bar UI, full game updates, automatic detection

class UpdateProgressUI
  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 100001
    @sprites = {}
    @progress = 0
    @total = 100
    @status = "Initializing..."

    create_ui
  end

  def create_ui
    # Dark overlay background
    @sprites[:overlay] = Sprite.new(@viewport)
    @sprites[:overlay].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites[:overlay].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 220))

    # Main panel
    panel_w = 550
    panel_h = 220
    @panel_x = (Graphics.width - panel_w) / 2
    @panel_y = (Graphics.height - panel_h) / 2

    @sprites[:panel] = Sprite.new(@viewport)
    @sprites[:panel].bitmap = Bitmap.new(panel_w, panel_h)
    @sprites[:panel].x = @panel_x
    @sprites[:panel].y = @panel_y
    draw_panel

    # Title text
    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(panel_w - 40, 50)
    @sprites[:title].x = @panel_x + 20
    @sprites[:title].y = @panel_y + 15
    draw_title("Updating Game")

    # Status text
    @sprites[:status] = Sprite.new(@viewport)
    @sprites[:status].bitmap = Bitmap.new(panel_w - 40, 35)
    @sprites[:status].x = @panel_x + 20
    @sprites[:status].y = @panel_y + 70

    # Progress bar background
    @bar_x = @panel_x + 25
    @bar_y = @panel_y + 120
    @bar_w = panel_w - 50
    @bar_h = 35

    @sprites[:bar_bg] = Sprite.new(@viewport)
    @sprites[:bar_bg].bitmap = Bitmap.new(@bar_w, @bar_h)
    @sprites[:bar_bg].x = @bar_x
    @sprites[:bar_bg].y = @bar_y
    draw_bar_background

    # Progress bar fill
    @sprites[:bar_fill] = Sprite.new(@viewport)
    @sprites[:bar_fill].bitmap = Bitmap.new(@bar_w - 6, @bar_h - 6)
    @sprites[:bar_fill].x = @bar_x + 3
    @sprites[:bar_fill].y = @bar_y + 3

    # Progress percentage text
    @sprites[:percent] = Sprite.new(@viewport)
    @sprites[:percent].bitmap = Bitmap.new(panel_w - 40, 30)
    @sprites[:percent].x = @panel_x + 20
    @sprites[:percent].y = @panel_y + 165

    update_display
  end

  def draw_panel
    bmp = @sprites[:panel].bitmap
    w, h = bmp.width, bmp.height

    # Outer glow/border
    bmp.fill_rect(0, 0, w, h, Color.new(80, 150, 255, 200))
    # Main background
    bmp.fill_rect(3, 3, w - 6, h - 6, Color.new(25, 35, 55))
    # Header gradient
    for i in 0...60
      alpha = 120 - (i * 2)
      bmp.fill_rect(3, 3 + i, w - 6, 1, Color.new(60, 100, 160, alpha))
    end
    # Bottom accent
    bmp.fill_rect(3, h - 8, w - 6, 2, Color.new(80, 150, 255, 100))
  end

  def draw_title(text)
    bmp = @sprites[:title].bitmap
    bmp.clear
    pbSetSystemFont(bmp)
    bmp.font.size = 32
    bmp.font.bold = true
    # Shadow
    bmp.font.color = Color.new(0, 0, 0, 150)
    bmp.draw_text(2, 2, bmp.width, 50, text, 1)
    # Main text
    bmp.font.color = Color.new(255, 255, 255)
    bmp.draw_text(0, 0, bmp.width, 50, text, 1)
  end

  def draw_bar_background
    bmp = @sprites[:bar_bg].bitmap
    # Outer border
    bmp.fill_rect(0, 0, bmp.width, bmp.height, Color.new(60, 80, 120))
    # Inner dark
    bmp.fill_rect(2, 2, bmp.width - 4, bmp.height - 4, Color.new(15, 20, 30))
  end

  def set_status(text)
    @status = text
    update_display
  end

  def set_progress(current, total)
    @progress = current
    @total = [total, 1].max
    update_display
  end

  def update_display
    # Update status text
    bmp = @sprites[:status].bitmap
    bmp.clear
    pbSetSystemFont(bmp)
    bmp.font.size = 18
    bmp.font.color = Color.new(180, 200, 230)
    bmp.draw_text(0, 0, bmp.width, 35, @status, 1)

    # Update progress bar
    percent = [(@progress.to_f / @total.to_f * 100).to_i, 100].min
    fill_bmp = @sprites[:bar_fill].bitmap
    fill_bmp.clear

    fill_w = ((fill_bmp.width * percent) / 100).to_i
    if fill_w > 0
      # Gradient fill from green to bright green
      for x in 0...fill_w
        ratio = x.to_f / fill_bmp.width
        r = (50 + ratio * 50).to_i
        g = (180 + ratio * 75).to_i
        b = (50 + ratio * 30).to_i
        fill_bmp.fill_rect(x, 0, 1, fill_bmp.height, Color.new(r, g, b))
      end
      # Shine effect on top
      for y in 0...(fill_bmp.height / 3)
        alpha = 80 - (y * 8)
        fill_bmp.fill_rect(0, y, fill_w, 1, Color.new(255, 255, 255, alpha)) if alpha > 0
      end
    end

    # Update percentage text
    pct_bmp = @sprites[:percent].bitmap
    pct_bmp.clear
    pbSetSystemFont(pct_bmp)
    pct_bmp.font.size = 16
    pct_bmp.font.color = Color.new(150, 170, 200)

    if @total > 1024 * 1024
      current_mb = (@progress / 1024.0 / 1024.0).round(2)
      total_mb = (@total / 1024.0 / 1024.0).round(2)
      pct_bmp.draw_text(0, 0, pct_bmp.width, 30, "#{current_mb} MB / #{total_mb} MB  (#{percent}%)", 1)
    elsif @total > 1024
      current_kb = (@progress / 1024.0).round(1)
      total_kb = (@total / 1024.0).round(1)
      pct_bmp.draw_text(0, 0, pct_bmp.width, 30, "#{current_kb} KB / #{total_kb} KB  (#{percent}%)", 1)
    else
      pct_bmp.draw_text(0, 0, pct_bmp.width, 30, "#{percent}%", 1)
    end

    Graphics.update
  end

  def show_complete
    draw_title("Update Complete!")
    set_status("Please restart the game to apply changes.")
    set_progress(100, 100)
    Graphics.update
  end

  def show_error(message)
    draw_title("Update Failed")
    set_status("Error: #{message}")
    Graphics.update
  end

  def dispose
    @sprites.each_value do |sprite|
      sprite.bitmap&.dispose
      sprite.dispose
    end
    @sprites.clear
    @viewport&.dispose
  end
end

module MultiplayerAutoUpdater
  @ui = nil

  def self.check_version_and_update
    return true unless defined?(MultiplayerConfig) && MultiplayerConfig::ENABLE_AUTO_UPDATE
    puts "[Auto Update] Checking for updates..."

    begin
      require 'net/http'
      require 'uri'

      uri = URI(MultiplayerConfig::UPDATE_CHECK_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        puts "[Auto Update] Failed to check version: HTTP #{response.code}"
        return true # Don't block game start
      end

      data = SimpleJSON.parse(response.body)
      server_version = data['version'] || data[:version]
      update_info = data['update_info'] || data[:update_info] || {}

      puts "[Auto Update] Client version: #{MultiplayerVersion::VERSION}"
      puts "[Auto Update] Server version: #{server_version}"

      comparison = MultiplayerVersion.compare(MultiplayerVersion::VERSION, server_version)

      if comparison < 0
        puts "[Auto Update] Update available!"
        changelog = update_info['changelog'] || update_info[:changelog] || "Bug fixes and improvements"
        file_count = update_info['file_count'] || update_info[:file_count] || "several"
        file_size = update_info['file_size'] || update_info[:file_size] || 0

        return prompt_update(server_version, changelog, file_size)
      elsif comparison > 0
        puts "[Auto Update] Client is newer than server"
        return true
      else
        puts "[Auto Update] Client is up to date"
        return true
      end

    rescue Timeout::Error
      puts "[Auto Update] Timeout checking for updates"
      return true
    rescue => e
      puts "[Auto Update] Error checking version: #{e.class.name} - #{e.message}"
      return true
    end
  end

  def self.prompt_update(server_version, changelog, file_size)
    size_text = if file_size > 1024 * 1024
      "#{(file_size / 1024.0 / 1024.0).round(1)} MB"
    elsif file_size > 1024
      "#{(file_size / 1024.0).round(0)} KB"
    elsif file_size > 0
      "#{file_size} bytes"
    else
      "unknown size"
    end

    message = _INTL("A new update is available!\n\nCurrent: v{1}\nLatest: v{2}\n\nChanges:\n{3}\n\nDownload size: {4}\n\nInstall now?",
                    MultiplayerVersion::VERSION, server_version, changelog, size_text)

    choice = pbMessage(message, [_INTL("Yes"), _INTL("No")], -1)

    if choice == 0
      return download_and_install_update
    else
      pbMessage(_INTL("You can update later from the options menu."))
      return true
    end
  end

  def self.download_and_install_update
    puts "[Auto Update] Starting download..."

    @ui = UpdateProgressUI.new
    @ui.set_status("Connecting to update server...")
    @ui.set_progress(0, 100)

    begin
      require 'socket'

      puts "[Auto Update] Socket library loaded"

      # Download the update tarball using raw TCP socket
      @ui.set_status("Downloading update package...")
      @ui.set_progress(10, 100)

      host = MultiplayerConfig::SERVER_HOST
      port = MultiplayerConfig::SERVER_PORT + 1

      puts "[Auto Update] Connecting to #{host}:#{port}"

      socket = TCPSocket.new(host, port)

      # Send raw HTTP GET request
      http_request = "GET /download_update HTTP/1.1\r\n"
      http_request += "Host: #{host}\r\n"
      http_request += "Connection: close\r\n"
      http_request += "\r\n"

      socket.write(http_request)
      puts "[Auto Update] Sent HTTP request"

      # Read HTTP response
      response_data = ""
      while chunk = socket.read(8192)
        response_data += chunk
        @ui.set_progress(10 + (response_data.bytesize / 1024), 100)
        Graphics.update
        Input.update
      end
      socket.close

      puts "[Auto Update] Received #{response_data.bytesize} bytes"

      # Parse HTTP response to get body
      header_end = response_data.index("\r\n\r\n")
      unless header_end
        @ui.show_error("Invalid HTTP response")
        sleep(2)
        @ui.dispose
        return false
      end

      headers = response_data[0...header_end]
      body = response_data[(header_end + 4)..-1]

      # Check for HTTP 200 OK
      unless headers =~ /HTTP\/1\.\d\s+200\s+OK/i
        @ui.show_error("Server returned error")
        sleep(2)
        @ui.dispose
        return false
      end

      puts "[Auto Update] Downloaded #{body.bytesize} bytes of update data"

      @ui.set_status("Extracting update files...")
      @ui.set_progress(60, 100)

      # Save tarball to temp file
      temp_file = File.join(Dir.pwd, "temp_update.tar.gz")
      File.open(temp_file, 'wb') { |f| f.write(body) }

      puts "[Auto Update] Saved to #{temp_file}"

      # Extract using system tar command (Windows has tar in newer versions)
      plugins_dir = File.join(Dir.pwd, "Plugins", "Multiplayer")

      @ui.set_status("Installing update files...")
      @ui.set_progress(70, 100)

      # On Windows, try to use tar if available
      if system("tar --version > nul 2>&1")
        puts "[Auto Update] Extracting with tar command"
        system("cd \"#{plugins_dir}\" && tar -xzf \"#{temp_file}\"")
      else
        # Fallback: manual extraction (simplified - just copy the tarball for now)
        puts "[Auto Update] System tar not available - manual extraction needed"
        # For now, just notify user to manually extract
        @ui.show_error("Please extract temp_update.tar.gz manually to Plugins/Multiplayer")
        sleep(3)
        @ui.dispose
        return false
      end

      @ui.set_progress(90, 100)

      # Clean up temp file
      File.delete(temp_file) if File.exist?(temp_file)

      @ui.set_status("Cleaning up...")
      @ui.set_progress(95, 100)

      # Delete plugin cache
      cache_path = File.join(Dir.pwd, "PluginScripts.rxdata")
      File.delete(cache_path) if File.exist?(cache_path)

      @ui.set_progress(100, 100)
      @ui.show_complete

      puts "[Auto Update] Update installed successfully!"
      puts "[Auto Update] Game will restart in 3 seconds..."

      # Wait 3 seconds then restart
      90.times do
        Graphics.update
        Input.update
        sleep(0.033)
      end

      @ui.dispose

      # Restart the game
      puts "[Auto Update] Restarting game..."
      Kernel.exit!

      return true

    rescue => e
      puts "[Auto Update] Error: #{e.class.name} - #{e.message}"
      puts e.backtrace[0..5].join("\n")

      if @ui
        @ui.show_error(e.message[0..50])
        sleep(2)
        @ui.dispose
      end

      pbMessage(_INTL("Update failed: {1}", e.message))
      return false
    end
  end

  # Alternative: Download as ZIP (simpler for large updates)
  def self.download_zip_update
    puts "[Auto Update] Downloading ZIP update..."

    @ui = UpdateProgressUI.new
    @ui.set_status("Downloading update package...")

    begin
      require 'net/http'
      require 'uri'

      uri = URI(MultiplayerConfig::PLUGIN_DOWNLOAD_URL)

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10

      # Stream download with progress
      request = Net::HTTP::Get.new(uri)
      total_size = 0
      downloaded = 0
      temp_path = File.join(Dir.pwd, "update_temp.zip")

      File.open(temp_path, 'wb') do |file|
        http.request(request) do |response|
          total_size = response['content-length'].to_i

          response.read_body do |chunk|
            file.write(chunk)
            downloaded += chunk.bytesize
            @ui.set_progress(downloaded, total_size)
            Graphics.update
          end
        end
      end

      @ui.set_status("Extracting update...")
      extract_zip_update(temp_path)

      File.delete(temp_path) if File.exist?(temp_path)

      @ui.show_complete
      sleep(2)
      @ui.dispose

      pbMessage(_INTL("Update complete! Please restart the game."))
      return true

    rescue => e
      puts "[Auto Update] ZIP download error: #{e.message}"
      @ui&.dispose
      return false
    end
  end

  def self.extract_zip_update(zip_path)
    require 'zip'

    Zip::File.open(zip_path) do |zip_file|
      zip_file.each do |entry|
        target_path = File.join(Dir.pwd, entry.name)
        FileUtils.mkdir_p(File.dirname(target_path))
        entry.extract(target_path) { true } # Overwrite existing
        puts "[Auto Update] Extracted: #{entry.name}"
      end
    end
  end
end

# Event handler for checking updates on game start
EventHandlers.add(:on_game_start, :auto_update_check,
  proc {
    next unless defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?
    MultiplayerAutoUpdater.check_version_and_update
  }
)

# Frame update handler to process pending updates from server
$mmo_pending_update = nil
$mmo_update_check_cooldown = 0
$mmo_update_shown_this_session = false

EventHandlers.add(:on_frame_update, :mmo_pending_update_check,
  proc {
    next unless $mmo_pending_update
    next unless $mmo_update_check_cooldown <= 0
    next if $mmo_update_shown_this_session  # Only show once per session

    # IMPORTANT: Only show update prompt when fully on the game map
    # Don't show during login, password entry, or other screens
    next unless $scene.is_a?(Scene_Map)
    next unless $player && $player.party  # Player data must be loaded
    next unless $game_map && $game_player  # Map must be ready

    # Wait a few frames after receiving update notification to avoid conflicts
    $mmo_update_check_cooldown = 60  # 1 second cooldown

    update_info = $mmo_pending_update
    $mmo_pending_update = nil
    $mmo_update_shown_this_session = true

    new_version = update_info[:new_version]
    current_version = update_info[:current_version]
    message = update_info[:message] || "Bug fixes and improvements"

    puts "[Auto Update] Processing pending update: #{current_version} -> #{new_version}"

    # Temporarily hide ALL MMO UI components so the update prompt is visible
    mmo_ui_was_visible = false
    party_ui_was_visible = false
    key_items_was_visible = false

    if defined?($mmo_ui_overlay) && $mmo_ui_overlay && $mmo_ui_overlay.respond_to?(:visible?)
      mmo_ui_was_visible = $mmo_ui_overlay.visible?
      $mmo_ui_overlay.visible = false if $mmo_ui_overlay.respond_to?(:visible=)
      puts "[Auto Update] MMO UI overlay hidden"
    end

    if defined?($mmo_party_ui) && $mmo_party_ui && $mmo_party_ui.respond_to?(:visible?)
      party_ui_was_visible = $mmo_party_ui.visible?
      $mmo_party_ui.visible = false if $mmo_party_ui.respond_to?(:visible=)
      puts "[Auto Update] Party UI hidden"
    end

    if defined?($mmo_key_items_bar) && $mmo_key_items_bar && $mmo_key_items_bar.respond_to?(:visible?)
      key_items_was_visible = $mmo_key_items_bar.visible?
      $mmo_key_items_bar.visible = false if $mmo_key_items_bar.respond_to?(:visible=)
      puts "[Auto Update] Key items bar hidden"
    end

    # Set flag and timer to show prompt after delay
    # Can't call pbConfirmMessage from frame update - it needs its own event loop
    $mmo_update_prompt_data = {
      new_version: new_version,
      current_version: current_version,
      message: message,
      mmo_ui_was_visible: mmo_ui_was_visible,
      party_ui_was_visible: party_ui_was_visible,
      key_items_was_visible: key_items_was_visible
    }
    $mmo_update_prompt_timer = 120  # Show after 2 seconds (60 frames/sec)
    puts "[Auto Update] Update prompt deferred - will show in 2 seconds"
  }
)

# Simple custom update prompt that works from frame update
class UpdatePromptWindow
  def initialize(current_version, new_version, message)
    @current_version = current_version
    @new_version = new_version
    @message = message
    @choice = 0  # 0 = Yes, 1 = No
    @active = true

    # Disable player movement while window is open
    $game_player.lock if defined?($game_player) && $game_player

    create_ui
  end

  def create_ui
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 200000

    # Dark overlay
    @overlay = Sprite.new(@viewport)
    @overlay.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @overlay.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 200))

    # Message panel
    @panel = Sprite.new(@viewport)
    @panel.bitmap = Bitmap.new(500, 250)
    @panel.x = (Graphics.width - 500) / 2
    @panel.y = (Graphics.height - 250) / 2

    # Draw panel background
    @panel.bitmap.fill_rect(0, 0, 500, 250, Color.new(255, 255, 255))
    @panel.bitmap.fill_rect(2, 2, 496, 246, Color.new(50, 50, 80))

    # Draw text
    pbSetSystemFont(@panel.bitmap)
    @panel.bitmap.font.color = Color.new(255, 255, 255)
    @panel.bitmap.font.size = 24
    @panel.bitmap.draw_text(0, 20, 500, 30, "Update Available!", 1)

    @panel.bitmap.font.size = 18
    @panel.bitmap.draw_text(0, 70, 500, 25, "Current: v#{@current_version}", 1)
    @panel.bitmap.draw_text(0, 95, 500, 25, "Latest: v#{@new_version}", 1)
    @panel.bitmap.draw_text(0, 130, 500, 25, @message, 1)
    @panel.bitmap.draw_text(0, 160, 500, 25, "Download and install now?", 1)

    draw_buttons
  end

  def draw_buttons
    # Yes button
    yes_color = @choice == 0 ? Color.new(100, 200, 100) : Color.new(80, 80, 80)
    @panel.bitmap.fill_rect(100, 200, 120, 35, yes_color)
    @panel.bitmap.font.color = Color.new(255, 255, 255)
    @panel.bitmap.draw_text(100, 200, 120, 35, "Yes", 1)

    # No button
    no_color = @choice == 1 ? Color.new(200, 100, 100) : Color.new(80, 80, 80)
    @panel.bitmap.fill_rect(280, 200, 120, 35, no_color)
    @panel.bitmap.draw_text(280, 200, 120, 35, "No", 1)
  end

  def update
    return unless @active

    if Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
      @choice = 1 - @choice
      @panel.bitmap.clear
      @panel.bitmap.fill_rect(0, 0, 500, 250, Color.new(255, 255, 255))
      @panel.bitmap.fill_rect(2, 2, 496, 246, Color.new(50, 50, 80))

      pbSetSystemFont(@panel.bitmap)
      @panel.bitmap.font.color = Color.new(255, 255, 255)
      @panel.bitmap.font.size = 24
      @panel.bitmap.draw_text(0, 20, 500, 30, "Update Available!", 1)

      @panel.bitmap.font.size = 18
      @panel.bitmap.draw_text(0, 70, 500, 25, "Current: v#{@current_version}", 1)
      @panel.bitmap.draw_text(0, 95, 500, 25, "Latest: v#{@new_version}", 1)
      @panel.bitmap.draw_text(0, 130, 500, 25, @message, 1)
      @panel.bitmap.draw_text(0, 160, 500, 25, "Download and install now?", 1)

      draw_buttons
    end

    if Input.trigger?(Input::USE) || Input.trigger?(Input::C)
      @active = false
      return @choice
    end

    return nil
  end

  def dispose
    # Re-enable player movement
    $game_player.unlock if defined?($game_player) && $game_player

    @overlay.bitmap&.dispose
    @overlay&.dispose
    @panel.bitmap&.dispose
    @panel&.dispose
    @viewport&.dispose
  end
end

# Check for deferred update prompt with timer
$mmo_update_prompt_timer = 0
$mmo_update_prompt_window = nil
EventHandlers.add(:on_frame_update, :show_deferred_update_prompt,
  proc {
    if $mmo_update_prompt_window
      choice = $mmo_update_prompt_window.update
      Graphics.update
      Input.update

      if choice != nil
        data = $mmo_update_prompt_data
        $mmo_update_prompt_window.dispose
        $mmo_update_prompt_window = nil
        $mmo_update_prompt_data = nil

        if choice == 0
          puts "[Auto Update] User selected: Yes (download)"
          MultiplayerAutoUpdater.download_and_install_update
        else
          puts "[Auto Update] User selected: Later"

          # Restore MMO UI
          if data[:mmo_ui_was_visible] && defined?($mmo_ui_overlay) && $mmo_ui_overlay
            $mmo_ui_overlay.visible = true if $mmo_ui_overlay.respond_to?(:visible=)
          end
          if data[:party_ui_was_visible] && defined?($mmo_party_ui) && $mmo_party_ui
            $mmo_party_ui.visible = true if $mmo_party_ui.respond_to?(:visible=)
          end
          if data[:key_items_was_visible] && defined?($mmo_key_items_bar) && $mmo_key_items_bar
            $mmo_key_items_bar.visible = true if $mmo_key_items_bar.respond_to?(:visible=)
          end
        end
      end
      next
    end

    next unless defined?($mmo_update_prompt_data) && $mmo_update_prompt_data
    next unless $scene.is_a?(Scene_Map)
    next unless $mmo_update_prompt_timer > 0

    $mmo_update_prompt_timer -= 1
    next if $mmo_update_prompt_timer > 0

    data = $mmo_update_prompt_data

    puts "[Auto Update] Showing custom update prompt window..."
    $mmo_update_prompt_window = UpdatePromptWindow.new(
      data[:current_version],
      data[:new_version],
      data[:message]
    )
  }
)

# Decrement cooldown each frame
EventHandlers.add(:on_frame_update, :mmo_update_cooldown_tick,
  proc {
    $mmo_update_check_cooldown -= 1 if $mmo_update_check_cooldown > 0
  }
)

puts "[Auto Updater] Enhanced auto-update system with progress bar loaded"
