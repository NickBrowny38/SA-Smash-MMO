def pbStartWildBattle(species, level)
  puts "[WILD BATTLE] Starting battle: #{species} level #{level}"

  if !$player || !$player.party || $player.party.length == 0
    puts '[WILD BATTLE] ERROR: Player has no Pokemon!'
    pbMessage(_INTL("You have no Pokémon!"))
    return false
  end

  can_battle = $player.party.any? { |p| p && !p.egg? && p.hp > 0 }
  if !can_battle
    puts '[WILD BATTLE] ERROR: No Pokemon can battle!'
    pbMessage(_INTL("You have no Pokémon that can battle!"))
    return false
  end

  puts "[WILD BATTLE] Player has #{$player.party.length} Pokemon, starting battle..."

  begin
    result = WildBattle.start(species, level)
    puts "[WILD BATTLE] Battle finished with result: #{result}"
    return result
  rescue => e
    puts "[WILD BATTLE] ERROR: #{e.class.name} - #{e.message}"
    puts e.backtrace[0..5].join("\n")
    pbMessage(_INTL("Battle error: {1}", e.message))
    return false
  end
end

puts '[Wild Battle Helper] Loaded - use pbStartWildBattle(:SPECIES, level) in events'
