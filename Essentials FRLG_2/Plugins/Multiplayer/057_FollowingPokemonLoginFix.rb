#===============================================================================
# Fix Following Pokemon desync after relogging
# When player logs in, reset follower position to be directly behind player
# V2 - Uses direct event access, bypasses can_check? which requires Scene_Map
#===============================================================================

# Reset follower position on login/map load
def mmo_reset_follower_position_on_login
  return unless pbIsMultiplayerMode?
  return unless defined?(FollowingPkmn)
  return unless $game_player

  # Check if follower is enabled
  return unless $PokemonGlobal && $PokemonGlobal.respond_to?(:follower_toggled) && $PokemonGlobal.follower_toggled

  puts "[Following Login Fix V2] Attempting to reset follower position on login"

  # Find the Game_FollowingPkmn object directly (bypass can_check? which requires Scene_Map)
  follower = nil
  follower_data = nil

  if $game_temp && $game_temp.respond_to?(:followers) && $game_temp.followers
    begin
      factory = $game_temp.followers

      # Method 1: Try using each_follower if available
      if factory.respond_to?(:each_follower)
        factory.each_follower do |event, data|
          if event.is_a?(Game_FollowingPkmn)
            follower = event
            follower_data = data
            puts "[Following Login Fix V2] Found follower via each_follower"
            break
          end
        end
      end

      # Method 2: Direct @events array access (fallback)
      if !follower && factory.respond_to?(:instance_variable_get)
        events_array = factory.instance_variable_get(:@events)
        if events_array && events_array.is_a?(Array)
          follower = events_array.find { |e| e.is_a?(Game_FollowingPkmn) }
          puts "[Following Login Fix V2] Found follower via @events array" if follower
        end
      end
    rescue => e
      puts "[Following Login Fix V2] Error finding follower: #{e.message}"
    end
  end

  if follower
    player_x = $game_player.x
    player_y = $game_player.y
    player_dir = $game_player.direction

    puts "[Following Login Fix V2] Found follower at (#{follower.x}, #{follower.y}), player at (#{player_x}, #{player_y})"

    # === COMPREHENSIVE FOLLOWER RESET ===

    # 1. CRITICAL FIRST: Reset the leader tracking variables
    # This MUST be done FIRST - the follower uses these to decide if it needs to "catch up"
    follower.instance_variable_set(:@last_leader_x, player_x)
    follower.instance_variable_set(:@last_leader_y, player_y)
    puts "[Following Login Fix V2] Reset @last_leader_x/y to (#{player_x}, #{player_y})"

    # 2. Clear movement states BEFORE moving
    follower.instance_variable_set(:@move_route_forcing, false)
    follower.instance_variable_set(:@wait_count, 0)

    # 3. Reset tile position to player's exact position
    follower.moveto(player_x, player_y)

    # 4. Reset real coordinates (pixel-based) - must match tile position exactly
    follower.instance_variable_set(:@real_x, player_x * Game_Map::REAL_RES_X)
    follower.instance_variable_set(:@real_y, player_y * Game_Map::REAL_RES_Y)

    # 5. Clear movement states again after move
    follower.straighten if follower.respond_to?(:straighten)

    # 6. Reset move speed to normal walking speed
    follower.move_speed = $game_player.move_speed if follower.respond_to?(:move_speed=)

    # 7. Set direction to match player
    follower.direction = player_dir if follower.respond_to?(:direction=)

    # 8. Reset step anime
    follower.step_anime = false if follower.respond_to?(:step_anime=)

    # 9. Reset pattern
    follower.instance_variable_set(:@pattern, 0)
    follower.instance_variable_set(:@anime_count, 0)

    # 10. Also update the FollowerData if we have it
    if follower_data
      follower_data.x = player_x if follower_data.respond_to?(:x=)
      follower_data.y = player_y if follower_data.respond_to?(:y=)
      follower_data.direction = player_dir if follower_data.respond_to?(:direction=)
      follower_data.current_map_id = $game_map.map_id if follower_data.respond_to?(:current_map_id=) && $game_map
      puts "[Following Login Fix V2] Updated FollowerData"
    end

    # 11. Also update $PokemonGlobal.followers FollowerData entries
    if $PokemonGlobal && $PokemonGlobal.respond_to?(:followers) && $PokemonGlobal.followers.is_a?(Array)
      $PokemonGlobal.followers.each do |f|
        next unless f && f.respond_to?(:following_pkmn?) && f.following_pkmn?
        f.x = player_x if f.respond_to?(:x=)
        f.y = player_y if f.respond_to?(:y=)
        f.direction = player_dir if f.respond_to?(:direction=)
        f.current_map_id = $game_map.map_id if f.respond_to?(:current_map_id=) && $game_map
        puts "[Following Login Fix V2] Updated $PokemonGlobal.followers entry"
      end
    end

    puts "[Following Login Fix V2] Reset complete - follower now at (#{follower.x}, #{follower.y})"
  else
    puts "[Following Login Fix V2] No follower found to reset"
  end
end

# Global flag to track if we need to reset
$mmo_follower_reset_pending = false
$mmo_follower_reset_frames = nil

# Hook into successful login - called when player data is received from server
EventHandlers.add(:on_player_change_outfit, :mmo_follower_login_reset,
  proc {
    if pbIsMultiplayerMode?
      puts "[Following Login Fix V2] on_player_change_outfit triggered - scheduling reset"
      $mmo_follower_reset_pending = true
      $mmo_follower_reset_frames = 60  # Give more time for map to fully load
    end
  }
)

# Hook map entry
EventHandlers.add(:on_enter_map, :mmo_follower_map_login_reset,
  proc { |old_map_id|
    next unless pbIsMultiplayerMode?
    next unless defined?(FollowingPkmn)

    # If this is initial login (old_map_id is -1 or nil), schedule reset
    if old_map_id.nil? || old_map_id <= 0
      puts "[Following Login Fix V2] Initial map entry detected (old_map_id: #{old_map_id}) - scheduling follower reset"
      $mmo_follower_reset_pending = true
      $mmo_follower_reset_frames = 60
    end
  }
)

# Also hook map change to reset follower on ANY map transition in multiplayer
EventHandlers.add(:on_leave_map, :mmo_follower_map_leave,
  proc { |new_map_id, new_map|
    next unless pbIsMultiplayerMode?
    next unless defined?(FollowingPkmn)

    # Schedule a reset after map transition
    puts "[Following Login Fix V2] Map transition detected - will reset follower after transfer"
    $mmo_follower_reset_pending = true
    $mmo_follower_reset_frames = 30
  }
)

# Frame update to execute delayed reset
EventHandlers.add(:on_frame_update, :mmo_follower_login_reset_update,
  proc {
    next unless pbIsMultiplayerMode?
    next unless $mmo_follower_reset_frames && $mmo_follower_reset_frames > 0

    $mmo_follower_reset_frames -= 1
    if $mmo_follower_reset_frames <= 0
      $mmo_follower_reset_frames = nil
      if $mmo_follower_reset_pending
        $mmo_follower_reset_pending = false
        mmo_reset_follower_position_on_login
      end
    end
  }
)

puts "[Following Login Fix V2] Follower position reset on login loaded - fixes desync after relogging"
