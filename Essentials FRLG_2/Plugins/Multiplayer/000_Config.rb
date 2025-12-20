module MultiplayerConfig
  SERVER_HOST = "38.46.216.99"

  SERVER_PORT = 5000

  ENABLE_AUTO_UPDATE = true

  HTTP_PORT = SERVER_PORT + 1

  UPDATE_CHECK_URL = "http://#{SERVER_HOST}:#{HTTP_PORT}/version"

  UPDATE_MANIFEST_URL = "http://#{SERVER_HOST}:#{HTTP_PORT}/update_manifest"

  PLUGIN_DOWNLOAD_URL = "http://#{SERVER_HOST}:#{HTTP_PORT}/download_plugin"

  CONNECTION_TIMEOUT = 10

  AUTO_CONNECT = false

  SKIP_INTRO_IN_MULTIPLAYER = false

  ALLOW_MP_DURING_INTRO = true

  INTRO_COMPLETE_FLAG  =  nil

  ENABLE_AUCTION_HOUSE = true

  ENABLE_TRADING  =  true

  ENABLE_BATTLING = true

  ENABLE_CHAT = true

  MAX_AUCTION_LISTINGS = 10

  AUCTION_DURATION_DAYS = 7

  SEPARATE_MP_SAVES = true

  WARN_ON_MODE_SWITCH = true

  SHOW_PLAYER_COUNT = true

  SHOW_CONNECTION_STATUS = true

  MP_MENU_KEY = :F8

  DEBUG_MODE = false

  DEBUG_NETWORK  =  false

  DEBUG_EVENTS = false

  def self.intro_complete?
    return true if INTRO_COMPLETE_FLAG.nil?
    return true if !defined?($game_switches)

    begin
      if INTRO_COMPLETE_FLAG.is_a?(String) || INTRO_COMPLETE_FLAG.is_a?(Symbol)

        return $game_switches[INTRO_COMPLETE_FLAG] rescue false
      elsif INTRO_COMPLETE_FLAG.is_a?(Integer)

        return $game_switches[INTRO_COMPLETE_FLAG] rescue false
      end
    rescue
      return true
    end

    true
  end

  def self.server_address
    "#{SERVER_HOST}:#{SERVER_PORT}"
  end

  def self.feature_enabled?(feature)
    case feature
    when :auction_house
      ENABLE_AUCTION_HOUSE
    when :trading
      ENABLE_TRADING
    when :battling
      ENABLE_BATTLING
    when :chat
      ENABLE_CHAT
    else
      false
    end
  end

  def self.get_starter_pokemon(index = 0)

    return nil
  end

  def self.debug_log(message, category = :general)
    return unless DEBUG_MODE

    case category
    when :network
      return unless DEBUG_NETWORK
      puts "[MP Network] #{message}"
    when :events
      return unless DEBUG_EVENTS
      puts "[MP Events] #{message}"
    else
      puts "[MP] #{message}"
    end
  end
end

puts "[Multiplayer] Configuration loaded - Server: #{MultiplayerConfig.server_address}"

if MultiplayerConfig::SERVER_HOST.nil? || MultiplayerConfig::SERVER_HOST.empty?
  puts "[Multiplayer] WARNING: SERVER_HOST is not set!"
end

if MultiplayerConfig::SERVER_PORT.nil? || MultiplayerConfig::SERVER_PORT <= 0
  puts "[Multiplayer] WARNING: SERVER_PORT is invalid!"
end

puts "[Multiplayer] Config validation complete"
