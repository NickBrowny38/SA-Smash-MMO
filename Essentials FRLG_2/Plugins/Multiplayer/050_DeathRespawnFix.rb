DEFAULT_SPAWN_MAP = 3
DEFAULT_SPAWN_X = 7
DEFAULT_SPAWN_Y = 6
DEFAULT_SPAWN_DIR = 2

alias mmo_pbStartOver pbStartOver

def pbStartOver(gameover = false)
  return mmo_pbStartOver(gameover) unless pbIsMultiplayerMode?

  if pbInBugContest?
    pbBugContestStartOver
    return
  end

  $stats.blacked_out_count += 1
  $player.heal_party

  has_valid_pokecenter = $PokemonGlobal.pokecenterMapId &&
                         $PokemonGlobal.pokecenterMapId >= 0 &&
                         pbRgssExists?(sprintf("Data/Map%03d.rxdata", $PokemonGlobal.pokecenterMapId))

  if has_valid_pokecenter
    target_map = $PokemonGlobal.pokecenterMapId
    target_x = $PokemonGlobal.pokecenterX
    target_y = $PokemonGlobal.pokecenterY
    target_dir = $PokemonGlobal.pokecenterDirection
    message = _INTL("You scurry back to a Pokémon Center, protecting your exhausted Pokémon from any further harm...")
  else
    target_map = DEFAULT_SPAWN_MAP
    target_x = DEFAULT_SPAWN_X
    target_y = DEFAULT_SPAWN_Y
    target_dir = DEFAULT_SPAWN_DIR

    $PokemonGlobal.pokecenterMapId = target_map
    $PokemonGlobal.pokecenterX = target_x
    $PokemonGlobal.pokecenterY = target_y
    $PokemonGlobal.pokecenterDirection = target_dir

    message = _INTL("You wake up at your home, your Pokémon have been healed...")
  end

  if gameover
    pbMessage("\\w[]\\wm\\c[8]\\l[3]" + _INTL("After the unfortunate defeat, you are sent home."))
  else
    pbMessage("\\w[]\\wm\\c[8]\\l[3]" + message)
  end

  pbCancelVehicles
  Followers.clear if defined?(Followers)
  $game_switches[Settings::STARTING_OVER_SWITCH] = true if defined?(Settings::STARTING_OVER_SWITCH)
  $game_temp.player_new_map_id = target_map
  $game_temp.player_new_x = target_x
  $game_temp.player_new_y = target_y
  $game_temp.player_new_direction = target_dir
  pbDismountBike
  $scene.transfer_player if $scene.is_a?(Scene_Map)
  $game_map.refresh

  if pbMultiplayerConnected?
    pbSaveMultiplayerData
  end
end

EventHandlers.add(:on_player_creation, :set_default_spawn,
  proc {
    if pbIsMultiplayerMode?
      if !$PokemonGlobal.pokecenterMapId || $PokemonGlobal.pokecenterMapId < 0
        $PokemonGlobal.pokecenterMapId = DEFAULT_SPAWN_MAP
        $PokemonGlobal.pokecenterX = DEFAULT_SPAWN_X
        $PokemonGlobal.pokecenterY = DEFAULT_SPAWN_Y
        $PokemonGlobal.pokecenterDirection = DEFAULT_SPAWN_DIR
      end
    end
  }
)

puts "[Death Respawn Fix] Players will respawn at default location (Map #{DEFAULT_SPAWN_MAP}) if no Pokemon Center visited"
