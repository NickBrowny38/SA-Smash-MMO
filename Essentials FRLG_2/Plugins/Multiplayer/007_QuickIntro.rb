MULTIPLAYER_QUICK_INTRO = false

def pbQuickIntro
  return unless MULTIPLAYER_QUICK_INTRO

  if !$player || $player.name.nil? || $player.name.empty?
    default_names  =  ["Red", "Ash", "Blue", "Green", "Gold", "Silver", "Crystal",
                     "Ruby", "Sapphire", "Diamond", "Pearl", "Black", "White",
                     "X", "Y", "Sun", "Moon", "Sword", "Shield"]
    random_name  =  default_names.sample + rand(100..999).to_s

    begin
      name = pbEnterPlayerName("Your name?", 0, 12, random_name)
      return name if name && !name.empty?
    rescue
    end

    return random_name
  end

  return $player.name
end

if defined?(pbMessage)
  alias multiplayer_pbMessage_original pbMessage

  def pbMessage(message, commands = nil, cmdIfCancel = 0, skin = nil, defaultCmd = 0, &block)

    if MULTIPLAYER_QUICK_INTRO && defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode? && pbMultiplayerConnected?

      if $game_switches && $game_switches[1] != true
        return (defaultCmd || cmdIfCancel) if commands
        return
      end
    end

    multiplayer_pbMessage_original(message, commands, cmdIfCancel, skin, defaultCmd, &block)
  end
end
