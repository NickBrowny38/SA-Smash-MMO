# Fix for Following Pokemon duplication during map transfers/warps
# This version ONLY removes duplicates, does NOT dispose the main follower
# The Following Pokemon EX plugin handles follower creation natively
# Note: mmo_create_following_pokemon is defined in 021_SceneMapIntegration.rb

$mmo_check_duplicates_frames = nil
$mmo_last_map_id = nil

# Check and remove ONLY DUPLICATE followers - keeps ONE follower alive
def mmo_remove_duplicate_followers_only
  return unless pbIsMultiplayerMode?
  return unless defined?(FollowingPkmn)

  removed_count = 0

  # Clean $game_temp.followers (Following Pokemon EX system) - keep LAST one only
  if $game_temp && $game_temp.respond_to?(:followers) && $game_temp.followers
    begin
      followers_obj = $game_temp.followers
      if followers_obj.respond_to?(:instance_variable_get)
        followers_array = followers_obj.instance_variable_get(:@followers)
        if followers_array && followers_array.is_a?(Array)
          pkmn_followers = followers_array.select { |f|
            f && f.respond_to?(:name) && (f.name == "FollowingPkmn" || f.name == "FollowerPkmn")
          }
          if pkmn_followers.length > 1
            puts "[Following Fix] Found #{pkmn_followers.length} followers in $game_temp - keeping last, removing #{pkmn_followers.length - 1} duplicates"
            # Keep the LAST one (most recent), remove the others
            to_remove = pkmn_followers[0..-2]
            to_remove.each do |f|
              followers_array.delete(f)
              removed_count += 1
            end
          end
        end
      end
    rescue => e
      puts "[Following Fix] Error checking $game_temp.followers: #{e.message}"
    end
  end

  # Clean $PokemonGlobal.followers (base Essentials system) - keep LAST one only
  if $PokemonGlobal && $PokemonGlobal.respond_to?(:followers) && $PokemonGlobal.followers.is_a?(Array)
    begin
      pkmn_followers = $PokemonGlobal.followers.select { |f|
        f && f.respond_to?(:name) && (f.name == "FollowingPkmn" || f.name == "FollowerPkmn")
      }
      if pkmn_followers.length > 1
        puts "[Following Fix] Found #{pkmn_followers.length} followers in $PokemonGlobal - keeping last, removing #{pkmn_followers.length - 1} duplicates"
        # Keep only the LAST one (most recent), remove others
        to_remove = pkmn_followers[0..-2]
        to_remove.each { |f| $PokemonGlobal.followers.delete(f) }
        removed_count += to_remove.length
      end
    rescue => e
      puts "[Following Fix] Error checking $PokemonGlobal.followers: #{e.message}"
    end
  end

  # Clean up duplicate character sprites in spritesets
  if $scene.is_a?(Scene_Map) && $scene.instance_variable_defined?(:@spritesets)
    spritesets = $scene.instance_variable_get(:@spritesets)
    if spritesets.is_a?(Hash)
      spritesets.each do |map_id, spriteset|
        next unless spriteset
        next unless spriteset.instance_variable_defined?(:@character_sprites)

        char_sprites = spriteset.instance_variable_get(:@character_sprites)
        next unless char_sprites.is_a?(Array)

        # Find follower sprites
        follower_sprites = char_sprites.select do |sprite|
          next false unless sprite && !sprite.disposed?
          next false unless sprite.respond_to?(:character) && sprite.character
          char = sprite.character
          char.is_a?(Game_Follower) && char.respond_to?(:name) &&
            (char.name == "FollowingPkmn" || char.name == "FollowerPkmn")
        end

        if follower_sprites.length > 1
          puts "[Following Fix] Found #{follower_sprites.length} follower sprites on map #{map_id} - disposing #{follower_sprites.length - 1} duplicates"
          # Keep only the LAST sprite, dispose others
          follower_sprites[0..-2].each do |sprite|
            sprite.dispose unless sprite.disposed?
            char_sprites.delete(sprite)
            removed_count += 1
          end
        end
      end
    end
  end

  if removed_count > 0
    puts "[Following Fix] Removed #{removed_count} duplicate followers/sprites"
  end
end

# Hook map enter - schedule duplicate check AFTER follower creation
EventHandlers.add(:on_enter_map, :mmo_schedule_follower_check,
  proc { |old_map_id|
    next unless pbIsMultiplayerMode?
    next unless defined?(FollowingPkmn)

    # Only check if we actually changed maps
    current_map = $game_map ? $game_map.map_id : nil
    if $mmo_last_map_id != current_map
      $mmo_last_map_id = current_map
      # Schedule duplicate check after enough frames for follower creation to complete
      $mmo_check_duplicates_frames = 20
      puts "[Following Fix] Map changed from #{old_map_id} to #{current_map} - scheduling duplicate check"
    end
  }
)

# Hook spriteset change - this catches connected map transitions
EventHandlers.add(:on_map_or_spriteset_change, :mmo_spriteset_follower_check,
  proc { |scene, map_changed|
    next unless pbIsMultiplayerMode?
    next unless defined?(FollowingPkmn)
    next unless map_changed

    # Schedule duplicate check after map/spriteset change
    $mmo_check_duplicates_frames = 20
    puts "[Following Fix] Spriteset changed - scheduling duplicate check"
  }
)

# Frame update - runs the duplicate check after delay
EventHandlers.add(:on_frame_update, :mmo_follower_duplicate_checker,
  proc {
    next unless pbIsMultiplayerMode?
    next unless $mmo_check_duplicates_frames

    $mmo_check_duplicates_frames -= 1
    if $mmo_check_duplicates_frames <= 0
      $mmo_check_duplicates_frames = nil
      mmo_remove_duplicate_followers_only
    end
  }
)

puts "[Following Pokemon Fix] Duplicate prevention loaded (keeps main follower, removes extras only)"
