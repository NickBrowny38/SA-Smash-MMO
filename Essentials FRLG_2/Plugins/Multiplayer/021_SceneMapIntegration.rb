# Create the Following Pokemon for multiplayer mode
# This is needed because in multiplayer, players don't go through the normal
# game start sequence that creates the initial follower
def mmo_create_following_pokemon
  return unless pbIsMultiplayerMode?
  return unless defined?(FollowingPkmn)
  return unless $player && $player.party && $player.party.length > 0
  return unless $game_map && $game_player
  return unless $game_temp && $game_temp.respond_to?(:followers)
  return unless $PokemonGlobal && $PokemonGlobal.respond_to?(:followers)

  # Check if a follower already exists
  if FollowingPkmn.respond_to?(:get) && FollowingPkmn.get
    puts "[Following] Follower already exists, just refreshing"
    $PokemonGlobal.follower_toggled = true
    FollowingPkmn.refresh(true) if FollowingPkmn.respond_to?(:refresh)
    return
  end

  # Get position behind the player
  behind_direction = 10 - $game_player.direction
  behind_x = $game_player.x
  behind_y = $game_player.y

  case behind_direction
  when 2 then behind_y -= 1  # Player facing up, follower behind (below)
  when 4 then behind_x += 1  # Player facing right, follower behind (to the right)
  when 6 then behind_x -= 1  # Player facing left, follower behind (to the left)
  when 8 then behind_y += 1  # Player facing down, follower behind (above)
  end

  # Get the first Pokemon for the follower sprite
  first_pokemon = $player.first_able_pokemon
  return unless first_pokemon

  # Get the character sprite name for this Pokemon
  species = first_pokemon.species
  form = first_pokemon.form
  shiny = first_pokemon.shiny?
  female = (first_pokemon.gender == 1)

  # Use Following Pokemon EX's sprite method if available
  char_name = ""
  if FollowingPkmn.respond_to?(:ow_sprite)
    char_name = FollowingPkmn.ow_sprite(first_pokemon) rescue ""
  end

  # Fallback sprite name construction
  if char_name.nil? || char_name == ""
    species_name = species.to_s
    char_name = "Followers/#{species_name}"
    char_name += "_#{form}" if form > 0
    char_name += "_shiny" if shiny
    char_name += "_female" if female && pbResolveBitmap("Graphics/Characters/#{char_name}_female")
  end

  puts "[Following] Creating follower for #{species} with sprite: #{char_name}"

  # Create a FollowerData object
  # FollowerData.new(original_map_id, event_id, event_name, current_map_id, x, y, direction, char_name, char_hue)
  event_id = -100  # Use a negative ID to avoid conflicts with real events

  follower_data = FollowerData.new(
    $game_map.map_id,     # original_map_id
    event_id,             # event_id (fake)
    "FollowingPkmn",      # event_name - IMPORTANT: must contain "FollowingPkmn" for following_pkmn? to work
    $game_map.map_id,     # current_map_id
    behind_x,             # x
    behind_y,             # y
    $game_player.direction, # direction (face same way as player)
    char_name,            # character_name
    0                     # character_hue
  )

  follower_data.name = "FollowingPkmn"  # Set the name for following_pkmn? check

  # Add to $PokemonGlobal.followers
  $PokemonGlobal.followers ||= []

  # Remove any existing FollowingPkmn entries first
  $PokemonGlobal.followers.delete_if { |f| f.respond_to?(:name) && f.name == "FollowingPkmn" }

  $PokemonGlobal.followers.push(follower_data)

  # Create the Game_FollowingPkmn object via the factory
  if $game_temp.followers.respond_to?(:create_follower_object)
    begin
      # Access the private method
      new_event = $game_temp.followers.send(:create_follower_object, follower_data)
      if new_event
        events_array = $game_temp.followers.instance_variable_get(:@events)
        events_array ||= []
        events_array.push(new_event)
        $game_temp.followers.instance_variable_set(:@events, events_array)
        $game_temp.followers.instance_variable_set(:@last_update, ($game_temp.followers.instance_variable_get(:@last_update) || 0) + 1)
        puts "[Following] Created Game_FollowingPkmn event"
      end
    rescue => e
      puts "[Following] Error creating follower object: #{e.message}"
    end
  end

  # Enable the follower toggle
  $PokemonGlobal.follower_toggled = true

  # Refresh the follower to update sprite
  FollowingPkmn.refresh(true) if FollowingPkmn.respond_to?(:refresh)

  puts "[Following] Following Pokemon created successfully for multiplayer"
end

class Scene_Map
  alias multiplayer_consolidated_update update unless method_defined?(:multiplayer_consolidated_update)
  alias multiplayer_original_main main unless method_defined?(:multiplayer_original_main)

  def main
    if pbIsMultiplayerMode? && !$multiplayer_music_enabled
      $game_map.define_singleton_method(:autoplay) { } if $game_map
    end

    multiplayer_original_main

    if pbIsMultiplayerMode? && $game_map
      # Safely remove the singleton method if it exists
      begin
        $game_map.singleton_class.send(:remove_method, :autoplay) if $game_map.singleton_methods.include?(:autoplay)
      rescue NameError
        # Method wasn't defined as singleton, ignore
      end
    end
  end

  def update

    multiplayer_consolidated_update

    return unless pbIsMultiplayerMode?

    if $multiplayer_play_music_on_first_update && $game_map
      $multiplayer_play_music_on_first_update = false
      $multiplayer_music_enabled = true
      $game_map.autoplay
      puts "[MUSIC] Playing map BGM after login complete"
    end

    if $multiplayer_notifications
      $multiplayer_notifications.update
      $multiplayer_notifications.draw
    end

    if pbMultiplayerConnected?
      pbMultiplayerClient.update
      @was_connected = true

      $multiplayer_chat ||= MultiplayerChat.new

      if $multiplayer_chat

        if !@chat_viewport
          @chat_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
          @chat_viewport.z  =  99999
        end

        if !$multiplayer_chat.instance_variable_get(:@sprite)
          $multiplayer_chat.initialize_sprite(@chat_viewport)
        end
      end

      # Initialize Following Pokemon via the EX plugin after multiplayer login
      if defined?($multiplayer_needs_follower_init) && $multiplayer_needs_follower_init
        $multiplayer_needs_follower_init = false

        # Create the follower properly for multiplayer mode
        if defined?(FollowingPkmn) && $player && $player.party && $player.party.length > 0
          begin
            mmo_create_following_pokemon
          rescue => e
            puts "[Following] Error initializing follower: #{e.message}"
            puts e.backtrace.first(5).join("\n")
          end
        end
      end

      if $multiplayer_chat

        if Input.triggerex?(0x54)
          $multiplayer_chat.open_input
        end

        if Input.triggerex?(0xBF)
          pbOpenMultiplayerChat("/")
        end

        if Input.triggerex?(0x48)
          $multiplayer_chat.toggle_chat
        end

        if Input.press?(Input::SHIFT)
          if Input.trigger?(Input::UP)
            $multiplayer_chat.scroll_up
          elsif Input.trigger?(Input::DOWN)
            $multiplayer_chat.scroll_down
          end
        end

        $multiplayer_chat.update
        $multiplayer_chat.draw
      end

      if defined?(Input::TAB) && pbWindowHasFocus?
        player_list = pbMultiplayerPlayerList
        if player_list
          if Input.press?(Input::TAB)
            player_list.show unless player_list.visible?
            player_list.update
          else
            player_list.hide if player_list.visible?
          end
        end
      end

      pbMultiplayerQuickMenu.update if defined?(pbMultiplayerQuickMenu)

      pbModernTradeManager.update if defined?(pbModernTradeManager)

      if defined?(FollowingPkmn) && defined?(MultiplayerFollowerManager)

        if !$multiplayer_follower_manager && @remote_player_manager
          if !@follower_viewport
            @follower_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
            @follower_viewport.z  =  99998
          end
          $multiplayer_follower_manager = MultiplayerFollowerManager.new(@follower_viewport)
          puts "[Following] Follower manager initialized for multiplayer"
        end

        if $multiplayer_follower_manager && @remote_player_manager
          remote_players = @remote_player_manager.instance_variable_get(:@remote_players)
          $multiplayer_follower_manager.update(remote_players)
        end
      end
    else

      @was_connected ||= false
      if @was_connected

        puts "Lost connection to server - showing disconnect screen"

        reason = nil
        if pbMultiplayerClient && pbMultiplayerClient.respond_to?(:get_last_error)
          reason = pbMultiplayerClient.get_last_error
        end
        reason ||= "Connection to server lost. The server may be offline or your internet connection was interrupted."

        if defined?(MultiplayerDisconnectHandler)
          MultiplayerDisconnectHandler.handle_disconnect(reason)
        else

          pbMessage(_INTL("Lost connection to server!\\nReturning to title screen..."))
          $scene = pbCallTitle
        end

        @was_connected = false
      end
    end
  end

  alias multiplayer_consolidated_dispose dispose unless method_defined?(:multiplayer_consolidated_dispose)

  def dispose

    if $multiplayer_chat
      $multiplayer_chat.dispose
      $multiplayer_chat = nil
    end

    if @chat_viewport
      @chat_viewport.dispose
      @chat_viewport = nil
    end

    if $multiplayer_follower_manager
      $multiplayer_follower_manager.dispose
      $multiplayer_follower_manager = nil
    end

    if @follower_viewport
      @follower_viewport.dispose
      @follower_viewport = nil
    end

    multiplayer_consolidated_dispose
  end
end
