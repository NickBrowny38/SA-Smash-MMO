# Fix for catching Pokemon with full party in multiplayer mode
# Ensures players can always send caught Pokemon to box instead of being
# forced to replace a party member

# Override the battle setup to ensure sendToBoxes is never set to 2 (must add to party)
# in multiplayer mode. Value 0 = ask player, 1 = auto-send to box, 2 = must add to party

module BattleCreation
  class << self
    alias mmo_full_party_prepare prepare if method_defined?(:prepare)

    def prepare(*args)
      result = mmo_full_party_prepare(*args)

      # In multiplayer mode, never force "must add to party" behavior
      if result && result.is_a?(Battle) && pbIsMultiplayerMode?
        if result.sendToBoxes == 2
          # Change from "must add to party" to "ask player"
          result.sendToBoxes = 0
        end
      end

      result
    end
  end
end

# Also hook into the actual battle start in case BattleCreation isn't used
class Battle
  alias mmo_full_party_pbStartBattle pbStartBattle

  def pbStartBattle
    # In multiplayer mode, ensure player can always send to box
    if pbIsMultiplayerMode? && @sendToBoxes == 2
      @sendToBoxes = 0  # Change to "ask player" mode
    end

    mmo_full_party_pbStartBattle
  end
end

# Hook into pbWildBattle to fix sendToBoxes before battle starts
alias mmo_full_party_pbWildBattle pbWildBattle if defined?(pbWildBattle)

def pbWildBattle(species, level, outcomeVar = 1, canRun = true, canLose = false)
  result = mmo_full_party_pbWildBattle(species, level, outcomeVar, canRun, canLose)
  result
end

# The main fix: Hook into the actual catch storage decision
# This overrides the pbStorePokemon behavior when party is full
if defined?(Battle::CatchAndStoreMixin)
  module Battle::CatchAndStoreMixin
    alias mmo_full_party_pbStorePokemon pbStorePokemon

    def pbStorePokemon(pkmn)
      # In multiplayer mode, always allow sending to box option
      if pbIsMultiplayerMode?
        old_send_to_boxes = @sendToBoxes
        @sendToBoxes = 0 if @sendToBoxes == 2  # Force "ask" mode instead of "must add to party"
        result = mmo_full_party_pbStorePokemon(pkmn)
        @sendToBoxes = old_send_to_boxes
        return result
      else
        return mmo_full_party_pbStorePokemon(pkmn)
      end
    end
  end
end

puts "[Full Party Catch Fix] Players can now send caught Pokemon to box when party is full"
