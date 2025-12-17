SaveData.register(:game_mode) do  save_value { $game_mode }
  load_value { |value| $game_mode = value }
  new_game_value { GameMode::SINGLEPLAYER }
end

puts "Game Mode Persistence registered"
