#===============================================================================
# Fix multiplayer battle desync issues - comprehensive sync patch
#===============================================================================
# This fix addresses critical desyncs in multiplayer battles:
# 1. RNG reseed before attack phase for deterministic crits/status/damage
# 2. Post-turn state validation sent to server
# 3. Pokemon switching synchronization
# 4. Forfeit and Draw/Tie system (Run button -> Forfeit or Request Draw)
# 5. Proper choice type handling (UseMove, SwitchOut, items blocked)

puts "[MP Battle Sync Fix] Loading improved battle synchronization..."

def ensure_multiplayer_battle_patch!
  return if $multiplayer_battle_patch_applied

  puts "[MP BATTLE SYNC] Installing improved multiplayer battle patch..."

  begin
    Battle.class_eval do

      #=====================================================================
      # pbCommandPhaseLoop - Turn choice synchronization
      #=====================================================================
      unless method_defined?(:multiplayer_original_pbCommandPhaseLoop)
        alias multiplayer_original_pbCommandPhaseLoop pbCommandPhaseLoop
      end

      def pbCommandPhaseLoop(isPlayer)
        if !@multiplayer_battle_id
          return multiplayer_original_pbCommandPhaseLoop(isPlayer)
        end

        puts "[MP SYNC] pbCommandPhaseLoop - isPlayer: #{isPlayer}, turn: #{@multiplayer_turn}, battle: ##{@multiplayer_battle_id}"

        # Seed RNG for command phase (will be reseeded before attack phase)
        turn_seed = @multiplayer_battle_id.to_i + (@multiplayer_turn || 0) * 1000
        srand(turn_seed)
        puts "[MP SYNC] Command phase RNG seed: #{turn_seed}"

        if isPlayer
          mp_command_phase_player
        else
          mp_command_phase_opponent
        end
      end

      #=====================================================================
      # Player's command phase: collect choices, handle run/draw, sync
      #=====================================================================
      def mp_command_phase_player
        # Check for incoming draw request before showing command menu
        mp_check_incoming_draw_request
        return if @decision > 0

        # Let player choose actions normally
        multiplayer_original_pbCommandPhaseLoop(true)
        return if @decision > 0
        return unless pbMultiplayerConnected?

        # Validate and serialize all player choices
        choices_data = []
        @battlers.each_with_index do |battler, i|
          next if !battler || !battler.pbOwnedByPlayer?
          choice = @choices[i]
          next unless choice && choice[0]

          # BLOCK ITEMS in multiplayer battles
          if choice[0] == :UseItem
            puts "[MP SYNC] ERROR: Items not allowed in multiplayer!"
            @scene.pbDisplayMessage(_INTL("Items cannot be used in multiplayer battles!")) if @scene
            @choices[i] = [:None, 0, nil, -1]
            multiplayer_original_pbCommandPhaseLoop(true)
            return
          end

          # HANDLE RUN -> Forfeit/Draw menu
          if choice[0] == :Run
            mp_handle_run_menu
            return
          end

          choice_index = choice[1].is_a?(Integer) ? choice[1] : choice[1].to_s
          choices_data << {
            battler_index: i,
            type: choice[0].to_s,
            index: choice_index,
            target_index: choice[3] ? choice[3].to_i : -1
          }
          puts "[MP SYNC] Player battler #{i}: #{choice[0]} index=#{choice_index} target=#{choice[3]}"
        end

        # Send choices to opponent via server
        $multiplayer_client.send_battle_choice(
          @multiplayer_battle_id,
          @multiplayer_opponent_id,
          @multiplayer_turn || 0,
          choices_data
        )
        puts "[MP SYNC] Sent #{choices_data.length} choices, waiting for opponent..."

        # Wait for opponent's choices
        mp_wait_for_opponent_choice
        return if @decision > 0

        @multiplayer_turn = (@multiplayer_turn || 0) + 1
      end

      #=====================================================================
      # Opponent's command phase: apply received choices
      #=====================================================================
      def mp_command_phase_opponent
        return if @decision > 0

        if $multiplayer_opponent_choice_data && $multiplayer_opponent_choice_data.is_a?(Array)
          puts "[MP SYNC] Processing #{$multiplayer_opponent_choice_data.length} opponent choices"

          # Build list of opponent battler indices
          opponent_battler_indices = []
          @battlers.each_with_index do |b, i|
            next if !b || b.pbOwnedByPlayer?
            opponent_battler_indices << i
          end
          puts "[MP SYNC] Opponent battlers at indices: #{opponent_battler_indices.inspect}"

          $multiplayer_opponent_choice_data.each_with_index do |choice_data, choice_idx|
            type_str = choice_data[:type] || choice_data['type'] || 'None'
            type_sym = type_str.to_sym
            index = (choice_data[:index] || choice_data['index'] || 0).to_i
            target_index = choice_data[:target_index] || choice_data['target_index']
            target_index = target_index.to_i if target_index

            # Map choice to correct opponent battler
            battler_idx = opponent_battler_indices[choice_idx]
            next unless battler_idx
            battler = @battlers[battler_idx]

            case type_sym
            when :UseMove
              move_object = battler.moves[index]
              # Swap target perspective (opponent's 0 -> our 1, and vice versa)
              adjusted_target = target_index && target_index >= 0 ? ((target_index == 0) ? 1 : 0) : -1
              @choices[battler_idx] = [type_sym, index, move_object, adjusted_target]
              puts "[MP SYNC] Battler #{battler_idx}: UseMove #{move_object ? move_object.name : 'nil'} -> target #{adjusted_target}"
            when :SwitchOut, :Shift
              @choices[battler_idx] = [type_sym, index, nil, -1]
              puts "[MP SYNC] Battler #{battler_idx}: Switch to party slot #{index}"
            when :UseItem
              @choices[battler_idx] = [type_sym, index, nil, target_index]
              puts "[MP SYNC] Battler #{battler_idx}: UseItem #{index}"
            when :Run
              @choices[battler_idx] = [type_sym, 0, nil, -1]
              puts "[MP SYNC] Battler #{battler_idx}: Run"
            when :Call
              @choices[battler_idx] = [type_sym, 0, nil, -1]
              puts "[MP SYNC] Battler #{battler_idx}: Call"
            else
              @choices[battler_idx] = [:None, 0, nil, -1]
              puts "[MP SYNC] WARNING: Unknown choice type '#{type_sym}' for battler #{battler_idx}"
            end
          end

          $multiplayer_opponent_choice_data = nil
          puts "[MP SYNC] Opponent choices applied successfully"
        else
          puts "[MP SYNC] ERROR: No valid opponent choice data!"
          @scene.pbDisplayMessage(_INTL("ERROR: Failed to receive opponent's action!")) if @scene
          @scene.pbDisplayMessage(_INTL("You win by default!")) if @scene
          @decision = 1
          pbAbort
        end
      end

      #=====================================================================
      # pbAttackPhase - CRITICAL: Reseed RNG for deterministic execution
      #=====================================================================
      # The command phase consumes rand() differently on each client
      # (player side has UI interactions, opponent side doesn't).
      # Reseeding here ensures both clients produce IDENTICAL:
      # - Critical hit rolls
      # - Damage variance (random factor in damage formula)
      # - Status effect application chances
      # - Accuracy/evasion checks
      # - Secondary effect chances (e.g. 30% burn from Flamethrower)
      # - Confusion self-hit checks
      # - Paralysis full-para checks
      #=====================================================================
      unless method_defined?(:multiplayer_original_pbAttackPhase)
        alias multiplayer_original_pbAttackPhase pbAttackPhase
      end

      def pbAttackPhase
        if @multiplayer_battle_id
          attack_seed = @multiplayer_battle_id.to_i + (@multiplayer_turn || 1) * 1000 + 500
          srand(attack_seed)
          puts "[MP SYNC] Attack phase RNG reseed: #{attack_seed} (turn #{@multiplayer_turn})"
        end
        multiplayer_original_pbAttackPhase
      end

      #=====================================================================
      # pbEndOfRoundPhase - Post-turn state validation
      #=====================================================================
      # After each turn completes (attack + end-of-round effects), send
      # a state snapshot to the server. The server compares both players'
      # states and detects desync (different HP, status, etc.).
      #=====================================================================
      unless method_defined?(:multiplayer_original_pbEndOfRoundPhase)
        alias multiplayer_original_pbEndOfRoundPhase pbEndOfRoundPhase
      end

      def pbEndOfRoundPhase
        result = multiplayer_original_pbEndOfRoundPhase

        if @multiplayer_battle_id && pbMultiplayerConnected? && @decision == 0
          mp_send_battle_state
        end

        result
      end

      # Send current battle state to server for cross-client validation
      def mp_send_battle_state
        battler_states = []
        @battlers.each_with_index do |b, i|
          next unless b
          battler_states << {
            index: i,
            hp: b.hp,
            status: b.status.to_s,
            statusCount: b.statusCount,
            totalhp: b.totalhp
          }
        end

        state = {
          turn: @multiplayer_turn || 0,
          battlers: battler_states
        }

        begin
          $multiplayer_client.send_battle_state(
            @multiplayer_battle_id,
            @multiplayer_opponent_id,
            state
          )
          puts "[MP SYNC] Sent state validation: turn #{@multiplayer_turn}, #{battler_states.length} battlers"
        rescue => e
          puts "[MP SYNC] Failed to send battle state: #{e.message}"
        end
      end

      #=====================================================================
      # Run Menu: Forfeit / Request Draw / Cancel
      #=====================================================================
      def mp_handle_run_menu
        # Clear the Run choice
        @battlers.each_with_index do |b, i|
          next if !b || !b.pbOwnedByPlayer?
          @choices[i] = [:None, 0, nil, -1]
        end

        commands = [_INTL("Forfeit"), _INTL("Request Draw"), _INTL("Cancel")]
        choice_idx = pbMessage(_INTL("What would you like to do?"), commands, -1)

        case choice_idx
        when 0 then mp_handle_forfeit
        when 1 then mp_handle_draw_request
        else
          # Cancel - restart command phase
          multiplayer_original_pbCommandPhaseLoop(true)
        end
      end

      def mp_handle_forfeit
        if pbMessage(_INTL("Forfeit this battle?\nThis counts as a loss."),
                     [_INTL("Yes"), _INTL("No")], 2) == 0
          @scene.pbDisplayMessage(_INTL("You forfeited the battle!")) if @scene
          if pbMultiplayerConnected?
            $multiplayer_client.send_battle_forfeit(
              @multiplayer_battle_id, @multiplayer_opponent_id
            )
          end
          @decision = 2  # Loss
          pbAbort
        else
          # Cancel - restart command phase
          multiplayer_original_pbCommandPhaseLoop(true)
        end
      end

      def mp_handle_draw_request
        @scene.pbDisplayMessage(_INTL("Requesting a draw...")) if @scene

        if pbMultiplayerConnected?
          $multiplayer_client.send_battle_draw_request(
            @multiplayer_battle_id, @multiplayer_opponent_id
          )
          $multiplayer_battle_draw_requested = true
          $multiplayer_battle_draw_response_received = false
        end

        # Wait for opponent's response
        timeout = 600  # 30 seconds
        last_sec = -1
        mp_create_timer_sprite

        while timeout > 0
          sec = (timeout / 20.0).ceil
          if sec != last_sec
            mp_update_timer_display("Waiting for response", sec)
            last_sec = sec
          end

          Graphics.update
          Input.update
          @scene.pbUpdate if @scene && @scene.respond_to?(:pbUpdate)

          # Draw confirmed by server
          if $multiplayer_battle_draw_confirmed
            cleanup_timer_sprite
            mp_finalize_draw
            return
          end

          # Response received
          if $multiplayer_battle_draw_response_received
            cleanup_timer_sprite
            $multiplayer_battle_draw_response_received = false
            $multiplayer_battle_draw_requested = false

            if $multiplayer_battle_draw_response_accepted
              # Accepted - wait for server confirmation
              mp_wait_for_draw_confirmation
              return
            else
              # Declined
              @scene.pbDisplayMessage(_INTL("Your opponent declined the draw request.")) if @scene
              multiplayer_original_pbCommandPhaseLoop(true)
              return
            end
          end

          # Check forfeit / disconnect
          if $multiplayer_battle_forfeited
            cleanup_timer_sprite
            mp_handle_opponent_forfeit
            return
          end

          if !pbMultiplayerConnected?
            cleanup_timer_sprite
            mp_handle_connection_lost
            return
          end

          begin
            pbMultiplayerClient.update if pbMultiplayerConnected?
          rescue => e
            puts "[MP SYNC] Network error during draw wait: #{e.message}"
            cleanup_timer_sprite
            mp_handle_network_error
            return
          end

          sleep(0.05)
          timeout -= 1
        end

        # Timeout
        cleanup_timer_sprite
        $multiplayer_battle_draw_requested = false
        @scene.pbDisplayMessage(_INTL("Draw request timed out.")) if @scene
        multiplayer_original_pbCommandPhaseLoop(true)
      end

      def mp_wait_for_draw_confirmation
        timeout = 300  # 15 seconds
        while timeout > 0
          Graphics.update
          Input.update
          begin
            pbMultiplayerClient.update if pbMultiplayerConnected?
          rescue
          end

          if $multiplayer_battle_draw_confirmed
            mp_finalize_draw
            return
          end

          sleep(0.05)
          timeout -= 1
        end

        # If no explicit confirmation arrived, the accept itself is enough
        mp_finalize_draw
      end

      def mp_finalize_draw
        cleanup_timer_sprite
        $multiplayer_battle_draw_confirmed = false
        $multiplayer_battle_draw_requested = false
        $multiplayer_battle_draw_request_received = false
        $multiplayer_battle_ended_as_draw = true

        @scene.pbDisplayMessage(_INTL("The battle ended in a draw!")) if @scene
        @scene.pbDisplayMessage(_INTL("No ELO will be gained or lost.")) if @scene

        @decision = 1  # End the battle (post-battle checks draw flag)
        pbAbort
      end

      #=====================================================================
      # Check for incoming draw request from opponent
      #=====================================================================
      def mp_check_incoming_draw_request
        return unless $multiplayer_battle_draw_request_received
        $multiplayer_battle_draw_request_received = false

        if @scene
          accepted = (pbMessage(
            _INTL("Your opponent is requesting a draw.\nNo ELO will be gained or lost.\nAccept the draw?"),
            [_INTL("Accept"), _INTL("Decline")], 2
          ) == 0)

          if pbMultiplayerConnected?
            $multiplayer_client.send_battle_draw_response(
              @multiplayer_battle_id,
              @multiplayer_opponent_id,
              accepted
            )
          end

          if accepted
            mp_wait_for_draw_confirmation
          end
        end
      end

      #=====================================================================
      # Wait for opponent's battle choice (main wait loop)
      #=====================================================================
      def mp_wait_for_opponent_choice
        timeout = 1200  # 60 seconds
        last_sec = -1
        mp_create_timer_sprite

        while timeout > 0
          sec = (timeout / 20.0).ceil
          if sec != last_sec
            mp_update_timer_display("Waiting for opponent", sec)
            last_sec = sec
          end

          Graphics.update
          Input.update
          @scene.pbUpdate if @scene && @scene.respond_to?(:pbUpdate)

          # Draw confirmed
          if $multiplayer_battle_draw_confirmed
            cleanup_timer_sprite
            mp_finalize_draw
            return
          end

          # Incoming draw request (opponent asking us)
          if $multiplayer_battle_draw_request_received
            cleanup_timer_sprite
            mp_check_incoming_draw_request
            return if @decision > 0
            # If declined, recreate timer and continue waiting
            mp_create_timer_sprite
          end

          # Opponent forfeit
          if $multiplayer_battle_forfeited
            cleanup_timer_sprite
            mp_handle_opponent_forfeit
            return
          end

          # Connection lost
          if !pbMultiplayerConnected?
            cleanup_timer_sprite
            mp_handle_connection_lost
            return
          end

          # Network update
          begin
            pbMultiplayerClient.update if pbMultiplayerConnected?
          rescue => e
            puts "[MP SYNC] Network error: #{e.message}"
            cleanup_timer_sprite
            mp_handle_network_error
            return
          end

          # Opponent choice received
          if $multiplayer_opponent_choice_received
            cleanup_timer_sprite
            $multiplayer_opponent_choice_received = false
            return
          end

          sleep(0.05)
          timeout -= 1
        end

        # Timeout
        cleanup_timer_sprite
        @scene.pbDisplayMessage(_INTL("Your opponent took too long!")) if @scene
        @scene.pbDisplayMessage(_INTL("You win by timeout!")) if @scene
        @decision = 1
        pbAbort
      end

      #=====================================================================
      # Common result handlers
      #=====================================================================
      def mp_handle_opponent_forfeit
        $multiplayer_battle_forfeited = false
        @scene.pbDisplayMessage(_INTL("Your opponent forfeited!")) if @scene
        @scene.pbDisplayMessage(_INTL("You win!")) if @scene
        @decision = 1
        pbAbort
      end

      def mp_handle_connection_lost
        @scene.pbDisplayMessage(_INTL("Connection lost!")) if @scene
        @scene.pbDisplayMessage(_INTL("Your opponent disconnected. You win!")) if @scene
        @decision = 1
        pbAbort
      end

      def mp_handle_network_error
        @scene.pbDisplayMessage(_INTL("Network error occurred!")) if @scene
        @scene.pbDisplayMessage(_INTL("Your opponent disconnected. You win!")) if @scene
        @decision = 1
        pbAbort
      end

      #=====================================================================
      # Timer sprite helpers
      #=====================================================================
      def mp_create_timer_sprite
        cleanup_timer_sprite  # Clean up any existing
        @multiplayer_timer_sprite = Sprite.new
        @multiplayer_timer_sprite.z = 99999
        @multiplayer_timer_sprite.bitmap = Bitmap.new(200, 60)
        @multiplayer_timer_sprite.x = (Graphics.width - 200) / 2
        @multiplayer_timer_sprite.y = 10
      end

      def mp_update_timer_display(label, seconds)
        return unless @multiplayer_timer_sprite &&
                      @multiplayer_timer_sprite.bitmap &&
                      !@multiplayer_timer_sprite.bitmap.disposed?

        bmp = @multiplayer_timer_sprite.bitmap
        bmp.clear
        bmp.fill_rect(0, 0, 200, 60, Color.new(0, 0, 0, 200))
        bmp.fill_rect(2, 2, 196, 56, Color.new(40, 40, 60, 255))

        text_color = if seconds > 30
                       Color.new(100, 255, 100)
                     elsif seconds > 15
                       Color.new(255, 255, 100)
                     else
                       Color.new(255, 100, 100)
                     end

        pbSetSystemFont(bmp)
        bmp.font.size = 18
        bmp.font.color = Color.new(200, 200, 200)
        bmp.draw_text(0, 5, 200, 24, label, 1)
        bmp.font.size = 24
        bmp.font.color = text_color
        bmp.draw_text(0, 28, 200, 28, "#{seconds}s", 1)
      end

      def cleanup_timer_sprite
        if @multiplayer_timer_sprite
          if @multiplayer_timer_sprite.bitmap && !@multiplayer_timer_sprite.bitmap.disposed?
            @multiplayer_timer_sprite.bitmap.dispose
          end
          @multiplayer_timer_sprite.dispose if !@multiplayer_timer_sprite.disposed?
          @multiplayer_timer_sprite = nil
        end
      end

      #=====================================================================
      # pbSwitchInBetween - Synchronize Pokemon replacements when one faints
      #=====================================================================
      unless method_defined?(:multiplayer_original_pbSwitchInBetween)
        alias multiplayer_original_pbSwitchInBetween pbSwitchInBetween
      end

      def pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
        if !@multiplayer_battle_id
          return multiplayer_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
        end

        battler = @battlers[idxBattler]
        return -1 if !battler

        puts "[MP SYNC] pbSwitchInBetween for battler #{idxBattler} (player: #{battler.pbOwnedByPlayer?})"

        if battler.pbOwnedByPlayer?
          mp_switch_player(idxBattler, checkLaxOnly, canCancel)
        else
          mp_switch_opponent(idxBattler)
        end
      end

      # Player selects replacement, send to opponent
      def mp_switch_player(idxBattler, checkLaxOnly, canCancel)
        idxParty = multiplayer_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)

        if idxParty >= 0 && pbMultiplayerConnected?
          puts "[MP SYNC] Player selected party slot #{idxParty}, sending to opponent"
          $multiplayer_client.send_battle_switch(
            @multiplayer_battle_id,
            @multiplayer_opponent_id,
            idxBattler,
            idxParty
          )
        end

        idxParty
      end

      # Wait for opponent's replacement choice
      def mp_switch_opponent(idxBattler)
        @scene.pbDisplay(_INTL("Waiting for opponent to choose their next Pokémon...")) if @scene

        $multiplayer_opponent_switch_received = false
        $multiplayer_opponent_switch_data = nil

        timeout = 1200  # 60 seconds
        last_sec = -1
        mp_create_timer_sprite

        while timeout > 0
          sec = (timeout / 20.0).ceil
          if sec != last_sec
            mp_update_timer_display("Opponent choosing", sec)
            last_sec = sec
          end

          Graphics.update
          Input.update

          # Draw confirmed during switch
          if $multiplayer_battle_draw_confirmed
            cleanup_timer_sprite
            mp_finalize_draw
            return -1
          end

          # Opponent forfeit during switch
          if $multiplayer_battle_forfeited
            cleanup_timer_sprite
            $multiplayer_battle_forfeited = false
            @decision = 1
            pbAbort
            return -1
          end

          # Connection lost during switch
          if !pbMultiplayerConnected?
            cleanup_timer_sprite
            @decision = 1
            pbAbort
            return -1
          end

          # Network update
          begin
            pbMultiplayerClient.update if pbMultiplayerConnected?
          rescue => e
            puts "[MP SYNC] Network error during switch: #{e.message}"
            cleanup_timer_sprite
            @decision = 1
            pbAbort
            return -1
          end

          # Switch received
          if $multiplayer_opponent_switch_received
            cleanup_timer_sprite
            $multiplayer_opponent_switch_received = false
            switch_data = $multiplayer_opponent_switch_data
            idxParty = switch_data[:party_index] || switch_data['party_index'] || 0
            puts "[MP SYNC] Opponent selected party slot #{idxParty}"
            return idxParty
          end

          sleep(0.05)
          timeout -= 1
        end

        # Timeout
        cleanup_timer_sprite
        @scene.pbDisplayMessage(_INTL("Opponent took too long to choose!")) if @scene
        @scene.pbDisplayMessage(_INTL("You win by timeout!")) if @scene
        @decision = 1
        pbAbort
        return -1
      end

      #=====================================================================
      # Block items in multiplayer battles
      #=====================================================================
      unless method_defined?(:multiplayer_original_pbItemMenu)
        alias multiplayer_original_pbItemMenu pbItemMenu
      end

      def pbItemMenu(idxBattler, firstAction)
        if @multiplayer_battle_id
          pbDisplay(_INTL("Items cannot be used in multiplayer battles!"))
          return false
        end
        multiplayer_original_pbItemMenu(idxBattler, firstAction)
      end

      unless method_defined?(:multiplayer_original_pbRegisterItem)
        alias multiplayer_original_pbRegisterItem pbRegisterItem
      end

      def pbRegisterItem(idxBattler, item, idxTarget = -1, idxMove = -1)
        if @multiplayer_battle_id
          puts "[MP BATTLE] ERROR: Attempted to use item #{item} - disabled in multiplayer!"
          return false
        end
        multiplayer_original_pbRegisterItem(idxBattler, item, idxTarget, idxMove)
      end

    end

    $multiplayer_battle_patch_applied = true
    puts "[MP BATTLE SYNC] Battle sync patch installed successfully!"

  rescue => e
    puts "[MP BATTLE SYNC] ERROR installing patch: #{e.message}"
    puts "[MP BATTLE SYNC] Trace: #{e.backtrace.first(5).join("\n")}" if e.backtrace
  end
end

# Apply the battle patch to a specific battle instance
def apply_multiplayer_battle_patch(battle)
  ensure_multiplayer_battle_patch!
  puts "[MP BATTLE SYNC] Battle ##{battle.multiplayer_battle_id} ready with sync"
end

puts "[MP Battle Sync Fix] Improved battle synchronization loaded"
