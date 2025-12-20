class MultiplayerBattleManager
  def start_synchronized_battle(opponent_id, opponent_name, format, opponent_party_data, rng_seed, battle_id, is_host)
    @active_battle = true
    $multiplayer_battle_forfeited = false
    $multiplayer_opponent_choice_received = false
    $multiplayer_opponent_choice_data = nil

    opponent_trainer = NPCTrainer.new(opponent_name, :POKEMONTRAINER_Red)
    opponent_trainer.party = []

    opponent_party_data.each do |pokemon_data|
      pokemon = pbModernTradeManager.deserialize_pokemon(pokemon_data)
      opponent_trainer.party << pokemon
    end

    if opponent_trainer.party.empty?
      pbMessage(_INTL("ERROR: Opponent has no valid Pokemon!"))
      @active_battle = false
      return false
    end

    $player.party.each { |pkmn| pkmn.heal if pkmn }
    opponent_trainer.party.each { |pkmn| pkmn.heal if pkmn }

    setBattleRule("single")
    case format
    when :double then setBattleRule("double")
    when :triple then setBattleRule("triple")
    when :rotation then setBattleRule("rotation")
    end

    setBattleRule("noExp")
    setBattleRule('noMoney')

    player_party = $player.party
    scene = BattleCreationHelperMethods.create_battle_scene
    battle = Battle.new(scene, player_party, opponent_trainer.party, $player, [opponent_trainer])

    battle.multiplayer_battle_id = battle_id
    battle.multiplayer_opponent_id = opponent_id
    battle.multiplayer_is_host = is_host
    battle.multiplayer_turn = 0

    srand(rng_seed)
    apply_multiplayer_battle_patch(battle)
    BattleCreationHelperMethods.prepare_battle(battle)

    battle.battlers.each_with_index do |b, i|
      next unless b
      scene.sprites["dataBox_#{i}"].refresh if scene.sprites["dataBox_#{i}"]
    end

    decision = 0
    begin
      pbBattleAnimation(pbGetTrainerBattleBGM(opponent_trainer)) do
        decision = battle.pbStartBattle
      end
      BattleCreationHelperMethods.after_battle(decision, true)
    rescue Battle::BattleAbortedException
      decision = 1
      BattleCreationHelperMethods.after_battle(decision, true)
    rescue => e
      decision = 1
      BattleCreationHelperMethods.after_battle(decision, true)
    end

    if pbMultiplayerConnected?
      my_id = $multiplayer_client.client_id
      if decision == 1
        $multiplayer_client.report_battle_complete(my_id, opponent_id)
      else
        $multiplayer_client.report_battle_complete(opponent_id, my_id)
      end
    end

    $player.party.each { |pkmn| pkmn.heal if pkmn }
    @active_battle = false
    return decision == 1
  end
end