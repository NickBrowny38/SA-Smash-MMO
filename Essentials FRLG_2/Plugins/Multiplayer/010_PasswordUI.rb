MULTIPLAYER_CREDENTIALS_FILE = 'multiplayer_credentials.dat'
CREDENTIALS_VERSION = 3

module CredentialSecurity
  HASH_ITERATIONS = 10000
  SALT_LENGTH = 32

  def self.derive_key
    machine_id = ENV['COMPUTERNAME'] || ENV['HOSTNAME'] || 'default'
    user_id = ENV['USERNAME'] || ENV['USER'] || 'player'
    seed = "#{machine_id}#{user_id}PkmnMMO2024"
    key_bytes = []
    seed.each_byte.with_index do |b, i|
      key_bytes << ((b * 31 + i * 17) % 256)
    end
    key_bytes
  end

  def self.generate_salt(length = SALT_LENGTH)
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ['!', '@', '#', '$', '%']
    Array.new(length) { chars.sample }.join
  end

  def self.hash_password_for_transmission(password, username)
    return nil if password.nil? || username.nil?
    require 'digest'

    normalized_user = username.downcase.strip
    salt = "mmo_auth_#{normalized_user}_2024"

    hash = password
    HASH_ITERATIONS.times do |i|
      hash = Digest::SHA256.hexdigest("#{salt}#{hash}#{i}")
    end
    hash
  end

  def self.encrypt(plain_text, salt)
    return nil if plain_text.nil?
    key = derive_key
    salted = salt + plain_text
    encrypted = []
    salted.each_byte.with_index do |b, i|
      encrypted << (b ^ key[i % key.length])
    end
    [encrypted.pack('C*')].pack('m0')
  end

  def self.decrypt(encrypted_text, salt_length = SALT_LENGTH)
    return nil if encrypted_text.nil? || encrypted_text.empty?
    key = derive_key
    decoded = encrypted_text.unpack('m0').first
    decrypted = []
    decoded.each_byte.with_index do |b, i|
      decrypted << (b ^ key[i % key.length])
    end
    result = decrypted.pack('C*')
    return nil if result.length <= salt_length
    result[salt_length..-1]
  end

  def self.hash_for_display(password)
    return "" if password.nil?
    "*" * [password.length, 8].min
  end
end

module LoginState
  DISCONNECTED = :disconnected
  CONNECTING = :connecting
  AUTHENTICATING = :authenticating
  LOADING_DATA = :loading_data
  CONNECTED = :connected
  FAILED = :failed

  MESSAGES = {
    disconnected: "Not connected",
    connecting: "Connecting to server...",
    authenticating: "Verifying credentials...",
    loading_data: "Loading your save data...",
    connected: "Connected!",
    failed: "Connection failed"
  }.freeze

  def self.message_for(state)
    MESSAGES[state] || "Unknown state"
  end
end

def pbValidateUsername(username)
  return false if username.nil? || username.empty?
  username = username.strip
  if username.length < 3
    pbMessage(_INTL("Username must be at least 3 characters long."))
    return false
  end
  if username.length > 20
    pbMessage(_INTL("Username must be 20 characters or less."))
    return false
  end
  unless username =~ /[a-zA-Z0-9]/
    pbMessage(_INTL("Username must contain at least one letter or number."))
    return false
  end
  if username.gsub(/\s+/, '').empty?
    pbMessage(_INTL('Username cannot be only spaces.'))
    return false
  end
  return true
end

def pbValidatePassword(password)
  return false if password.nil? || password.empty?
  if password.length < 8
    pbMessage(_INTL("Password must be at least 8 characters long."))
    return false
  end
  unless password =~ /[0-9]/
    pbMessage(_INTL('Password must contain at least one number.'))
    return false
  end
  return true
end

def pbSaveMultiplayerCredentials(username, password)
  begin
    salt = CredentialSecurity.generate_salt
    encrypted_user = CredentialSecurity.encrypt(username, salt)
    encrypted_pass = CredentialSecurity.encrypt(password, salt)
    data = {
      version: CREDENTIALS_VERSION,
      salt: salt,
      u: encrypted_user,
      p: encrypted_pass,
      ts: Time.now.to_i
    }
    File.open(MULTIPLAYER_CREDENTIALS_FILE, 'wb') do |file|
      file.write(Marshal.dump(data))
    end
  rescue => e
    puts "Failed to save credentials: #{e.message}"
  end
end

def pbLoadMultiplayerCredentials
  begin
    if File.exist?(MULTIPLAYER_CREDENTIALS_FILE)
      data = File.open(MULTIPLAYER_CREDENTIALS_FILE, "rb") { |file| Marshal.load(file) }
      if data[:version] && data[:version] >= 2 && data[:salt]
        username = CredentialSecurity.decrypt(data[:u], data[:salt].length)
        password = CredentialSecurity.decrypt(data[:p], data[:salt].length)
        return [username, password]
      elsif data[:username] && data[:password]
        pbSaveMultiplayerCredentials(data[:username], data[:password])
        return [data[:username], data[:password]]
      end
    end
  rescue => e
    puts "Failed to load credentials: #{e.message}"
    pbClearMultiplayerCredentials
  end
  return [nil, nil]
end

def pbClearMultiplayerCredentials
  begin
    if File.exist?(MULTIPLAYER_CREDENTIALS_FILE)
      File.open(MULTIPLAYER_CREDENTIALS_FILE, 'wb') do |f|
        f.write("\x00" * 256)
      end
      File.delete(MULTIPLAYER_CREDENTIALS_FILE)
      return true
    end
  rescue => e
    puts "Failed to clear credentials: #{e.message}"
    return false
  end
  return true
end

def pbChangeMultiplayerAccount

  was_connected = pbMultiplayerConnected?

  if was_connected
    if !pbConfirmMessage(_INTL("Disconnect and switch accounts?"))
      return false
    end
    pbDisconnectFromMultiplayer
  end

  pbClearMultiplayerCredentials

  pbMessage(_INTL("Credentials cleared. You'll be prompted to login next time."))

  if was_connected
    if pbConfirmMessage(_INTL("Connect with a different account now?"))
      return pbJoinMultiplayerGame if defined?(pbJoinMultiplayerGame)
    end
  end

  return true
end

def pbGetMultiplayerPassword(username)
  password = pbKeyboardInput("Enter password for #{username}:", 50, "", nil, true)
  return nil if password.nil? || password.empty?
  password
end

def pbMultiplayerLoginScreen(force_new_account = false)
  puts "=== LOGIN SCREEN START ==="

  unless force_new_account
    saved_username, saved_password = pbLoadMultiplayerCredentials

    if saved_username && saved_password && !saved_username.empty?
      puts "Found saved credentials for: #{saved_username}"

      if pbShowLoginConfirmDialog(saved_username)
        puts "Using saved credentials: #{saved_username}"
        return [saved_username, saved_password]
      else
        puts "User chose to use different credentials"
      end
    else
      puts "No saved credentials found"
    end
  end

  puts "Prompting for new credentials"

  username = nil
  loop do
    username = pbKeyboardInput("Enter username (3-20 chars):", 20)

    if username.nil?
      return [nil, nil]
    end

    username = username.gsub(/\s+/, '')

    if username.empty?
      pbSimpleAlert("Invalid Username", "Username cannot be empty.\nPlease try again.")
      next
    end

    if pbValidateUsername(username)
      break
    end
  end

  $player.name = username if $player

  password = nil
  loop do
    password = pbKeyboardInput("Enter password (8+ chars, 1+ number):", 50, "", nil, true)

    if password.nil?
      return [nil, nil]
    end

    if password.empty?
      pbSimpleAlert("Password Required", "A password is required for account security.\nPlease enter a password.")
      next
    end

    if pbValidatePassword(password)
      break
    end
  end

  pbSaveMultiplayerCredentials(username, password)

  puts "=== LOGIN SCREEN END ==="
  [username, password]
end

def pbShowLoginConfirmDialog(username)
  viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
  viewport.z = 99999

  bg_sprite = Sprite.new(viewport)
  bg_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
  bg_sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 200))

  box_width = 380
  box_height = 180
  box_x = (Graphics.width - box_width) / 2
  box_y = (Graphics.height - box_height) / 2

  box_sprite = Sprite.new(viewport)
  box_sprite.bitmap = Bitmap.new(box_width, box_height)
  box_sprite.x = box_x
  box_sprite.y = box_y
  box_sprite.z = 100000

  box_sprite.bitmap.fill_rect(0, 0, box_width, box_height, Color.new(255, 255, 255))
  box_sprite.bitmap.fill_rect(4, 4, box_width - 8, box_height - 8, Color.new(40, 50, 70))
  box_sprite.bitmap.fill_rect(8, 8, box_width - 16, 45, Color.new(70, 130, 180))

  pbSetSystemFont(box_sprite.bitmap)
  box_sprite.bitmap.font.size = 26
  box_sprite.bitmap.font.bold = true
  box_sprite.bitmap.font.color = Color.new(255, 255, 255)
  box_sprite.bitmap.draw_text(15, 14, box_width - 30, 32, "Welcome Back!", 1)

  box_sprite.bitmap.font.size = 22
  box_sprite.bitmap.font.bold = false
  box_sprite.bitmap.draw_text(20, 60, box_width - 40, 28, "Continue as:", 1)

  box_sprite.bitmap.font.size = 28
  box_sprite.bitmap.font.bold = true
  box_sprite.bitmap.font.color = Color.new(100, 200, 255)
  box_sprite.bitmap.draw_text(20, 88, box_width - 40, 32, username, 1)

  selection = 0
  button_y = box_height - 50

  draw_buttons = proc do |sel|
    box_sprite.bitmap.fill_rect(30, button_y, 150, 38, sel == 0 ? Color.new(100, 180, 100) : Color.new(80, 80, 100))
    box_sprite.bitmap.fill_rect(200, button_y, 150, 38, sel == 1 ? Color.new(180, 100, 100) : Color.new(80, 80, 100))

    box_sprite.bitmap.font.size = 20
    box_sprite.bitmap.font.bold = true
    box_sprite.bitmap.font.color = Color.new(255, 255, 255)
    box_sprite.bitmap.draw_text(30, button_y + 8, 150, 24, "Continue", 1)
    box_sprite.bitmap.draw_text(200, button_y + 8, 150, 24, "Switch Account", 1)
  end

  draw_buttons.call(selection)

  5.times { Graphics.update; Input.update }

  result = nil
  loop do
    Graphics.update
    Input.update

    if Input.trigger?(Input::LEFT)
      selection = 0
      draw_buttons.call(selection)
    elsif Input.trigger?(Input::RIGHT)
      selection = 1
      draw_buttons.call(selection)
    end

    if Input.trigger?(Input::USE) || Input.trigger?(Input::ACTION)
      result = (selection == 0)
      break
    end

    if Input.trigger?(Input::BACK)
      result = false
      break
    end
  end

  box_sprite.bitmap.dispose
  box_sprite.dispose
  bg_sprite.bitmap.dispose
  bg_sprite.dispose
  viewport.dispose

  result
end

class ConnectionStatusOverlay
  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999

    @bg_sprite = Sprite.new(@viewport)
    @bg_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @bg_sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))

    @box_width = 350
    @box_height = 120
    @box_x = (Graphics.width - @box_width) / 2
    @box_y = (Graphics.height - @box_height) / 2

    @box_sprite = Sprite.new(@viewport)
    @box_sprite.bitmap = Bitmap.new(@box_width, @box_height)
    @box_sprite.x = @box_x
    @box_sprite.y = @box_y
    @box_sprite.z = 100000

    @spinner_frame = 0
    @spinner_chars = ['|', '/', '-', '\\']
  end

  def update(message, sub_message = nil)
    @spinner_frame = (@spinner_frame + 1) % 20
    spinner = @spinner_chars[@spinner_frame / 5]

    @box_sprite.bitmap.clear
    @box_sprite.bitmap.fill_rect(0, 0, @box_width, @box_height, Color.new(255, 255, 255))
    @box_sprite.bitmap.fill_rect(4, 4, @box_width - 8, @box_height - 8, Color.new(40, 50, 70))

    pbSetSystemFont(@box_sprite.bitmap)
    @box_sprite.bitmap.font.size = 24
    @box_sprite.bitmap.font.bold = true
    @box_sprite.bitmap.font.color = Color.new(255, 255, 255)
    @box_sprite.bitmap.draw_text(20, 25, @box_width - 40, 30, "#{spinner} #{message}", 1)

    if sub_message
      @box_sprite.bitmap.font.size = 18
      @box_sprite.bitmap.font.bold = false
      @box_sprite.bitmap.font.color = Color.new(180, 180, 180)
      @box_sprite.bitmap.draw_text(20, 60, @box_width - 40, 24, sub_message, 1)
    end

    progress_width = @box_width - 40
    @box_sprite.bitmap.fill_rect(20, @box_height - 30, progress_width, 8, Color.new(60, 60, 80))

    progress = case message
               when /Connecting/ then 0.25
               when /Authenticating|Verifying/ then 0.5
               when /Loading/ then 0.75
               when /Connected/ then 1.0
               else 0.1
               end
    @box_sprite.bitmap.fill_rect(20, @box_height - 30, (progress_width * progress).to_i, 8, Color.new(100, 180, 100))

    Graphics.update
  end

  def show_success(message)
    @box_sprite.bitmap.clear
    @box_sprite.bitmap.fill_rect(0, 0, @box_width, @box_height, Color.new(255, 255, 255))
    @box_sprite.bitmap.fill_rect(4, 4, @box_width - 8, @box_height - 8, Color.new(40, 80, 60))

    pbSetSystemFont(@box_sprite.bitmap)
    @box_sprite.bitmap.font.size = 26
    @box_sprite.bitmap.font.bold = true
    @box_sprite.bitmap.font.color = Color.new(100, 255, 100)
    @box_sprite.bitmap.draw_text(20, 40, @box_width - 40, 36, message, 1)

    @box_sprite.bitmap.fill_rect(20, @box_height - 30, @box_width - 40, 8, Color.new(100, 180, 100))

    8.times { Graphics.update }
  end

  def dispose
    @box_sprite.bitmap.dispose if @box_sprite&.bitmap
    @box_sprite.dispose if @box_sprite
    @bg_sprite.bitmap.dispose if @bg_sprite&.bitmap
    @bg_sprite.dispose if @bg_sprite
    @viewport.dispose if @viewport
  end
end

def pbConnectWithPassword
  username, password = pbMultiplayerLoginScreen
  return false if username.nil?

  server_host = MultiplayerConfig::SERVER_HOST
  server_port = MultiplayerConfig::SERVER_PORT

  puts "=" * 50
  puts "MULTIPLAYER LOGIN"
  puts "=" * 50
  puts "Server: #{server_host}:#{server_port}"
  puts "Username: #{username}"

  hashed_password = CredentialSecurity.hash_password_for_transmission(password, username)

  max_retries = 3
  retry_count = 0
  base_delay = 1.0

  loop do
    status = ConnectionStatusOverlay.new

    10.times do
      status.update("Connecting to server...", "#{server_host}:#{server_port}")
    end

    success = false
    error_msg = nil

    begin
      20.times do
        status.update("Connecting to server...", "Establishing connection...")
      end

      success = pbConnectToMultiplayer(server_host, server_port, username, hashed_password)

      if success
        15.times { status.update("Authenticating...", "Verifying credentials...") }
        15.times { status.update("Loading save data...", "Please wait...") }
        status.show_success("Connected!")
      else
        error_msg = pbMultiplayerClient&.connection_error || "Could not connect to server.\nThe server may be offline."
      end
    rescue => e
      error_msg = "Connection error: #{e.message}"
      puts "Connection exception: #{e.message}"
    end

    status.dispose

    if success
      puts "LOGGED IN SUCCESSFULLY!"
      puts "=" * 50
      $multiplayer_auto_connected = true
      return true
    end

    retry_count += 1
    puts "Login failed (attempt #{retry_count}/#{max_retries})"
    puts "=" * 50

    if retry_count < max_retries
      delay = base_delay * (2 ** (retry_count - 1))
      delay = [delay, 8.0].min

      if pbShowRetryDialog(error_msg, retry_count, max_retries, delay)
        delay_frames = (delay * 60).to_i
        delay_frames.times { Graphics.update }
        next
      else
        return false
      end
    else
      pbSimpleAlert("Connection Failed", "#{error_msg}\n\nMaximum attempts reached.\nPlease check your internet connection\nand try again later.")
      return false
    end
  end
end

def pbShowRetryDialog(error_msg, attempt, max_attempts, delay)
  viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
  viewport.z = 99999

  bg_sprite = Sprite.new(viewport)
  bg_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
  bg_sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 200))

  box_width = 400
  box_height = 200
  box_x = (Graphics.width - box_width) / 2
  box_y = (Graphics.height - box_height) / 2

  box_sprite = Sprite.new(viewport)
  box_sprite.bitmap = Bitmap.new(box_width, box_height)
  box_sprite.x = box_x
  box_sprite.y = box_y
  box_sprite.z = 100000

  box_sprite.bitmap.fill_rect(0, 0, box_width, box_height, Color.new(255, 255, 255))
  box_sprite.bitmap.fill_rect(4, 4, box_width - 8, box_height - 8, Color.new(50, 40, 40))
  box_sprite.bitmap.fill_rect(8, 8, box_width - 16, 45, Color.new(180, 80, 80))

  pbSetSystemFont(box_sprite.bitmap)
  box_sprite.bitmap.font.size = 24
  box_sprite.bitmap.font.bold = true
  box_sprite.bitmap.font.color = Color.new(255, 255, 255)
  box_sprite.bitmap.draw_text(15, 14, box_width - 30, 32, "Connection Failed", 1)

  box_sprite.bitmap.font.size = 18
  box_sprite.bitmap.font.bold = false

  lines = error_msg.split(/\\n|\n/)
  y_offset = 60
  lines.each do |line|
    box_sprite.bitmap.draw_text(20, y_offset, box_width - 40, 22, line, 1)
    y_offset += 22
  end

  box_sprite.bitmap.font.size = 16
  box_sprite.bitmap.font.color = Color.new(200, 200, 200)
  box_sprite.bitmap.draw_text(20, box_height - 80, box_width - 40, 20, "Attempt #{attempt}/#{max_attempts} - Retry in #{delay.to_i}s?", 1)

  selection = 0
  button_y = box_height - 50

  draw_buttons = proc do |sel|
    box_sprite.bitmap.fill_rect(50, button_y, 130, 38, sel == 0 ? Color.new(100, 180, 100) : Color.new(80, 80, 100))
    box_sprite.bitmap.fill_rect(220, button_y, 130, 38, sel == 1 ? Color.new(180, 100, 100) : Color.new(80, 80, 100))

    box_sprite.bitmap.font.size = 18
    box_sprite.bitmap.font.bold = true
    box_sprite.bitmap.font.color = Color.new(255, 255, 255)
    box_sprite.bitmap.draw_text(50, button_y + 10, 130, 22, "Retry", 1)
    box_sprite.bitmap.draw_text(220, button_y + 10, 130, 22, "Cancel", 1)
  end

  draw_buttons.call(selection)

  5.times { Graphics.update; Input.update }

  result = nil
  loop do
    Graphics.update
    Input.update

    if Input.trigger?(Input::LEFT)
      selection = 0
      draw_buttons.call(selection)
    elsif Input.trigger?(Input::RIGHT)
      selection = 1
      draw_buttons.call(selection)
    end

    if Input.trigger?(Input::USE) || Input.trigger?(Input::ACTION)
      result = (selection == 0)
      break
    end

    if Input.trigger?(Input::BACK)
      result = false
      break
    end
  end

  box_sprite.bitmap.dispose
  box_sprite.dispose
  bg_sprite.bitmap.dispose
  bg_sprite.dispose
  viewport.dispose

  result
end
