module HMUnlockSystem
  HM_BADGE_REQUIREMENTS = {
    :CUT       => 1,
    :FLY       => 4,
    :SURF      => 4,
    :STRENGTH  => 4,
    :FLASH     => 0,
    :ROCKSMASH => 0
  }

  HM_ITEM_MAP = {
    :HM01 => :CUT,
    :HM02 => :FLY,
    :HM03 => :SURF,
    :HM04 => :STRENGTH,
    :HM05 => :FLASH,
    :HM06 => :ROCKSMASH
  }

  HM_MOVES = [:CUT, :FLY, :SURF, :STRENGTH, :FLASH, :ROCKSMASH]

  # Cooldown to prevent rapid repeated use
  @last_hm_use_time = 0
  @hm_cooldown = 1.0  # 1 second cooldown

  def self.on_cooldown?
    now = Time.now.to_f
    if now - @last_hm_use_time < @hm_cooldown
      return true
    end
    false
  end

  def self.start_cooldown
    @last_hm_use_time = Time.now.to_f
  end

  def self.can_use_hm?(move_id)
    return false unless $player
    move_sym = move_id.is_a?(Symbol) ? move_id : (GameData::Move.get(move_id).id rescue nil)
    return false unless move_sym
    return false unless HM_MOVES.include?(move_sym)

    required_badges = HM_BADGE_REQUIREMENTS[move_sym] || 0
    current_badges = $player.badge_count rescue 0
    current_badges >= required_badges
  end

  def self.hm_unlocked?(move_sym)
    can_use_hm?(move_sym)
  end

  def self.get_required_badges(move_sym)
    HM_BADGE_REQUIREMENTS[move_sym] || 0
  end

  def self.get_hm_for_item(item_id)
    item_sym = item_id.is_a?(Symbol) ? item_id : (GameData::Item.get(item_id).id rescue nil)
    HM_ITEM_MAP[item_sym]
  end

  def self.item_is_hm?(item_id)
    !get_hm_for_item(item_id).nil?
  end

  def self.can_use_hm_item?(item_id)
    hm_move = get_hm_for_item(item_id)
    return false unless hm_move
    can_use_hm?(hm_move)
  end

  def self.use_hm_from_bar(move_sym)
    return false unless can_use_hm?(move_sym)
    return false if on_cooldown?

    start_cooldown

    case move_sym
    when :CUT
      use_cut
    when :SURF
      use_surf
    when :STRENGTH
      use_strength
    when :FLASH
      use_flash
    when :FLY
      use_fly
    when :ROCKSMASH
      use_rock_smash
    else
      pbMessage("#{move_sym} can only be used in specific locations.")
      false
    end
  end

  def self.use_cut
    facing_event = $game_player.pbFacingEvent
    if facing_event
      facing_event.start if facing_event.name.downcase.include?("cut")
      return true
    end
    pbMessage("There's nothing to Cut here.")
    false
  end

  def self.use_surf
    if $game_player.pbFacingTerrainTag.can_surf_freely
      pbSurf
      return true
    end
    pbMessage("You can't Surf here.")
    false
  end

  def self.use_strength
    pbMessage("Strength can be used on boulders.")
    false
  end

  def self.use_flash
    if $PokemonGlobal.flashUsed
      pbMessage("Flash is already being used.")
      return false
    end
    if $game_map && $game_map.metadata&.dark_map
      pbFlash
      return true
    end
    pbMessage("It's not dark here.")
    false
  end

  def self.use_fly
    if defined?(pbCanFly?) && pbCanFly?
      pbFlyToNewLocation rescue pbMessage("No destinations available.")
      return true
    end
    pbMessage("You can't use Fly here.")
    false
  end

  def self.use_rock_smash
    facing_event = $game_player.pbFacingEvent
    if facing_event && facing_event.name.downcase.include?("rock")
      facing_event.start
      return true
    end
    pbMessage("There's nothing to smash here.")
    false
  end
end

puts "[HM Unlock] HM unlock system loaded - HMs usable based on badge count"
