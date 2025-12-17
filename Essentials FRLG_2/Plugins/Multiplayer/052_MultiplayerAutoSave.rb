#===============================================================================
# Auto-save triggers for multiplayer - ensures data persists after battles/purchases
#===============================================================================

# Helper function to save multiplayer data to server
def pbSaveMultiplayerData
  return unless pbMultiplayerConnected?
  return unless defined?(pbMultiplayerClient) && pbMultiplayerClient

  begin
    pbMultiplayerClient.send_player_data
    puts "[MP Save] Saved player data to server"
  rescue => e
    puts "[MP Save] Error saving: #{e.message}"
  end
end

# Trigger save after battle ends
EventHandlers.add(:on_end_battle, :multiplayer_battle_save,
  proc { |decision, canLose|
    if pbIsMultiplayerMode? && pbMultiplayerConnected?
      # Save immediately after battle to persist rewards, trainer flags, etc.
      pbSaveMultiplayerData
      puts "[MP Save] Auto-saved after battle (decision: #{decision})"
    end
  }
)

# Trigger save after party changes
EventHandlers.add(:on_player_change_party, :multiplayer_party_save,
  proc {
    if pbIsMultiplayerMode? && pbMultiplayerConnected?
      pbSaveMultiplayerData
      puts "[MP Save] Auto-saved after party change"
    end
  }
)

# Track state for auto-save
module MultiplayerAutoSave
  @last_saved_money = nil
  @last_item_count = nil
  @last_badge_count = nil

  def self.check_and_save_if_needed
    return unless pbIsMultiplayerMode? && pbMultiplayerConnected?
    return unless defined?($player) && $player

    current_money = $player.money rescue 0
    current_items = count_bag_items rescue 0
    current_badges = $player.badge_count rescue 0

    # Initialize on first check
    if @last_saved_money.nil?
      @last_saved_money = current_money
      @last_item_count = current_items
      @last_badge_count = current_badges
      return
    end

    # Save if money changed
    if current_money != @last_saved_money
      puts "[MP Save] Money changed: #{@last_saved_money} -> #{current_money}"
      @last_saved_money = current_money
      pbSaveMultiplayerData
      return
    end

    # Save if item count changed (item obtained or used)
    if current_items != @last_item_count
      puts "[MP Save] Items changed: #{@last_item_count} -> #{current_items}"
      @last_item_count = current_items
      pbSaveMultiplayerData
      return
    end

    # Save if badges changed
    if current_badges != @last_badge_count
      puts "[MP Save] Badges changed: #{@last_badge_count} -> #{current_badges}"
      @last_badge_count = current_badges
      pbSaveMultiplayerData
      return
    end
  end

  def self.count_bag_items
    return 0 unless $bag
    total = 0
    $bag.pockets.each do |pocket|
      next unless pocket
      pocket.each { |item| total += item[1] if item }
    end
    total
  end

  def self.force_save
    @last_saved_money = $player.money rescue 0
    @last_item_count = count_bag_items
    @last_badge_count = $player.badge_count rescue 0
    pbSaveMultiplayerData
  end

  def self.reset_tracking
    @last_saved_money = $player.money rescue 0
    @last_item_count = count_bag_items
    @last_badge_count = $player.badge_count rescue 0
  end
end

# Hook into item gain/loss
alias mp_autosave_pbReceiveItem pbReceiveItem unless defined?(mp_autosave_pbReceiveItem)
def pbReceiveItem(item, quantity = 1)
  ret = mp_autosave_pbReceiveItem(item, quantity)
  if ret && pbIsMultiplayerMode? && pbMultiplayerConnected?
    pbSaveMultiplayerData
    puts "[MP Save] Auto-saved after receiving item: #{item}"
  end
  ret
end

# Periodic save check in Scene_Map
class Scene_Map
  alias mp_autosave_update update unless method_defined?(:mp_autosave_update)

  def update
    mp_autosave_update

    # Check every 180 frames (about 3 seconds)
    @mp_autosave_timer ||= 0
    @mp_autosave_timer += 1

    if @mp_autosave_timer >= 180
      @mp_autosave_timer = 0
      MultiplayerAutoSave.check_and_save_if_needed if pbIsMultiplayerMode?
    end
  end
end

puts "[MP AutoSave] Auto-save triggers loaded - saves after battles, items, money, and badge changes"
