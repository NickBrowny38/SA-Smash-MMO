#===============================================================================
# Fix multiplayer battle desync issues - especially Pokemon switching
#===============================================================================

# This fix addresses critical desyncs in multiplayer battles, particularly:
# 1. Switching Pokemon after defeating opponent's Pokemon
# 2. Voluntary Pokemon swaps during battle
# 3. Multiple battler choice synchronization
# 4. Proper handling of different choice types (UseMove, SwitchOut, UseItem, etc.)

puts "[MP Battle Sync Fix] Loading improved battle synchronization..."

def ensure_multiplayer_battle_patch!
  return if $multiplayer_battle_patch_applied

  puts "[MP BATTLE SYNC] Installing improved multiplayer battle patch..."

  begin
    Battle.class_eval do
      # Only alias if not already aliased
      unless method_defined?(:multiplayer_original_pbCommandPhaseLoop)
        alias multiplayer_original_pbCommandPhaseLoop pbCommandPhaseLoop
      end

      def pbCommandPhaseLoop(isPlayer)
        # Non-multiplayer battles use original code
        if !@multiplayer_battle_id
          return multiplayer_original_pbCommandPhaseLoop(isPlayer)
        end

        puts "[MP SYNC] pbCommandPhaseLoop - isPlayer: #{isPlayer}, turn: #{@multiplayer_turn}, battle: ##{@multiplayer_battle_id}"

        # CRITICAL: Reseed RNG for BOTH players to ensure sync
        turn_seed = @multiplayer_battle_id.to_i + (@multiplayer_turn || 0) * 1000
        srand(turn_seed)
        puts "[MP SYNC] RNG seed: #{turn_seed} (before #{isPlayer ? 'player' : 'opponent'} choices)"

        if isPlayer
          # PLAYER'S TURN: Choose actions and send to opponent
          puts "[MP SYNC] Player choosing actions..."

          # Let player choose their actions normally
          multiplayer_original_pbCommandPhaseLoop(isPlayer)

          # Check if battle ended
          if @decision > 0
            puts "[MP SYNC] Battle ended during player turn (decision: #{@decision})"
            return
          end

          # Send choices to opponent
          if pbMultiplayerConnected?
            puts "[MP SYNC] Sending player choices to opponent..."

            # Serialize ALL choices for ALL player battlers
            choices_data = []
            @battlers.each_with_index do |battler, i|
              next if !battler || !battler.pbOwnedByPlayer?

              choice = @choices[i]
              if choice && choice[0]
                # BLOCK ITEMS IN MULTIPLAYER BATTLES
                if choice[0] == :UseItem
                  puts "[MP SYNC] ERROR: Items are not allowed in multiplayer battles!"
                  @scene.pbDisplayMessage("Items cannot be used in multiplayer battles!") if @scene
                  # Force the player to make a different choice
                  pbAbort
                  return
                end

                # HANDLE RUN AS FORFEIT IN MULTIPLAYER BATTLES
                if choice[0] == :Run
                  puts "[MP SYNC] Player attempting to forfeit the battle!"

                  # Ask for confirmation
                  if @scene && @scene.pbDisplayConfirm("Do you want to forfeit this battle?\nYou will lose if you forfeit.")
                    puts "[MP SYNC] Player confirmed forfeit!"
                    @scene.pbDisplayMessage("You forfeited the battle!")

                    # Send forfeit notification to opponent
                    if pbMultiplayerConnected?
                      $multiplayer_client.send_battle_forfeit(@multiplayer_battle_id, @multiplayer_opponent_id)
                    end

                    # End battle as loss
                    @decision = 2  # 2 = loss
                    pbAbort
                    return
                  else
                    puts "[MP SYNC] Forfeit cancelled - player must choose another action"
                    # Return to command menu without sending choices
                    return
                  end
                end

                # Serialize choice data
                choice_index = choice[1].is_a?(Integer) ? choice[1] : choice[1].to_s
                choice_hash = {
                  battler_index: i,
                  type: choice[0].to_s,
                  index: choice_index,  # Move index OR Pokemon party index for switches
                  target_index: choice[3] ? choice[3].to_i : -1
                }

                puts "[MP SYNC] Player battler #{i}: #{choice_hash.inspect}"
                choices_data << choice_hash
              end
            end

            $multiplayer_client.send_battle_choice(
              @multiplayer_battle_id,
              @multiplayer_opponent_id,
              @multiplayer_turn || 0,
              choices_data
            )

            puts "[MP SYNC] Sent #{choices_data.length} choices, waiting for opponent..."

            # Wait for opponent's choices with timeout
            timeout = 1200  # 60 seconds
            last_displayed_seconds = -1

            # Create timer sprite if needed
            if !@multiplayer_timer_sprite
              @multiplayer_timer_sprite = Sprite.new
              @multiplayer_timer_sprite.z = 99999
              @multiplayer_timer_sprite.bitmap = Bitmap.new(200, 60)
              @multiplayer_timer_sprite.x = (Graphics.width - 200) / 2
              @multiplayer_timer_sprite.y = 10
            end

            while timeout > 0
              remaining_seconds = (timeout / 20.0).ceil

              # Update timer display
              if remaining_seconds != last_displayed_seconds
                @multiplayer_timer_sprite.bitmap.clear
                @multiplayer_timer_sprite.bitmap.fill_rect(0, 0, 200, 60, Color.new(0, 0, 0, 200))
                @multiplayer_timer_sprite.bitmap.fill_rect(2, 2, 196, 56, Color.new(40, 40, 60, 255))

                text_color = if remaining_seconds > 30
                  Color.new(100, 255, 100)
                elsif remaining_seconds > 15
                  Color.new(255, 255, 100)
                else
                  Color.new(255, 100, 100)
                end

                pbSetSystemFont(@multiplayer_timer_sprite.bitmap)
                @multiplayer_timer_sprite.bitmap.font.size = 18
                @multiplayer_timer_sprite.bitmap.font.color = Color.new(200, 200, 200)
                @multiplayer_timer_sprite.bitmap.draw_text(0, 5, 200, 24, "Waiting for opponent", 1)

                @multiplayer_timer_sprite.bitmap.font.size = 24
                @multiplayer_timer_sprite.bitmap.font.color = text_color
                @multiplayer_timer_sprite.bitmap.draw_text(0, 28, 200, 28, "#{remaining_seconds}s", 1)

                last_displayed_seconds = remaining_seconds
              end

              Graphics.update
              Input.update
              @scene.pbUpdate if @scene && @scene.respond_to?(:pbUpdate)

              # Check for opponent forfeit
              if $multiplayer_battle_forfeited
                puts "[MP SYNC] Opponent forfeited!"
                cleanup_timer_sprite
                @scene.pbDisplayMessage("Your opponent forfeited!")
                @scene.pbDisplayMessage("You win!")
                @decision = 1
                $multiplayer_battle_forfeited = false
                pbAbort
                return
              end

              # Check for connection loss
              if !pbMultiplayerConnected?
                puts "[MP SYNC] Connection lost!"
                cleanup_timer_sprite
                @scene.pbDisplayMessage("Connection lost!")
                @scene.pbDisplayMessage("Your opponent disconnected. You win!")
                @decision = 1
                pbAbort
                return
              end

              # Update network
              begin
                pbMultiplayerClient.update if pbMultiplayerConnected?
              rescue => e
                puts "[MP SYNC] Network error: #{e.message}"
                cleanup_timer_sprite
                @scene.pbDisplayMessage('Network error occurred!')
                @scene.pbDisplayMessage("Your opponent disconnected. You win!")
                @decision = 1
                pbAbort
                return
              end

              # Check if opponent's choice received
              if $multiplayer_opponent_choice_received
                puts "[MP SYNC] Opponent choices received!"
                cleanup_timer_sprite
                $multiplayer_opponent_choice_received = false
                break
              end

              sleep(0.05)
              timeout -= 1
            end

            # Handle timeout
            if timeout <= 0
              puts "[MP SYNC] Opponent timeout!"
              cleanup_timer_sprite
              @scene.pbDisplayMessage("Your opponent took too long!")
              @scene.pbDisplayMessage("You win by timeout!")
              @decision = 1
              pbAbort
              return
            end

            @multiplayer_turn = (@multiplayer_turn || 0) + 1
          end

        else
          # OPPONENT'S TURN: Apply received choices
          puts "[MP SYNC] Applying opponent choices..."

          # Check if battle already ended
          if @decision > 0
            puts "[MP SYNC] Battle already ended (decision: #{@decision})"
            return
          end

          # Apply opponent's choices
          if $multiplayer_opponent_choice_data && $multiplayer_opponent_choice_data.is_a?(Array)
            puts "[MP SYNC] Processing #{$multiplayer_opponent_choice_data.length} opponent choices"

            # Build list of opponent battler indices
            opponent_battler_indices = []
            @battlers.each_with_index do |b, i|
              next if !b || b.pbOwnedByPlayer?
              opponent_battler_indices << i
            end

            puts "[MP SYNC] Found opponent battlers at indices: #{opponent_battler_indices.inspect}"

            $multiplayer_opponent_choice_data.each_with_index do |choice_data, choice_idx|
              # Get choice details
              type_str = choice_data[:type] || choice_data['type'] || 'None'
              type_sym = type_str.to_sym
              index = (choice_data[:index] || choice_data['index'] || 0).to_i
              target_index = choice_data[:target_index] || choice_data['target_index']
              target_index = target_index.to_i if target_index

              # Map choice to correct opponent battler (support multi-battles)
              battler_idx = opponent_battler_indices[choice_idx]
              next unless battler_idx
              battler = @battlers[battler_idx]

              # Handle different choice types
              case type_sym
              when :UseMove
                # Using a move
                move_object = battler.moves[index]
                # Swap target perspective (opponent's target 0 = our battler 1, and vice versa)
                adjusted_target = target_index && target_index >= 0 ? ((target_index == 0) ? 1 : 0) : -1
                @choices[battler_idx] = [type_sym, index, move_object, adjusted_target]
                puts "[MP SYNC] Battler #{battler_idx}: UseMove #{move_object ? move_object.name : 'nil'} -> target #{adjusted_target}"

              when :SwitchOut, :Shift
                # Switching Pokemon - index is the party position
                @choices[battler_idx] = [type_sym, index, nil, -1]
                puts "[MP SYNC] Battler #{battler_idx}: Switch to party slot #{index}"

              when :UseItem
                # Using item
                @choices[battler_idx] = [type_sym, index, nil, target_index]
                puts "[MP SYNC] Battler #{battler_idx}: UseItem #{index}"

              when :Run
                # Attempting to run
                @choices[battler_idx] = [type_sym, 0, nil, -1]
                puts "[MP SYNC] Battler #{battler_idx}: Run"

              when :Call
                # Calling Pokemon (if multi battles)
                @choices[battler_idx] = [type_sym, 0, nil, -1]
                puts "[MP SYNC] Battler #{battler_idx}: Call"

              else
                # Unknown choice type - use None as fallback
                @choices[battler_idx] = [:None, 0, nil, -1]
                puts "[MP SYNC] WARNING: Unknown choice type '#{type_sym}' for battler #{battler_idx}"
              end
            end

            $multiplayer_opponent_choice_data = nil
            puts "[MP SYNC] Opponent choices applied successfully"

          else
            puts "[MP SYNC] ERROR: No valid opponent choice data!"
            @scene.pbDisplayMessage("ERROR: Failed to receive opponent's action!")
            @scene.pbDisplayMessage("You win by default!")
            @decision = 1
            pbAbort
            return
          end
        end
      end

      # Helper to cleanup timer sprite
      def cleanup_timer_sprite
        if @multiplayer_timer_sprite
          @multiplayer_timer_sprite.bitmap.dispose if @multiplayer_timer_sprite.bitmap
          @multiplayer_timer_sprite.dispose
          @multiplayer_timer_sprite = nil
        end
      end

      # Override pbSwitchInBetween to synchronize Pokemon replacements when one faints
      unless method_defined?(:multiplayer_original_pbSwitchInBetween)
        alias multiplayer_original_pbSwitchInBetween pbSwitchInBetween
      end

      def pbSwitchInBetween(idxBattler, checkLaxOnly = false, canCancel = false)
        # Non-multiplayer battles use original code
        if !@multiplayer_battle_id
          return multiplayer_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)
        end

        battler = @battlers[idxBattler]
        return -1 if !battler

        puts "[MP SYNC] pbSwitchInBetween for battler #{idxBattler} (player owned: #{battler.pbOwnedByPlayer?})"

        if battler.pbOwnedByPlayer?
          # PLAYER needs to switch - let them choose and send to opponent
          puts "[MP SYNC] Player selecting replacement Pokemon..."
          idxParty = multiplayer_original_pbSwitchInBetween(idxBattler, checkLaxOnly, canCancel)

          if idxParty >= 0 && pbMultiplayerConnected?
            puts "[MP SYNC] Player selected party slot #{idxParty}, sending to opponent..."
            $multiplayer_client.send_battle_switch(
              @multiplayer_battle_id,
              @multiplayer_opponent_id,
              idxBattler,
              idxParty
            )
          end

          return idxParty

        else
          # OPPONENT needs to switch - wait for their choice
          puts "[MP SYNC] Waiting for opponent to select replacement Pokemon..."

          @scene.pbDisplay("Waiting for opponent to choose their next Pokémon...") if @scene

          # Reset opponent switch data
          $multiplayer_opponent_switch_received = false
          $multiplayer_opponent_switch_data = nil

          # Wait for opponent's switch choice with timeout (60 seconds)
          timeout = 1200  # 60 seconds at 0.05s intervals
          last_displayed_seconds = -1

          # Create/update timer sprite
          if !@multiplayer_timer_sprite
            @multiplayer_timer_sprite = Sprite.new
            @multiplayer_timer_sprite.z = 99999
            @multiplayer_timer_sprite.bitmap = Bitmap.new(200, 60)
            @multiplayer_timer_sprite.x = (Graphics.width - 200) / 2
            @multiplayer_timer_sprite.y = 10
          end

          while timeout > 0
            remaining_seconds = (timeout / 20.0).ceil

            # Update timer display
            if remaining_seconds != last_displayed_seconds
              @multiplayer_timer_sprite.bitmap.clear
              @multiplayer_timer_sprite.bitmap.fill_rect(0, 0, 200, 60, Color.new(0, 0, 0, 200))
              @multiplayer_timer_sprite.bitmap.fill_rect(2, 2, 196, 56, Color.new(40, 40, 60, 255))

              text_color = if remaining_seconds > 30
                Color.new(100, 255, 100)
              elsif remaining_seconds > 15
                Color.new(255, 255, 100)
              else
                Color.new(255, 100, 100)
              end

              pbSetSystemFont(@multiplayer_timer_sprite.bitmap)
              @multiplayer_timer_sprite.bitmap.font.size = 18
              @multiplayer_timer_sprite.bitmap.font.color = Color.new(200, 200, 200)
              @multiplayer_timer_sprite.bitmap.draw_text(0, 5, 200, 24, "Opponent choosing", 1)

              @multiplayer_timer_sprite.bitmap.font.size = 24
              @multiplayer_timer_sprite.bitmap.font.color = text_color
              @multiplayer_timer_sprite.bitmap.draw_text(0, 28, 200, 28, "#{remaining_seconds}s", 1)

              last_displayed_seconds = remaining_seconds
            end

            Graphics.update
            Input.update

            # Check for opponent forfeit
            if $multiplayer_battle_forfeited
              puts "[MP SYNC] Opponent forfeited during switch!"
              cleanup_timer_sprite
              @decision = 1
              pbAbort
              return -1
            end

            # Check connection
            if !pbMultiplayerConnected?
              puts "[MP SYNC] Connection lost during switch!"
              cleanup_timer_sprite
              @decision = 1
              pbAbort
              return -1
            end

            # Update network
            begin
              pbMultiplayerClient.update if pbMultiplayerConnected?
            rescue => e
              puts "[MP SYNC] Network error during switch: #{e.message}"
              cleanup_timer_sprite
              @decision = 1
              pbAbort
              return -1
            end

            # Check if opponent's switch received
            if $multiplayer_opponent_switch_received
              puts "[MP SYNC] Opponent's switch choice received!"
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

          # Timeout - opponent took too long
          puts "[MP SYNC] Opponent timeout during Pokemon selection!"
          cleanup_timer_sprite
          @scene.pbDisplayMessage("Opponent took too long to choose!")
          @scene.pbDisplayMessage("You win by timeout!")
          @decision = 1
          pbAbort
          return -1
        end
      end

      # Override pbItemMenu to block items in multiplayer battles
      unless method_defined?(:multiplayer_original_pbItemMenu)
        alias multiplayer_original_pbItemMenu pbItemMenu
      end

      def pbItemMenu(idxBattler, firstAction)
        # Block items in multiplayer battles
        if @multiplayer_battle_id
          pbDisplay("Items cannot be used in multiplayer battles!")
          return false
        end

        return multiplayer_original_pbItemMenu(idxBattler, firstAction)
      end

      # Override pbRegisterItem to completely disable items in multiplayer
      unless method_defined?(:multiplayer_original_pbRegisterItem)
        alias multiplayer_original_pbRegisterItem pbRegisterItem
      end

      def pbRegisterItem(idxBattler, item, idxTarget = -1, idxMove = -1)
        # Block item registration in multiplayer battles
        if @multiplayer_battle_id
          puts "[MP BATTLE] ERROR: Attempted to use item #{item} - items disabled in multiplayer!"
          return false
        end

        return multiplayer_original_pbRegisterItem(idxBattler, item, idxTarget, idxMove)
      end
    end

    $multiplayer_battle_patch_applied = true
    puts "[MP BATTLE SYNC] Improved battle sync patch installed successfully!"

  rescue => e
    puts "[MP BATTLE SYNC] ERROR installing patch: #{e.message}"
    puts "[MP BATTLE SYNC] Trace: #{e.backtrace.first(5).join("\n")}" if e.backtrace
  end
end

# Reinstall the patch with the new version
def apply_multiplayer_battle_patch(battle)
  ensure_multiplayer_battle_patch!
  puts "[MP BATTLE SYNC] Battle ##{battle.multiplayer_battle_id} ready with improved sync"
end

puts "[MP Battle Sync Fix] Improved battle synchronization loaded - fixes switching and choice desyncs"
