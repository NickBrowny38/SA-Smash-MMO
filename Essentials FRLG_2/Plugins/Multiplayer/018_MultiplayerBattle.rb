class MultiplayerBattleManager
  attr_reader :battle_cooldown_until

  def initialize
    @pending_requests = []
    @active_battle = false
    @sent_request  =  nil
    @request_ui = nil
    @battle_cooldown_until = nil
  end

  def in_cooldown?
    return false unless @battle_cooldown_until
    Time.now < @battle_cooldown_until
  end

  def cooldown_remaining
    return 0 unless @battle_cooldown_until
    remaining = (@battle_cooldown_until - Time.now).ceil
    [remaining, 0].max
  end

  def start_synchronized_battle(opponent_id, opponent_name, format, opponent_party_data, rng_seed, battle_id, is_host)
    @active_battle = true

    $multiplayer_battle_forfeited = false
    $multiplayer_opponent_choice_received = false
    $multiplayer_opponent_choice_data = nil

    puts "[MP BATTLE] Starting SYNCHRONIZED battle ##{battle_id}"
    puts "[MP BATTLE] RNG Seed: #{rng_seed}, Is Host: #{is_host}"

    opponent_trainer = NPCTrainer.new(opponent_name, :POKEMONTRAINER_Red)
    opponent_trainer.party = []

    opponent_party_data.each do |pokemon_data|
      pokemon = pbModernTradeManager.deserialize_pokemon(pokemon_data)
      opponent_trainer.party << pokemon
    end

    if opponent_trainer.party.empty?
      pbMessage(_INTL("ERROR: Opponent has no valid Pokemon!\\nBattle cancelled."))
      @active_battle = false
      return false
    end

    pbMessage(_INTL("Starting synchronized battle with {1}!\\nGood luck!", opponent_name))

    setBattleRule("single")
    case format
    when :double
      setBattleRule("double")
    when :triple
      setBattleRule("triple")
    when :rotation
      setBattleRule("rotation")
    end

    setBattleRule("noExp")
    setBattleRule('noMoney')
    setBattleRule("setStyle")  # CRITICAL: Disable switch prompt after opponent KO
    puts "[MP BATTLE] Set battle style enforced - no switch prompts during battle"

    puts "[MP BATTLE] Healing player's Pokemon for fair PVP match"
    $player.party.each do |pkmn|
      pkmn.heal if pkmn
    end

    puts "[MP BATTLE] Healing opponent's Pokemon for fair PVP match"
    opponent_trainer.party.each do |pkmn|
      pkmn.heal if pkmn
    end

    pbMessage(_INTL("All Pokémon have been healed for a fair battle!"))

    player_party = $player.party
    scene = BattleCreationHelperMethods.create_battle_scene
    battle  =  Battle.new(scene, player_party, opponent_trainer.party, $player, [opponent_trainer])

    battle.multiplayer_battle_id = battle_id
    battle.multiplayer_opponent_id = opponent_id
    battle.multiplayer_is_host = is_host
    battle.multiplayer_turn = 0

    # CRITICAL: Force "Set" battle style to prevent switch prompts after opponent KO
    # In multiplayer battles, both players must choose simultaneously - no mid-turn prompts
    battle.instance_variable_set(:@switchStyle, false)
    puts "[MP BATTLE] Forced Set battle style (no switch prompts after KO)"

    # Set RNG seed for deterministic battle behavior
    srand(rng_seed)
    puts "[MP BATTLE] Initial RNG seed set to: #{rng_seed}"

    apply_multiplayer_battle_patch(battle)

    BattleCreationHelperMethods.prepare_battle(battle)

    # Verify battle state synchronization
    puts "[MP BATTLE] Verifying battle state synchronization..."
    if !verify_battle_state_sync(battle_id, opponent_id, rng_seed)
      pbMessage(_INTL("Battle synchronization failed!\\nBattle cancelled."))
      @active_battle = false
      return false
    end
    puts "[MP BATTLE] Battle state verified and synchronized!"

    $game_temp.party_heart_gauges_before_battle = [] if !$game_temp.party_heart_gauges_before_battle

    decision = 0
    battle_result = false
    battle_completed_normally = false
    skip_final_message = false

    begin
      pbBattleAnimation(pbGetTrainerBattleBGM(opponent_trainer)) do        decision = battle.pbStartBattle
      end

      battle_completed_normally = true
      BattleCreationHelperMethods.after_battle(decision, true)

      battle_result = (decision == 1)

    rescue Battle::BattleAbortedException => e

      puts "[MP BATTLE] Battle aborted: #{e.message}"

      decision = 1
      battle_result = true
      skip_final_message = true

      begin
        BattleCreationHelperMethods.after_battle(decision, true)
      rescue => cleanup_error
        puts "[MP BATTLE] Cleanup failed after abort - continuing"
        puts "[MP BATTLE] Cleanup error: #{cleanup_error.message}"
      end

    rescue => e

      puts "[MP BATTLE] Battle error: #{e.class} - #{e.message}"
      puts "[MP BATTLE] Error trace: #{e.backtrace.first(3).join("\n")}" if e.backtrace

      decision = 1
      battle_result = true

      begin
        BattleCreationHelperMethods.after_battle(decision, true)
      rescue => cleanup_error
        puts "[MP BATTLE] Failed to clean up after error - continuing anyway"
        puts "[MP BATTLE] Cleanup error: #{cleanup_error.message}"
      end

      if !battle_completed_normally
        error_type = case e.class.to_s
        when /Connection/, /Socket/, /Network/
          skip_final_message = true
          nil
        when /Timeout/
          skip_final_message = true
          nil
        else
          "System"
        end

        if error_type
          pbMessage(_INTL('{1} error occurred during battle.\\nYou win by default!', error_type))
          skip_final_message = true
        end
      end
    end

    if pbMultiplayerConnected?
      begin
        my_client_id  =  $multiplayer_client.client_id
        if battle_result
          $multiplayer_client.report_battle_complete(my_client_id, opponent_id)
        else
          $multiplayer_client.report_battle_complete(opponent_id, my_client_id)
        end
        puts "[MP BATTLE] Result reported to server successfully"
      rescue => report_error
        puts "[MP BATTLE] Failed to report result to server: #{report_error.message}"
        pbMessage(_INTL("Warning: Could not report battle result to server.\\nYour stats may not have updated."))
      end
    else
      pbMessage(_INTL("Warning: Connection lost!\\nBattle result was not reported to server."))
    end

    if !skip_final_message
      if battle_result
        pbMessage(_INTL('Victory!\\nYou won the battle against {1}!', opponent_name))
      else
        pbMessage(_INTL("Defeat!\\nYou lost the battle against {1}.", opponent_name))
      end
    end

    puts "[MP BATTLE] Healing all Pokemon after PvP battle..."
    if $player && $player.party
      $player.party.each do |pkmn|
        next if !pkmn
        pkmn.heal
      end
      puts "[MP BATTLE] Healed #{$player.party.length} Pokemon"
    end
    pbMessage(_INTL("Your Pokemon were fully healed!"))

    @battle_cooldown_until = Time.now + 5
    puts "[MP BATTLE] Battle cooldown set: 5 seconds"

    @active_battle = false
    return battle_result
  end

  def receive_opponent_battle_choice(choice_data)

    $multiplayer_opponent_choice_received = true
    $multiplayer_opponent_choice_data = choice_data
  end

  def active_mp_battle
    @active_battle
  end

  def verify_battle_state_sync(battle_id, opponent_id, rng_seed)
    return true unless pbMultiplayerConnected?

    begin
      puts "[MP SYNC] Sending battle ready signal with RNG seed: #{rng_seed}"

      # Send ready signal with our RNG seed to opponent
      $multiplayer_client.send_battle_ready(battle_id, opponent_id, rng_seed)

      # Wait for opponent ready signal (with timeout)
      timeout = 300  # 15 seconds
      $multiplayer_opponent_battle_ready = false
      $multiplayer_opponent_rng_seed = nil

      while timeout > 0 && !$multiplayer_opponent_battle_ready
        sleep(0.05)
        timeout -= 1

        # Update network
        begin
          $multiplayer_client.update if pbMultiplayerConnected?
        rescue => e
          puts "[MP SYNC] Network error during ready check: #{e.message}"
          return false
        end

        # Check connection
        if !pbMultiplayerConnected?
          puts "[MP SYNC] Connection lost during ready check"
          return false
        end
      end

      if timeout <= 0
        puts "[MP SYNC] Timeout waiting for opponent ready signal"
        return false
      end

      # Verify RNG seeds match
      if $multiplayer_opponent_rng_seed != rng_seed
        puts "[MP SYNC] RNG seed mismatch! Ours: #{rng_seed}, Theirs: #{$multiplayer_opponent_rng_seed}"
        return false
      end

      puts "[MP SYNC] Battle state verified - both players ready with matching RNG seed"
      return true

    rescue => e
      puts "[MP SYNC] Error during battle state verification: #{e.message}"
      return false
    end
  end

  def receive_opponent_battle_ready(rng_seed)
    puts "[MP SYNC] Received opponent battle ready signal with RNG seed: #{rng_seed}"
    $multiplayer_opponent_battle_ready = true
    $multiplayer_opponent_rng_seed = rng_seed
  end
end
