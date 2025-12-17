module Input
  class << self
    def reset_input_states
      @previous_states = {} if defined?(@previous_states)
    end
  end
end

EventHandlers.add(:on_start_battle, :reset_input_on_battle_start,
  proc {
    Input.reset_input_states
  }
)

EventHandlers.add(:on_end_battle, :reset_input_on_battle_end,
  proc { |decision, canLose|
    Input.reset_input_states
  }
)

class Battle
  alias mmo_input_pbStartBattle pbStartBattle

  def pbStartBattle
    Input.reset_input_states
    mmo_input_pbStartBattle
  end
end

puts "[Battle Input Fix] Input states reset on battle start/end to prevent stuck keys"
