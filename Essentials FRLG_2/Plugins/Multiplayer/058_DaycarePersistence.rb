#===============================================================================
# Daycare Pokemon Persistence for Multiplayer V2
# Saves and loads daycare Pokemon to/from the server
# Uses EventHandlers instead of alias_method for reliability
#===============================================================================

module MultiplayerDaycare
  # Serialize daycare data for sending to server
  def self.serialize
    return nil unless $PokemonGlobal && $PokemonGlobal.respond_to?(:day_care)

    daycare = $PokemonGlobal.day_care
    return nil unless daycare

    daycare_data = {
      egg_generated: daycare.egg_generated ? 1 : 0,
      step_counter: daycare.step_counter || 0,
      slots: []
    }

    daycare.slots.each_with_index do |slot, index|
      if slot.filled? && slot.pokemon
        pkmn = slot.pokemon
        initial_level = slot.instance_variable_get(:@initial_level) || pkmn.level

        # Serialize the Pokemon using the full serialization method
        if defined?(pbModernTradeManager) && pbModernTradeManager.respond_to?(:serialize_pokemon)
          pkmn_data = pbModernTradeManager.serialize_pokemon(pkmn)
        else
          pkmn_data = serialize_pokemon_basic(pkmn)
        end

        daycare_data[:slots] << {
          slot_index: index,
          initial_level: initial_level,
          pokemon: pkmn_data
        }
      end
    end

    return daycare_data
  end

  # Basic Pokemon serialization fallback
  def self.serialize_pokemon_basic(pkmn)
    return nil unless pkmn
    {
      species: pkmn.species.to_s,
      level: pkmn.level,
      name: pkmn.name,
      hp: pkmn.hp,
      exp: pkmn.exp,
      gender: pkmn.gender,
      nature: pkmn.nature ? pkmn.nature.id.to_s : nil,
      ability_index: pkmn.ability_index,
      item: pkmn.item ? pkmn.item.to_s : nil,
      moves: pkmn.moves.map { |m| m ? { id: m.id.to_s, pp: m.pp, ppup: m.ppup } : nil }.compact,
      iv: pkmn.iv.dup,
      ev: pkmn.ev.dup,
      ot_name: pkmn.owner.name,
      ot_id: pkmn.owner.id,
      shiny: pkmn.shiny?,
      form: pkmn.form,
      happiness: pkmn.happiness,
      poke_ball: pkmn.poke_ball ? pkmn.poke_ball.to_s : "POKEBALL"
    }
  end

  # Load daycare data from server response
  def self.load(daycare_data)
    return unless daycare_data
    return unless $PokemonGlobal && $PokemonGlobal.respond_to?(:day_care)

    puts "[Daycare V2] Loading daycare data from server..."

    # Initialize daycare if needed
    $PokemonGlobal.day_care ||= DayCare.new
    daycare = $PokemonGlobal.day_care

    # Clear existing slots
    daycare.slots.each { |slot| slot.reset }

    # Load egg counters (handle both symbol and string keys)
    egg_gen = daycare_data[:egg_generated] || daycare_data['egg_generated']
    daycare.egg_generated = (egg_gen == 1 || egg_gen == true)

    step_count = daycare_data[:step_counter] || daycare_data['step_counter']
    daycare.step_counter = step_count.to_i if step_count

    # Load slot Pokemon
    slots_data = daycare_data[:slots] || daycare_data['slots'] || []
    slots_data.each do |slot_entry|
      slot_index = slot_entry[:slot_index] || slot_entry['slot_index']
      initial_level = slot_entry[:initial_level] || slot_entry['initial_level']
      pkmn_data = slot_entry[:pokemon] || slot_entry['pokemon']

      next unless slot_index && pkmn_data
      next unless slot_index >= 0 && slot_index < DayCare::MAX_SLOTS

      # Deserialize the Pokemon
      pokemon = nil
      if defined?(pbModernTradeManager) && pbModernTradeManager.respond_to?(:deserialize_pokemon)
        pokemon = pbModernTradeManager.deserialize_pokemon(pkmn_data)
      else
        pokemon = deserialize_pokemon_basic(pkmn_data)
      end

      if pokemon
        # Deposit the Pokemon into the slot
        slot = daycare.slots[slot_index]
        slot.instance_variable_set(:@pokemon, pokemon)
        slot.instance_variable_set(:@initial_level, initial_level || pokemon.level)
        puts "[Daycare V2] Loaded Pokemon into slot #{slot_index}: #{pokemon.species} Lv.#{pokemon.level}"
      end
    end

    puts "[Daycare V2] Loaded daycare from server: #{slots_data.size} Pokemon, egg_generated: #{daycare.egg_generated}"
  end

  # Basic Pokemon deserialization fallback
  def self.deserialize_pokemon_basic(data)
    return nil unless data

    species = data[:species] || data['species']
    return nil unless species

    level = (data[:level] || data['level'] || 5).to_i

    begin
      pokemon = Pokemon.new(species.to_sym, level)

      # Set basic attributes
      pokemon.name = data[:name] || data['name'] if data[:name] || data['name']
      pokemon.hp = (data[:hp] || data['hp']).to_i if data[:hp] || data['hp']

      return pokemon
    rescue => e
      puts "[Daycare V2] Error deserializing Pokemon: #{e.message}"
      return nil
    end
  end

  # Send daycare data to server
  def self.send_to_server
    return unless pbMultiplayerConnected?
    return unless $multiplayer_client

    daycare_data = serialize
    if daycare_data && daycare_data[:slots] && daycare_data[:slots].size > 0
      $multiplayer_client.send_message(MultiplayerProtocol.create_message('daycare_update', { daycare: daycare_data }))
      puts "[Daycare V2] Sent daycare data to server: #{daycare_data[:slots].size} Pokemon"
      return true
    else
      puts "[Daycare V2] No Pokemon in daycare to send"
      return false
    end
  end
end

# Global tracking for daycare changes
$mmo_daycare_last_state = nil
$mmo_daycare_check_timer = 0

# Check if daycare state changed (called periodically)
def mmo_check_daycare_changed
  return false unless $PokemonGlobal && $PokemonGlobal.respond_to?(:day_care) && $PokemonGlobal.day_care

  daycare = $PokemonGlobal.day_care
  current_state = []

  daycare.slots.each_with_index do |slot, i|
    if slot.filled? && slot.pokemon
      current_state << "#{i}:#{slot.pokemon.species}:#{slot.pokemon.level}"
    end
  end
  current_state << "egg:#{daycare.egg_generated}"

  state_string = current_state.join(",")

  if $mmo_daycare_last_state != state_string
    $mmo_daycare_last_state = state_string
    return true
  end

  return false
end

# Hook into frame update to periodically check daycare state
EventHandlers.add(:on_frame_update, :mmo_daycare_persistence_check,
  proc {
    next unless pbIsMultiplayerMode?
    next unless pbMultiplayerConnected?

    # Check every 60 frames (about 1 second)
    $mmo_daycare_check_timer = ($mmo_daycare_check_timer || 0) + 1
    next unless $mmo_daycare_check_timer >= 60
    $mmo_daycare_check_timer = 0

    # If daycare changed, send update
    if mmo_check_daycare_changed
      puts "[Daycare V2] Daycare state changed - sending update"
      MultiplayerDaycare.send_to_server
    end
  }
)

# Hook into player data save to include daycare
EventHandlers.add(:on_player_interact, :mmo_daycare_save_on_interact,
  proc {
    next unless pbIsMultiplayerMode?
    next unless pbMultiplayerConnected?

    # Send daycare data after any interaction (might have deposited/withdrew)
    if $PokemonGlobal && $PokemonGlobal.respond_to?(:day_care) && $PokemonGlobal.day_care
      daycare = $PokemonGlobal.day_care
      has_pokemon = daycare.slots.any? { |slot| slot.filled? }
      if has_pokemon
        MultiplayerDaycare.send_to_server
      end
    end
  }
)

# Hook into map change to save daycare
EventHandlers.add(:on_leave_map, :mmo_daycare_save_on_map_change,
  proc { |new_map_id, new_map|
    next unless pbIsMultiplayerMode?
    next unless pbMultiplayerConnected?

    # Send daycare data on map change
    MultiplayerDaycare.send_to_server
  }
)

# Direct hook for when Pokemon are deposited/withdrawn from daycare
# Override DayCare methods to trigger saves
if defined?(DayCare)
  class DayCare
    # Store original deposit method
    if !method_defined?(:deposit_pokemon_original_mmo)
      alias_method :deposit_pokemon_original_mmo, :deposit if method_defined?(:deposit)
    end

    def deposit(pkmn, *args)
      result = deposit_pokemon_original_mmo(pkmn, *args)
      # Trigger daycare save after deposit
      if pbIsMultiplayerMode? && pbMultiplayerConnected?
        puts "[Daycare V2] Pokemon deposited - scheduling save"
        $mmo_daycare_save_pending = true
      end
      result
    end

    # Store original withdraw method
    if !method_defined?(:withdraw_pokemon_original_mmo)
      alias_method :withdraw_pokemon_original_mmo, :withdraw if method_defined?(:withdraw)
    end

    def withdraw(slot, *args)
      result = withdraw_pokemon_original_mmo(slot, *args)
      # Trigger daycare save after withdraw
      if pbIsMultiplayerMode? && pbMultiplayerConnected?
        puts "[Daycare V2] Pokemon withdrawn - scheduling save"
        $mmo_daycare_save_pending = true
      end
      result
    end
  end
end

# Process pending daycare saves
EventHandlers.add(:on_frame_update, :mmo_daycare_pending_save,
  proc {
    next unless $mmo_daycare_save_pending
    $mmo_daycare_save_pending = false

    # Wait a few frames then save
    $mmo_daycare_save_delay = 10
  }
)

EventHandlers.add(:on_frame_update, :mmo_daycare_delayed_save,
  proc {
    next unless $mmo_daycare_save_delay && $mmo_daycare_save_delay > 0
    $mmo_daycare_save_delay -= 1

    if $mmo_daycare_save_delay <= 0
      $mmo_daycare_save_delay = nil
      MultiplayerDaycare.send_to_server
    end
  }
)

puts "[Daycare Persistence V2] Daycare multiplayer persistence loaded"
