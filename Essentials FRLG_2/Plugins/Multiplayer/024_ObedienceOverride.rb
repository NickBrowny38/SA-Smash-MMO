class Battle::Battler
  alias multiplayer_obedience_check? pbObedienceCheck?

  def pbObedienceCheck?(choice)
    if defined?(pbMultiplayerConnected?) && pbMultiplayerConnected?
      return true
    end

    return multiplayer_obedience_check?(choice)
  end
end

puts "Multiplayer: Obedience system disabled - all Pokemon obey in multiplayer mode"
