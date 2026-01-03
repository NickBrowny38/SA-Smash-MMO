# Enhanced Auto-Updater System for Pokemon FRLG MMO
# Features: Progress bar UI, full game updates, manifest-based downloads
# Uses raw TCP sockets for mkxp compatibility

#===============================================================================
# Progress Bar UI - Beautiful update progress display
#===============================================================================
class UpdateProgressUI
  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 100001
    @sprites = {}
    @progress = 0
    @total = 100
    @status = "Initializing..."
    @file_name = ""

    create_ui
  end

  def create_ui
    # Dark overlay background
    @sprites[:overlay] = Sprite.new(@viewport)
    @sprites[:overlay].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites[:overlay].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 220))

    # Main panel
    panel_w = 600
    panel_h = 280
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

    # File name text
    @sprites[:file_name] = Sprite.new(@viewport)
    @sprites[:file_name].bitmap = Bitmap.new(panel_w - 40, 25)
    @sprites[:file_name].x = @panel_x + 20
    @sprites[:file_name].y = @panel_y + 100

    # Progress bar background
    @bar_x = @panel_x + 25
    @bar_y = @panel_y + 140
    @bar_w = panel_w - 50
    @bar_h = 40

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
    @sprites[:percent].y = @panel_y + 190

    # File counter text
    @sprites[:counter] = Sprite.new(@viewport)
    @sprites[:counter].bitmap = Bitmap.new(panel_w - 40, 25)
    @sprites[:counter].x = @panel_x + 20
    @sprites[:counter].y = @panel_y + 220

    update_display
  end

  def draw_panel
    bmp = @sprites[:panel].bitmap
    w, h = bmp.width, bmp.height

    # Outer glow/border - nice blue
    bmp.fill_rect(0, 0, w, h, Color.new(80, 150, 255, 200))
    # Main background - dark blue
    bmp.fill_rect(3, 3, w - 6, h - 6, Color.new(25, 35, 55))
    # Header gradient
    for i in 0...70
      alpha = 120 - (i * 1.7).to_i
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

  def set_file_name(name)
    @file_name = name
    update_display
  end

  def set_progress(current, total)
    @progress = current
    @total = [total, 1].max
    update_display
  end

  def set_file_counter(current, total)
    @file_current = current
    @file_total = total
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

    # Update file name text
    if @sprites[:file_name]
      bmp = @sprites[:file_name].bitmap
      bmp.clear
      pbSetSystemFont(bmp)
      bmp.font.size = 14
      bmp.font.color = Color.new(140, 160, 190)
      # Truncate long file names
      display_name = @file_name.length > 60 ? "..." + @file_name[-57..-1] : @file_name
      bmp.draw_text(0, 0, bmp.width, 25, display_name, 1)
    end

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

    # Update file counter
    if @sprites[:counter] && @file_current && @file_total
      cnt_bmp = @sprites[:counter].bitmap
      cnt_bmp.clear
      pbSetSystemFont(cnt_bmp)
      cnt_bmp.font.size = 14
      cnt_bmp.font.color = Color.new(120, 140, 170)
      cnt_bmp.draw_text(0, 0, cnt_bmp.width, 25, "File #{@file_current} of #{@file_total}", 1)
    end

    Graphics.update
  end

  def show_complete
    draw_title("Update Complete!")
    set_status("Please restart the game to apply changes.")
    set_file_name("")
    set_progress(100, 100)
    Graphics.update
  end

  def show_error(message)
    draw_title("Update Failed")
    set_status("Error: #{message}")
    set_file_name("")
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

#===============================================================================
# HTTP Client - Raw TCP socket for mkxp compatibility
#===============================================================================
module SimpleHTTP
  # Perform a GET request using raw TCP sockets (works in mkxp)
  def self.get(host, port, path, timeout = 30)
    require 'socket'

    socket = nil
    begin
      socket = TCPSocket.new(host, port)
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # Send HTTP request
      request = "GET #{path} HTTP/1.1\r\n"
      request += "Host: #{host}:#{port}\r\n"
      request += "Connection: close\r\n"
      request += "Accept: */*\r\n"
      request += "\r\n"

      socket.write(request)

      # Read response with timeout
      response = ""
      start_time = Time.now

      while Time.now - start_time < timeout
        begin
          chunk = socket.read_nonblock(8192)
          response += chunk if chunk
        rescue IO::WaitReadable
          IO.select([socket], nil, nil, 0.1)
        rescue EOFError
          break
        end
      end

      socket.close

      # Parse HTTP response
      header_end = response.index("\r\n\r\n")
      return nil unless header_end

      headers = response[0...header_end]
      body = response[(header_end + 4)..-1]

      # Check status code
      status_line = headers.split("\r\n").first
      status_code = status_line.match(/HTTP\/\d\.\d\s+(\d+)/)[1].to_i rescue 0

      return nil unless status_code == 200

      # Handle chunked transfer encoding
      if headers.downcase.include?("transfer-encoding: chunked")
        body = decode_chunked(body)
      end

      return body

    rescue => e
      puts "[SimpleHTTP] Error: #{e.class.name} - #{e.message}"
      return nil
    ensure
      socket&.close rescue nil
    end
  end

  # Decode chunked transfer encoding
  def self.decode_chunked(data)
    result = ""
    pos = 0

    while pos < data.length
      # Find chunk size line
      line_end = data.index("\r\n", pos)
      break unless line_end

      size_str = data[pos...line_end].strip
      chunk_size = size_str.to_i(16)
      break if chunk_size == 0

      # Extract chunk data
      chunk_start = line_end + 2
      chunk_end = chunk_start + chunk_size
      break if chunk_end > data.length

      result += data[chunk_start...chunk_end]
      pos = chunk_end + 2  # Skip trailing \r\n
    end

    result
  end

  # Download file with progress callback
  def self.download_file(host, port, path, timeout = 60, &progress_callback)
    require 'socket'

    socket = nil
    begin
      socket = TCPSocket.new(host, port)
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # Send HTTP request
      request = "GET #{path} HTTP/1.1\r\n"
      request += "Host: #{host}:#{port}\r\n"
      request += "Connection: close\r\n"
      request += "Accept: */*\r\n"
      request += "\r\n"

      socket.write(request)

      # Read headers first
      header_data = ""
      while !header_data.include?("\r\n\r\n")
        chunk = socket.readpartial(1024)
        header_data += chunk
      end

      header_end = header_data.index("\r\n\r\n")
      headers = header_data[0...header_end]
      body = header_data[(header_end + 4)..-1] || ""

      # Parse content length
      content_length = 0
      headers.each_line do |line|
        if line.downcase.start_with?("content-length:")
          content_length = line.split(":")[1].strip.to_i
        end
      end

      # Check status
      status_line = headers.split("\r\n").first
      status_code = status_line.match(/HTTP\/\d\.\d\s+(\d+)/)[1].to_i rescue 0
      return nil unless status_code == 200

      # Read body with progress
      while body.length < content_length
        begin
          chunk = socket.readpartial(16384)
          body += chunk
          progress_callback.call(body.length, content_length) if progress_callback
          Graphics.update
        rescue EOFError
          break
        end
      end

      socket.close
      return body

    rescue => e
      puts "[SimpleHTTP] Download error: #{e.class.name} - #{e.message}"
      return nil
    ensure
      socket&.close rescue nil
    end
  end
end

#===============================================================================
# Simple JSON Parser (for manifest parsing without external gems)
#===============================================================================
module SimpleJSON
  def self.parse(json_string)
    # Clean up the string
    str = json_string.strip

    # Use Ruby's built-in JSON if available (newer Ruby versions)
    if defined?(JSON)
      return JSON.parse(str, symbolize_names: true) rescue nil
    end

    # Simple fallback parser for basic JSON
    parse_value(str, 0)[0]
  end

  def self.parse_value(str, pos)
    pos = skip_whitespace(str, pos)
    return [nil, pos] if pos >= str.length

    char = str[pos]

    case char
    when '{'
      parse_object(str, pos)
    when '['
      parse_array(str, pos)
    when '"'
      parse_string(str, pos)
    when 't', 'f'
      parse_boolean(str, pos)
    when 'n'
      parse_null(str, pos)
    when '-', '0'..'9'
      parse_number(str, pos)
    else
      [nil, pos]
    end
  end

  def self.skip_whitespace(str, pos)
    while pos < str.length && " \t\n\r".include?(str[pos])
      pos += 1
    end
    pos
  end

  def self.parse_object(str, pos)
    result = {}
    pos += 1  # Skip '{'

    loop do
      pos = skip_whitespace(str, pos)
      break if str[pos] == '}'

      # Parse key
      key, pos = parse_string(str, pos)
      pos = skip_whitespace(str, pos)
      pos += 1 if str[pos] == ':'  # Skip ':'

      # Parse value
      value, pos = parse_value(str, pos)
      result[key.to_sym] = value

      pos = skip_whitespace(str, pos)
      pos += 1 if str[pos] == ','  # Skip ','
    end

    pos += 1  # Skip '}'
    [result, pos]
  end

  def self.parse_array(str, pos)
    result = []
    pos += 1  # Skip '['

    loop do
      pos = skip_whitespace(str, pos)
      break if str[pos] == ']'

      value, pos = parse_value(str, pos)
      result << value

      pos = skip_whitespace(str, pos)
      pos += 1 if str[pos] == ','  # Skip ','
    end

    pos += 1  # Skip ']'
    [result, pos]
  end

  def self.parse_string(str, pos)
    pos += 1  # Skip opening quote
    result = ""

    while pos < str.length && str[pos] != '"'
      if str[pos] == '\\'
        pos += 1
        case str[pos]
        when 'n' then result += "\n"
        when 't' then result += "\t"
        when 'r' then result += "\r"
        when '"' then result += '"'
        when '\\' then result += '\\'
        else result += str[pos]
        end
      else
        result += str[pos]
      end
      pos += 1
    end

    pos += 1  # Skip closing quote
    [result, pos]
  end

  def self.parse_number(str, pos)
    start_pos = pos
    pos += 1 if str[pos] == '-'
    while pos < str.length && "0123456789.eE+-".include?(str[pos])
      pos += 1
    end
    num_str = str[start_pos...pos]
    [num_str.include?('.') ? num_str.to_f : num_str.to_i, pos]
  end

  def self.parse_boolean(str, pos)
    if str[pos, 4] == 'true'
      [true, pos + 4]
    elsif str[pos, 5] == 'false'
      [false, pos + 5]
    else
      [nil, pos]
    end
  end

  def self.parse_null(str, pos)
    if str[pos, 4] == 'null'
      [nil, pos + 4]
    else
      [nil, pos]
    end
  end
end

#===============================================================================
# MD5 Calculator (for file verification)
#===============================================================================
module SimpleMD5
  # Calculate MD5 hash of a file
  def self.file_hash(file_path)
    return nil unless File.exist?(file_path)

    begin
      require 'digest'
      Digest::MD5.file(file_path).hexdigest
    rescue => e
      puts "[MD5] Error calculating hash for #{file_path}: #{e.message}"
      nil
    end
  end

  # Calculate MD5 hash of data
  def self.data_hash(data)
    require 'digest'
    Digest::MD5.hexdigest(data)
  end
end

#===============================================================================
# Auto-Updater Module
#===============================================================================
module MultiplayerAutoUpdater
  @ui = nil

  # Check for updates at game start
  def self.check_version_and_update
    return true unless defined?(MultiplayerConfig) && MultiplayerConfig::ENABLE_AUTO_UPDATE

    puts "[Auto Update] Checking for updates..."

    begin
      host = MultiplayerConfig::SERVER_HOST
      port = MultiplayerConfig::HTTP_PORT

      # Fetch version info from server
      version_json = SimpleHTTP.get(host, port, "/version", 10)

      unless version_json
        puts "[Auto Update] Failed to fetch version info"
        return true  # Don't block game start
      end

      data = SimpleJSON.parse(version_json)
      unless data
        puts "[Auto Update] Failed to parse version response"
        return true
      end

      server_version = data[:version] || data["version"]
      update_info = data[:update_info] || data["update_info"] || {}

      puts "[Auto Update] Client version: #{MultiplayerVersion::VERSION}"
      puts "[Auto Update] Server version: #{server_version}"

      comparison = MultiplayerVersion.compare(MultiplayerVersion::VERSION, server_version)

      if comparison < 0
        puts "[Auto Update] Update available!"
        changelog = update_info[:changelog] || update_info["changelog"] || "Bug fixes and improvements"
        file_size = update_info[:file_size] || update_info["file_size"] || 0
        file_count = update_info[:file_count] || update_info["file_count"] || 0

        return prompt_update(server_version, changelog, file_size, file_count)
      elsif comparison > 0
        puts "[Auto Update] Client is newer than server"
        return true
      else
        puts "[Auto Update] Client is up to date"
        return true
      end

    rescue => e
      puts "[Auto Update] Error checking version: #{e.class.name} - #{e.message}"
      return true
    end
  end

  # Show update prompt to user
  def self.prompt_update(server_version, changelog, file_size, file_count)
    size_text = if file_size > 1024 * 1024
      "#{(file_size / 1024.0 / 1024.0).round(1)} MB"
    elsif file_size > 1024
      "#{(file_size / 1024.0).round(0)} KB"
    elsif file_size > 0
      "#{file_size} bytes"
    else
      "calculating..."
    end

    message = _INTL("A new update is available!\n\nCurrent: v{1}\nLatest: v{2}\n\nChanges:\n{3}\n\nDownload size: ~{4}\nFiles: {5}\n\nInstall now?",
                    MultiplayerVersion::VERSION, server_version, changelog, size_text, file_count)

    choice = pbMessage(message, [_INTL("Yes"), _INTL("No")], -1)

    if choice == 0
      return download_and_install_update
    else
      pbMessage(_INTL("You can update later. Note: You may not be able to connect to the server with an outdated client."))
      return true
    end
  end

  # Main update download and installation
  def self.download_and_install_update
    puts "[Auto Update] Starting manifest-based update..."

    @ui = UpdateProgressUI.new
    @ui.set_status("Connecting to update server...")
    @ui.set_progress(0, 100)

    begin
      host = MultiplayerConfig::SERVER_HOST
      port = MultiplayerConfig::HTTP_PORT

      # Step 1: Fetch update manifest
      @ui.set_status("Fetching update manifest...")
      @ui.set_progress(5, 100)

      manifest_json = SimpleHTTP.get(host, port, "/update_manifest", 30)

      unless manifest_json
        @ui.show_error("Failed to fetch update manifest")
        sleep(2)
        @ui.dispose
        return false
      end

      manifest = SimpleJSON.parse(manifest_json)

      unless manifest && manifest[:files]
        @ui.show_error("Invalid update manifest")
        sleep(2)
        @ui.dispose
        return false
      end

      puts "[Auto Update] Manifest received: #{manifest[:files].length} files, #{manifest[:total_size]} bytes"

      # Step 2: Determine which files need updating
      @ui.set_status("Checking local files...")
      @ui.set_progress(10, 100)

      files_to_update = []
      total_download_size = 0

      manifest[:files].each do |file_info|
        local_path = File.join(Dir.pwd, file_info[:path])

        needs_update = false

        if !File.exist?(local_path)
          needs_update = true
          puts "[Auto Update] New file: #{file_info[:path]}"
        else
          local_md5 = SimpleMD5.file_hash(local_path)
          if local_md5 != file_info[:md5]
            needs_update = true
            puts "[Auto Update] Changed file: #{file_info[:path]}"
          end
        end

        if needs_update
          files_to_update << file_info
          total_download_size += file_info[:size]
        end
      end

      if files_to_update.empty?
        puts "[Auto Update] All files up to date!"
        @ui.set_status("All files are up to date!")
        @ui.set_progress(100, 100)
        sleep(2)
        @ui.dispose
        return true
      end

      puts "[Auto Update] #{files_to_update.length} files to update (#{total_download_size} bytes)"

      # Step 3: Download and install each file
      @ui.set_status("Downloading updates...")
      downloaded_bytes = 0
      files_completed = 0

      files_to_update.each do |file_info|
        file_path = file_info[:path]
        local_path = File.join(Dir.pwd, file_path)

        @ui.set_file_name(file_path)
        @ui.set_file_counter(files_completed + 1, files_to_update.length)

        # Create backup of existing file
        if File.exist?(local_path)
          backup_path = local_path + ".backup"
          File.rename(local_path, backup_path) rescue nil
        end

        # Ensure directory exists
        dir_path = File.dirname(local_path)
        FileUtils.mkdir_p(dir_path) unless Dir.exist?(dir_path)

        # Download file
        url_path = "/download_file?path=#{URI.encode_www_form_component(file_path)}"

        file_data = SimpleHTTP.download_file(host, port, url_path, 120) do |current, total|
          progress = (((downloaded_bytes + current).to_f / total_download_size) * 85 + 10).to_i
          @ui.set_progress(progress, 100)
        end

        if file_data
          # Verify MD5
          received_md5 = SimpleMD5.data_hash(file_data)
          if received_md5 != file_info[:md5]
            puts "[Auto Update] MD5 mismatch for #{file_path}! Expected: #{file_info[:md5]}, Got: #{received_md5}"
            # Restore backup
            backup_path = local_path + ".backup"
            if File.exist?(backup_path)
              File.rename(backup_path, local_path) rescue nil
            end
          else
            # Write file
            File.open(local_path, 'wb') { |f| f.write(file_data) }
            puts "[Auto Update] Updated: #{file_path}"

            # Remove backup
            backup_path = local_path + ".backup"
            File.delete(backup_path) if File.exist?(backup_path)
          end

          downloaded_bytes += file_info[:size]
          files_completed += 1
        else
          puts "[Auto Update] Failed to download: #{file_path}"
          # Restore backup
          backup_path = local_path + ".backup"
          if File.exist?(backup_path)
            File.rename(backup_path, local_path) rescue nil
          end
        end
      end

      # Step 4: Clean up and finalize
      @ui.set_status("Finalizing update...")
      @ui.set_progress(98, 100)

      # Delete PluginScripts cache to force recompile
      cache_path = File.join(Dir.pwd, "PluginScripts.rxdata")
      File.delete(cache_path) if File.exist?(cache_path)

      @ui.set_progress(100, 100)
      @ui.show_complete

      puts "[Auto Update] Update complete! #{files_completed}/#{files_to_update.length} files updated."
      puts "[Auto Update] Game will restart in 3 seconds..."

      # Wait before restart
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

  # Force check for updates (can be called from menu)
  def self.force_check_update
    check_version_and_update
  end
end

#===============================================================================
# URI Encoding helper
#===============================================================================
module URI
  def self.encode_www_form_component(str)
    str.to_s.gsub(/[^a-zA-Z0-9_.\-~]/) do |char|
      '%' + char.ord.to_s(16).upcase.rjust(2, '0')
    end
  end
end

#===============================================================================
# FileUtils helper if not available
#===============================================================================
unless defined?(FileUtils)
  module FileUtils
    def self.mkdir_p(path)
      parts = path.split(/[\/\\]/)
      current = ""
      parts.each do |part|
        current = current.empty? ? part : File.join(current, part)
        Dir.mkdir(current) unless Dir.exist?(current)
      end
    end
  end
end

#===============================================================================
# Event Handlers
#===============================================================================

# Check for updates when entering multiplayer mode
EventHandlers.add(:on_game_start, :auto_update_check,
  proc {
    next unless defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?
    MultiplayerAutoUpdater.check_version_and_update
  }
)

# Handle pending updates from server (when server tells us we're outdated)
$mmo_pending_update = nil
$mmo_update_check_cooldown = 0
$mmo_update_shown_this_session = false

EventHandlers.add(:on_frame_update, :mmo_pending_update_check,
  proc {
    next unless $mmo_pending_update
    next unless $mmo_update_check_cooldown <= 0
    next if $mmo_update_shown_this_session

    # Only show when on map
    next unless $scene.is_a?(Scene_Map)
    next unless $player && $player.party
    next unless $game_map && $game_player

    $mmo_update_check_cooldown = 120

    update_info = $mmo_pending_update
    $mmo_pending_update = nil
    $mmo_update_shown_this_session = true

    new_version = update_info[:new_version]
    current_version = update_info[:current_version]
    message = update_info[:message] || "Bug fixes and improvements"

    puts "[Auto Update] Server notified of update: #{current_version} -> #{new_version}"

    # Show update prompt
    choice = pbMessage(
      _INTL("A new game update is available!\n\nYour version: v{1}\nLatest: v{2}\n\n{3}\n\nUpdate now?",
            current_version, new_version, message),
      [_INTL("Yes"), _INTL("Later")],
      -1
    )

    if choice == 0
      MultiplayerAutoUpdater.download_and_install_update
    end
  }
)

# Cooldown timer
EventHandlers.add(:on_frame_update, :mmo_update_cooldown_tick,
  proc {
    $mmo_update_check_cooldown -= 1 if $mmo_update_check_cooldown > 0
  }
)

puts "[Auto Updater] Enhanced manifest-based auto-update system loaded"
