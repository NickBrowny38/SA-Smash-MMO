if true

$multiplayer_disable_common_events  =  false

class Game_CommonEvent
  alias multiplayer_original_update update unless method_defined?(:multiplayer_original_update)

  def update
    if pbIsMultiplayerMode? && $multiplayer_disable_common_events
      return
    end

    multiplayer_original_update
  end
end

class Game_Event
  alias multiplayer_original_update update unless method_defined?(:multiplayer_original_update)

  def update
    is_touch_event = (@trigger == 1 || @trigger == 2)

    if pbIsMultiplayerMode? && $multiplayer_disable_common_events && !is_touch_event
      return
    end

    multiplayer_original_update
  end
end

end

puts "[MULTIPLAYER] Common event blocking loaded successfully"
