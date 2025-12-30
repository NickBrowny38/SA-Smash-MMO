MULTIPLAYER_CREDENTIALS_FILE = 'multiplayer_credentials.dat'
CREDENTIALS_VERSION = 2

module CredentialSecurity
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

  def self.generate_salt(length = 16)
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
    Array.new(length) { chars.sample }.join
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

  def self.decrypt(encrypted_text, salt_length = 16)
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

  password = pbKeyboardInput("Enter password for #{username}:", 50)

  if password.nil? || password.empty?

    return username
  end

  return password
end

def pbMultiplayerLoginScreen(force_new_account = false)
  puts "=== LOGIN SCREEN START ==="

  unless force_new_account
    saved_username, saved_password = pbLoadMultiplayerCredentials

    if saved_username && saved_password && !saved_username.empty?
      puts "Found saved credentials for: #{saved_username}"

      puts 'ABOUT TO SHOW LOGIN PROMPT...'
      if pbSimpleConfirm("Login as #{saved_username}?")
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
  loop do    username = pbKeyboardInput("Enter username (3-20 chars):", 20)

    if username.nil?
      pbMessage(_INTL("Login cancelled."))
      return [nil, nil]
    end

    username = username.gsub(/\s+/, '')

    if username.empty?
      pbMessage(_INTL('Username cannot be empty. Please try again.'))
      next
    end

    if pbValidateUsername(username)
      break
    end

  end

  $player.name = username if $player

  password = nil
  loop do    password = pbKeyboardInput("Enter password (8+ chars, 1+ number):", 50, "", nil, true)

    if password.nil?
      pbMessage(_INTL("Login cancelled."))
      return [nil, nil]
    end

    if password.empty?
      if pbConfirmMessage(_INTL("Use quick login (no password)?"))
        password = username
        break
      else
        next
      end
    end

    if pbValidatePassword(password)

      break
    end

  end

  pbSaveMultiplayerCredentials(username, password)

  puts "=== LOGIN SCREEN END ==="
  return [username, password]
end

def pbShowConnectionStatus(message)
  return unless defined?(pbSimpleAlert)
  viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
  viewport.z = 99999

  sprite = Sprite.new(viewport)
  sprite.bitmap = Bitmap.new(Graphics.width, 80)
  sprite.y = (Graphics.height - 80) / 2

  sprite.bitmap.fill_rect(0, 0, Graphics.width, 80, Color.new(0, 0, 0, 220))
  sprite.bitmap.fill_rect(4, 4, Graphics.width - 8, 72, Color.new(40, 40, 60, 255))

  pbSetSystemFont(sprite.bitmap)
  sprite.bitmap.font.size = 24
  sprite.bitmap.font.color = Color.new(255, 255, 255, 255)
  sprite.bitmap.draw_text(0, 25, Graphics.width, 30, message, 1)

  Graphics.update

  return [sprite, viewport]
end

def pbHideConnectionStatus(sprites)
  return unless sprites
  sprite, viewport = sprites
  sprite.bitmap.dispose if sprite && sprite.bitmap
  sprite.dispose if sprite
  viewport.dispose if viewport
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
  puts "Connecting..."

  max_retries = 3
  retry_count = 0

  loop do
    status_sprites = pbShowConnectionStatus("Connecting to server...")
    3.times { Graphics.update }

    success = pbConnectToMultiplayer(server_host, server_port, username, password)

    pbHideConnectionStatus(status_sprites)

    if success
      puts "LOGGED IN SUCCESSFULLY!"
      puts '=' * 50
      $multiplayer_auto_connected = true
      return true
    else
      retry_count += 1
      puts "Login failed (attempt #{retry_count})"
      puts "=" * 50

      error_msg = nil
      if pbMultiplayerClient && pbMultiplayerClient.connection_error
        error_msg = pbMultiplayerClient.connection_error
      else
        error_msg = "Could not connect to server.\nThe server may be offline."
      end

      if retry_count < max_retries
        if defined?(pbSimpleConfirm)
          if pbSimpleConfirm("#{error_msg}\n\nRetry connection? (#{retry_count}/#{max_retries})")
            next
          else
            return false
          end
        else
          pbSimpleAlert("Connection Failed", error_msg) if defined?(pbSimpleAlert)
          return false
        end
      else
        pbSimpleAlert("Connection Failed", "#{error_msg}\n\nMaximum retry attempts reached.\nPlease try again later.") if defined?(pbSimpleAlert)
        return false
      end
    end
  end
end
