class Battle
  attr_accessor :multiplayer_battle_id
  attr_accessor :multiplayer_opponent_id
  attr_accessor :multiplayer_is_host
  attr_accessor :multiplayer_turn
end

$multiplayer_opponent_choice_received = false
$multiplayer_opponent_choice_data = nil
$multiplayer_battle_patch_applied = false
$multiplayer_battle_forfeited = false

def ensure_multiplayer_battle_patch!
  return if $multiplayer_battle_patch_applied

  Battle.class_eval do
    if method_defined?(:multiplayer_original_pbCommandPhaseLoop)
      remove_method :pbCommandPhaseLoop
      alias pbCommandPhaseLoop multiplayer_original_pbCommandPhaseLoop
    end

    alias multiplayer_original_pbCommandPhaseLoop pbCommandPhaseLoop

    def pbCommandPhaseLoop(isPlayer)
      if !@multiplayer_battle_id
        return multiplayer_original_pbCommandPhaseLoop(isPlayer)
      end

      sync_seed = @multiplayer_battle_id.to_i + (@multiplayer_turn || 0) * 1000
      srand(sync_seed)

      if isPlayer
        multiplayer_original_pbCommandPhaseLoop(isPlayer)

        if @decision > 0
          return
        end

        if pbMultiplayerConnected?
          choices_data = []
          @battlers.each_with_index do |battler, i|
            next if !battler || !battler.pbOwnedByPlayer?
            
            choice = @choices[i]
            if choice && choice[0]
              choices_data << {
                battler_index: i,
                type: choice[0].to_s,
                index: choice[1].to_i,
                target_index: choice[3].to_i,
                hp_at_start: battler.hp,
                status_at_start: battler.status
              }
            end
          end

          $multiplayer_client.send_battle_choice(
            @multiplayer_battle_id,
            @multiplayer_opponent_id,
            @multiplayer_turn || 0,
            choices_data
          )

          timeout = 1800 
          while timeout > 0
            Graphics.update
            Input.update
            @scene.pbUpdate if @scene
            
            begin
              pbMultiplayerClient.update if pbMultiplayerConnected?
            rescue
              @decision = 1
              pbAbort
              return
            end

            if $multiplayer_battle_forfeited || !pbMultiplayerConnected?
              @decision = 1
              @scene.pbDisplayMessage("Connection lost or opponent forfeited.")
              pbAbort
              return
            end

            break if $multiplayer_opponent_choice_received
            sleep(0.01)
            timeout -= 1
          end

          if timeout <= 0
            @decision = 1
            @scene.pbDisplayMessage("Opponent timed out.")
            pbAbort
            return
          end

          $multiplayer_opponent_choice_received = false
          @multiplayer_turn = (@multiplayer_turn || 0) + 1
        end

      else
        if $multiplayer_opponent_choice_data && $multiplayer_opponent_choice_data.is_a?(Array)
          
          $multiplayer_opponent_choice_data.each do |data|
            type_sym = data[:type].to_sym
            idx = data[:index]
            target = data[:target_index]
            
            battler_idx = nil
            @battlers.each_with_index do |b, i|
              next if !b || b.pbOwnedByPlayer?
              battler_idx = i
              break
            end

            if battler_idx
              battler = @battlers[battler_idx]
              
              adjusted_target = target >= 0 ? ((target == 0) ? 1 : 0) : -1
              move_obj = (type_sym == :UseMove) ? battler.moves[idx] : nil
              
              @choices[battler_idx] = [type_sym, idx, move_obj, adjusted_target]

              if data[:hp_at_start] && battler.hp != data[:hp_at_start]
                battler.hp = data[:hp_at_start]
                @scene.sprites["dataBox_#{battler_idx}"].refresh if @scene.sprites["dataBox_#{battler_idx}"]
              end

              if data[:status_at_start] && battler.status != data[:status_at_start]
                battler.status = data[:status_at_start].to_sym
                @scene.sprites["dataBox_#{battler_idx}"].refresh if @scene.sprites["dataBox_#{battler_idx}"]
              end
            end
          end
          $multiplayer_opponent_choice_data = nil
        else
          @decision = 1
          pbAbort
          return
        end
      end
    end
  end
  $multiplayer_battle_patch_applied = true
end

def apply_multiplayer_battle_patch(battle)
  ensure_multiplayer_battle_patch!
end