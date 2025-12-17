class MultiplayerItemPersistence
  def initialize
    @picked_up_items = {}
  end

  def register_pickup(map_id, event_id)
    key = "#{map_id}:#{event_id}"

    unless @picked_up_items[key]
      @picked_up_items[key] = true

      if pbMultiplayerConnected?
        pbMultiplayerClient.send_item_pickup(map_id, event_id)
        puts "Registered item pickup: Map #{map_id}, Event #{event_id}"
      end
    end
  end

  def picked_up?(map_id, event_id)
    key = "#{map_id}:#{event_id}"
    @picked_up_items[key] == true
  end

  def load_from_server(items_data)
    @picked_up_items.clear

    if items_data.is_a?(Array)
      items_data.each do |item_key|
        @picked_up_items[item_key]  =  true
      end
      puts "Loaded #{@picked_up_items.length} picked up items from server"
    end

    hide_picked_up_items_on_map($game_map.map_id) if $game_map
  end

  def get_picked_up_items
    @picked_up_items.keys
  end

  def hide_picked_up_items_on_map(map_id)
    return unless $game_map && $game_map.map_id == map_id

    @picked_up_items.each_key do |key|
      parts = key.split(':')
      item_map_id = parts[0].to_i
      item_event_id = parts[1].to_i

      next unless item_map_id == map_id

      event  =  $game_map.events[item_event_id]
      next unless event

      if event.name =~ /Item/i || event.character_name == 'Object ball'

        event.erase
        puts "Erased already-picked-up item: Event #{item_event_id} on Map #{map_id}"
      end
    end
  end
end

$multiplayer_item_persistence = nil

def pbMultiplayerItemPersistence
  $multiplayer_item_persistence ||= MultiplayerItemPersistence.new
  return $multiplayer_item_persistence
end

alias multiplayer_original_pbItemBall pbItemBall

def pbItemBall(item, quantity = 1)
  result = multiplayer_original_pbItemBall(item, quantity)

  if result && pbIsMultiplayerMode? && $game_map && $game_map.events[@event_id]
    pbMultiplayerItemPersistence.register_pickup($game_map.map_id, @event_id)
  end

  return result
end

class Scene_Map
  alias item_persistence_transfer_player transfer_player

  def transfer_player(cancel_swimming = true)
    item_persistence_transfer_player(cancel_swimming)

    if pbIsMultiplayerMode? && $game_map
      pbMultiplayerItemPersistence.hide_picked_up_items_on_map($game_map.map_id)
    end
  end
end

module Game_Map_ItemPersistence
  def setup(map_id)
    super

    if pbIsMultiplayerMode?
      pbMultiplayerItemPersistence.hide_picked_up_items_on_map(map_id)
    end
  end
end

class Game_Map
  prepend Game_Map_ItemPersistence
end

class MultiplayerClient
  def send_item_pickup(map_id, event_id)
    data = {
      type: :collect_item,
      data: {
        map_id: map_id,
        event_id: event_id
      }
    }
    send_message(data)
  end
end
