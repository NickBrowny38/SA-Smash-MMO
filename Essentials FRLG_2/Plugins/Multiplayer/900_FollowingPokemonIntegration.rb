puts "[Multiplayer] Loading Following Pokemon integration (will activate if plugin present)"

class MultiplayerClient
    attr_accessor :other_player_followers

    alias multiplayer_following_initialize initialize
    def initialize
      multiplayer_following_initialize
      @other_player_followers = {}
      @last_sent_follower_species = nil
    end

    alias multiplayer_following_send_position_update send_position_update unless method_defined?(:multiplayer_following_send_position_update)

    def send_position_update
      return unless @connected
      return unless $game_player
      return unless $player

      follower_pokemon = nil
      if defined?(FollowingPkmn) && $player && $player.party && $player.party.length > 0
        if $PokemonGlobal && $PokemonGlobal.respond_to?(:follower_toggled) && $PokemonGlobal.follower_toggled
          follower_pokemon  =  $player.first_able_pokemon
        end
      end

      current_state = {
        map: $game_player.map.map_id,
        x: $game_player.x,
        y: $game_player.y,
        real_x: $game_player.real_x,
        real_y: $game_player.real_y,
        dir: $game_player.direction,
        charset: get_charset_name
      }

      current_state[:follower_species] = follower_pokemon ? follower_pokemon.species : nil

      if @last_position_state == current_state
        return
      end
      @last_position_state = current_state.dup

      player_data = {
        map_id: $game_player.map.map_id,
        x: $game_player.x,
        y: $game_player.y,
        real_x: $game_player.real_x,
        real_y: $game_player.real_y,
        direction: $game_player.direction,
        pattern: $game_player.pattern,
        move_speed: $game_player.move_speed,
        movement_type: get_movement_type,
        charset: get_charset_name
      }

      if follower_pokemon

        current_species = follower_pokemon.species
        player_data[:follower] = {
          species: current_species,
          shiny: follower_pokemon.shiny?,
          form: follower_pokemon.form
        }

        @last_sent_follower_species = current_species

        unless @following_logged
          puts "[Following] CLIENT: Sending follower data: #{player_data[:follower].inspect}"
          @following_logged  =  true
        end
      else

        if @last_sent_follower_species
          puts "[Following] Follower removed (was #{@last_sent_follower_species}), sending nil"
          player_data[:follower] = nil
          @last_sent_follower_species = nil
        end

      end

      send_message(MultiplayerProtocol.position_update_message(player_data))
    end

  end

EventHandlers.add(:on_enter_map, :multiplayer_following_pokemon_map_change,
  proc { |old_map_id|

    if pbIsMultiplayerMode? && defined?(FollowingPkmn) && $player && $player.party && $player.party.length > 0

      if $PokemonGlobal && $PokemonGlobal.respond_to?(:follower_toggled) && $PokemonGlobal.follower_toggled

        $multiplayer_needs_follower_init = true
        puts "[Following] Map changed - will reinitialize follower"
      end
    end
  }
)

puts "[Multiplayer] Following Pokemon integration loaded (will activate at runtime if plugin present)"
