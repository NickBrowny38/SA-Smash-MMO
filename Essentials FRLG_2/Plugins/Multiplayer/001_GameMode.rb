module GameMode
  SINGLEPLAYER = :singleplayer
  MULTIPLAYER = :multiplayer
end

$game_mode = GameMode::SINGLEPLAYER

def pbIsMultiplayerMode?

  $game_mode == GameMode::MULTIPLAYER
end

def pbIsSingleplayerMode?
  $game_mode == GameMode::SINGLEPLAYER || $game_mode.nil?
end

def pbSetGameMode(mode)
  if mode != GameMode::SINGLEPLAYER && mode != GameMode::MULTIPLAYER
    raise "Invalid game mode: #{mode}"
  end
  $game_mode = mode
  puts "Game mode set to: #{mode}"
end

def pbGetGameMode
  $game_mode
end

def pbMultiplayerActive?
  pbIsMultiplayerMode? && pbMultiplayerConnected?
end

puts 'Game Mode system initialized'
