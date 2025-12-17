MULTIPLAYER_CREDENTIALS_FILE = 'multiplayer_credentials.dat'

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
    File.open(MULTIPLAYER_CREDENTIALS_FILE, 'wb') do |file|
      file.write(Marshal.dump({username: username, password: password}))
    end
  rescue => e
    puts "Failed to save credentials: #{e.message}"
  end
end

def pbLoadMultiplayerCredentials
  begin
    if File.exist?(MULTIPLAYER_CREDENTIALS_FILE)
      data = File.open(MULTIPLAYER_CREDENTIALS_FILE, "rb") { |file| Marshal.load(file) }
      return [data[:username], data[:password]]
    end
  rescue => e
    puts "Failed to load credentials: #{e.message}"
  end
  return [nil, nil]
end

def pbClearMultiplayerCredentials
  begin
    if File.exist?(MULTIPLAYER_CREDENTIALS_FILE)
      File.delete(MULTIPLAYER_CREDENTIALS_FILE)
      puts "Credentials cleared"
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

def pbConnectWithPassword
  username, password = pbMultiplayerLoginScreen

  server_host  =  "193.31.31.187"
  server_port = 5000

  puts "=" * 50
  puts "MULTIPLAYER LOGIN"
  puts "=" * 50
  puts "Server: #{server_host}:#{server_port}"
  puts "Username: #{username}"
  puts "Connecting..."

  if pbConnectToMultiplayer(server_host, server_port, username, password)
    puts "✓ LOGGED IN SUCCESSFULLY!"
    puts '=' * 50
    $multiplayer_auto_connected = true
    return true
  else
    puts "✗ Login failed"
    puts "=" * 50
    return false
  end
end
