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

    # Calculate position behind the player
    behind_x = player_x
    behind_y = player_y
    case player_dir
    when 2 then behind_y -= 1  # Player facing down, follower above
    when 4 then behind_x += 1  # Player facing left, follower to right
    when 6 then behind_x -= 1  # Player facing right, follower to left
    when 8 then behind_y += 1  # Player facing up, follower below
    end

    puts "[Following Login Fix V2] Found follower at (#{follower.x}, #{follower.y}), moving to (#{behind_x}, #{behind_y})"

    # === COMPREHENSIVE FOLLOWER RESET ===

    # 1. CRITICAL FIRST: Reset the leader tracking variables to current player position
    # This tells the follower "the leader is here" so it doesn't try to catch up
    follower.instance_variable_set(:@last_leader_x, player_x)
    follower.instance_variable_set(:@last_leader_y, player_y)

    # 2. Clear movement states BEFORE moving
    follower.instance_variable_set(:@move_route_forcing, false)
    follower.instance_variable_set(:@wait_count, 0)

    # 3. Reset tile position to BEHIND the player
    follower.moveto(behind_x, behind_y)

    # 4. Reset real coordinates (pixel-based) - must match tile position exactly
    follower.instance_variable_set(:@real_x, behind_x * Game_Map::REAL_RES_X)
    follower.instance_variable_set(:@real_y, behind_y * Game_Map::REAL_RES_Y)

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
      follower_data.x = behind_x if follower_data.respond_to?(:x=)
      follower_data.y = behind_y if follower_data.respond_to?(:y=)
      follower_data.direction = player_dir if follower_data.respond_to?(:direction=)
      follower_data.current_map_id = $game_map.map_id if follower_data.respond_to?(:current_map_id=) && $game_map
      puts "[Following Login Fix V2] Updated FollowerData"
    end

    # 11. Also update $PokemonGlobal.followers FollowerData entries
    if $PokemonGlobal && $PokemonGlobal.respond_to?(:followers) && $PokemonGlobal.followers.is_a?(Array)
      $PokemonGlobal.followers.each do |f|
        next unless f && f.respond_to?(:following_pkmn?) && f.following_pkmn?
        f.x = behind_x if f.respond_to?(:x=)
        f.y = behind_y if f.respond_to?(:y=)
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

# Global flag to track if follower needs position sync
$mmo_follower_needs_sync = true
$mmo_follower_sync_cooldown = 0

# Hook into successful login
EventHandlers.add(:on_player_change_outfit, :mmo_follower_login_reset,
  proc {
    if pbIsMultiplayerMode?
      $mmo_follower_needs_sync = true
      $mmo_follower_sync_cooldown = 0
    end
  }
)

# Hook map entry
EventHandlers.add(:on_enter_map, :mmo_follower_map_login_reset,
  proc { |old_map_id|
    next unless pbIsMultiplayerMode?
    next unless defined?(FollowingPkmn)
    $mmo_follower_needs_sync = true
    $mmo_follower_sync_cooldown = 0
  }
)

module MMOFollowerSyncPatch
  def follow_leader(leader, instant = false, leaderIsTrueLeader = true)
    if pbIsMultiplayerMode?
      if $mmo_follower_sync_cooldown && $mmo_follower_sync_cooldown > 0
        $mmo_follower_sync_cooldown -= 1
        @last_leader_x = leader.x
        @last_leader_y = leader.y
        return
      end

      if $mmo_follower_needs_sync
        $mmo_follower_needs_sync = false
        $mmo_follower_sync_cooldown = 15

        player_x = leader.x
        player_y = leader.y
        player_dir = leader.direction

        behind_x = player_x
        behind_y = player_y
        behind_dir = 10 - player_dir
        case behind_dir
        when 2 then behind_y -= 1
        when 4 then behind_x -= 1
        when 6 then behind_x += 1
        when 8 then behind_y += 1
        end

        @last_leader_x = player_x
        @last_leader_y = player_y
        @move_route_forcing = false
        @through = false
        @move_speed = leader.move_speed
        moveto(behind_x, behind_y)
        @real_x = behind_x * Game_Map::REAL_RES_X
        @real_y = behind_y * Game_Map::REAL_RES_Y
        @pattern = 0
        @anime_count = 0
        @step_anime = false
        @moved_last_frame = false
        @moved_this_frame = false
        straighten if respond_to?(:straighten)
        end_movement if respond_to?(:end_movement)
        calculate_bush_depth if respond_to?(:calculate_bush_depth)
        return
      end
    end

    super(leader, instant, leaderIsTrueLeader)
  end
end

$mmo_follower_patch_applied = false

EventHandlers.add(:on_game_start, :mmo_apply_follower_patch,
  proc {
    next if $mmo_follower_patch_applied
    next unless defined?(Game_FollowingPkmn)
    Game_FollowingPkmn.prepend(MMOFollowerSyncPatch)
    $mmo_follower_patch_applied = true
    puts "[Following Login Fix] Patch applied to Game_FollowingPkmn"
  }
)

if defined?(Game_FollowingPkmn)
  Game_FollowingPkmn.prepend(MMOFollowerSyncPatch)
  $mmo_follower_patch_applied = true
end

puts "[Following Login Fix V2] Follower position reset on login loaded"
