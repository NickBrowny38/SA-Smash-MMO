# Pokemon Essentials Multiplayer Server Configuration
# Edit these settings to customize your server

module ServerConfig
  #=============================================================================
  # SERVER SETTINGS
  #=============================================================================

  # Server port (must match client config)
  PORT = 5000

  # Public IP/hostname for download URLs (used by auto-updater)
  # This MUST be set to your server's public IP address
  PUBLIC_HOST = "46.250.245.149"

  # Maximum number of players
  MAX_PLAYERS = 50

  # Server timeout (seconds before disconnecting idle players)
  # Default: 120 seconds (2 minutes)
  TIMEOUT_SECONDS = 120

  #=============================================================================
  # SPAWN SETTINGS (where new players start)
  #=============================================================================

  # Default spawn map ID for new players
  # Find your map IDs in PBS/maps.txt or Data/MapInfos.rxdata
  DEFAULT_SPAWN_MAP = 7  # Map ID

  # Default spawn coordinates
  DEFAULT_SPAWN_X = 25
  DEFAULT_SPAWN_Y = 6

  # Default spawn direction (2=down, 4=left, 6=right, 8=up)
  DEFAULT_SPAWN_DIRECTION = 2

  #=============================================================================
  # NEW PLAYER SETTINGS
  #=============================================================================

  # Starting money for new players
  STARTING_MONEY = 3000

  # Starting ELO rating for battles
  STARTING_ELO = 1000

  #=============================================================================
  # BATTLE SETTINGS
  #=============================================================================

  # ELO K-factor (how much ELO changes per battle)
  # Higher = more volatile rankings
  # Default: 100
  ELO_K_FACTOR = 100

  # ELO penalty for disconnecting during battle
  DISCONNECT_ELO_PENALTY = 50

  # Battle timeout (minutes of inactivity before auto-forfeit)
  # 0 = no timeout
  BATTLE_TIMEOUT_MINUTES = 3

  #=============================================================================
  # DATABASE SETTINGS
  #=============================================================================

  # Database file path (relative to server directory)
  DATABASE_PATH = 'pokemon_server.db'

  # Auto-backup database on server start
  AUTO_BACKUP = true

  # Keep last N backups
  MAX_BACKUPS = 7

  #=============================================================================
  # LOGGING SETTINGS
  #=============================================================================

  # Log level (DEBUG, INFO, WARN, ERROR)
  LOG_LEVEL = 'INFO'

  # Log to file instead of console
  LOG_TO_FILE = false

  # Log file path
  LOG_FILE_PATH = 'server.log'

  #=============================================================================
  # SECURITY SETTINGS
  #=============================================================================

  # Require password for login
  REQUIRE_PASSWORD = true

  # Minimum password length
  MIN_PASSWORD_LENGTH = 4

  # Maximum login attempts before temporary ban
  MAX_LOGIN_ATTEMPTS = 5

  # Ban duration in minutes
  BAN_DURATION_MINUTES = 15

  #=============================================================================
  # COMMAND SYSTEM SETTINGS
  #=============================================================================

  # Admin accounts (these users have full permissions)
  ADMIN_ACCOUNTS = ['yauhyeah', 'jjthegg']

  # Command configuration (enable/disable commands)
  COMMANDS = {
    # Player Commands
    help: { enabled: true, permission: :player, description: "Show available commands" },
    msg: { enabled: true, permission: :player, aliases: [:m, :w, :tell], description: "Send a private message" },
    reply: { enabled: true, permission: :player, aliases: [:r], description: "Reply to last private message" },
    online: { enabled: true, permission: :player, aliases: [:who, :list], description: "List online players" },
    time: { enabled: true, permission: :player, description: "Show server time" },
    spawn: { enabled: true, permission: :player, description: "Teleport to spawn point" },
    home: { enabled: true, permission: :player, description: "Teleport to your home" },
    sethome: { enabled: true, permission: :player, description: "Set your home location" },
    ping: { enabled: true, permission: :player, description: "Check your connection latency" },
    stats: { enabled: true, permission: :player, description: "View player statistics" },
    badge: { enabled: true, permission: :player, aliases: [:badges], description: "Check your badge progress" },
    playtime: { enabled: true, permission: :player, description: "Check your total playtime" },
    ignore: { enabled: true, permission: :player, description: "Ignore messages from a player" },
    unignore: { enabled: true, permission: :player, description: "Unignore a player" },
    tpa: { enabled: true, permission: :player, description: "Send teleport request to a player" },
    changepassword: { enabled: true, permission: :player, aliases: [:passwd, :changepw], description: "Change your password" },
    tpaccept: { enabled: true, permission: :player, description: "Accept pending teleport request" },
    tpdeny: { enabled: true, permission: :player, description: "Deny pending teleport request" },

    # Moderator Commands
    mute: { enabled: true, permission: :moderator, description: "Mute a player temporarily" },
    unmute: { enabled: true, permission: :moderator, description: "Unmute a player" },
    kick: { enabled: true, permission: :moderator, description: "Kick a player from the server" },
    warn: { enabled: true, permission: :moderator, description: "Warn a player" },

    # Admin Commands
    ban: { enabled: true, permission: :admin, description: "Ban a player temporarily or permanently" },
    unban: { enabled: true, permission: :admin, description: "Unban a player" },
    give: { enabled: true, permission: :admin, description: "Give items or Pokemon to a player" },
    tp: { enabled: true, permission: :admin, aliases: [:teleport], description: "Teleport to a player" },
    summon: { enabled: true, permission: :admin, description: "Summon a player to you" },
    setspawn: { enabled: true, permission: :admin, description: "Set server spawn point" },
    settime: { enabled: true, permission: :admin, description: "Set server time" },
    broadcast: { enabled: true, permission: :admin, aliases: [:announce], description: "Send server-wide announcement" },
    heal: { enabled: true, permission: :admin, description: "Heal a player's Pokemon" },
    setmoney: { enabled: true, permission: :admin, description: "Set a player's money" },
    maintenance: { enabled: true, permission: :admin, description: "Toggle maintenance mode" },
  }

  # Default mute/ban durations (in minutes)
  DEFAULT_MUTE_DURATION = 30
  DEFAULT_BAN_DURATION = 1440  # 24 hours

  #=============================================================================
  # HELPER METHODS
  #=============================================================================

  def self.get_spawn_position
    {
      map_id: DEFAULT_SPAWN_MAP,
      x: DEFAULT_SPAWN_X,
      y: DEFAULT_SPAWN_Y,
      direction: DEFAULT_SPAWN_DIRECTION
    }
  end

  def self.log_level_constant
    case LOG_LEVEL.upcase
    when 'DEBUG' then Logger::DEBUG
    when 'INFO' then Logger::INFO
    when 'WARN' then Logger::WARN
    when 'ERROR' then Logger::ERROR
    else Logger::INFO
    end
  end

  def self.is_admin?(username)
    ADMIN_ACCOUNTS.include?(username.to_s.downcase)
  end

  def self.command_enabled?(command)
    command_sym = command.to_sym
    COMMANDS[command_sym] && COMMANDS[command_sym][:enabled]
  end

  def self.get_command_permission(command)
    command_sym = command.to_sym
    COMMANDS[command_sym] ? COMMANDS[command_sym][:permission] : :admin
  end

  def self.get_command_aliases(command)
    command_sym = command.to_sym
    COMMANDS[command_sym] ? (COMMANDS[command_sym][:aliases] || []) : []
  end

  def self.find_command_by_alias(alias_name)
    alias_sym = alias_name.to_sym
    COMMANDS.each do |cmd, config|
      return cmd if config[:aliases] && config[:aliases].include?(alias_sym)
    end
    nil
  end
end

puts "[Server Config] Configuration loaded"
puts "[Server Config] Spawn: Map #{ServerConfig::DEFAULT_SPAWN_MAP} (#{ServerConfig::DEFAULT_SPAWN_X}, #{ServerConfig::DEFAULT_SPAWN_Y})"
puts "[Server Config] Max Players: #{ServerConfig::MAX_PLAYERS}"
puts "[Server Config] Port: #{ServerConfig::PORT}"
