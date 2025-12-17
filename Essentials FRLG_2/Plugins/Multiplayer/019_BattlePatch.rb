class Battle
  attr_accessor :multiplayer_battle_id
  attr_accessor :multiplayer_opponent_id
  attr_accessor :multiplayer_is_host
  attr_accessor :multiplayer_turn
  attr_accessor :waiting_for_opponent
end

$multiplayer_opponent_choice_received = false
$multiplayer_opponent_choice_data = nil
$multiplayer_battle_patch_applied = false
$multiplayer_battle_forfeited = false

def ensure_multiplayer_battle_patch!
  return if $multiplayer_battle_patch_applied

  puts "[MP BATTLE] Installing multiplayer battle patch (pbCommandPhaseLoop)..."

  begin
    Battle.class_eval do      alias multiplayer_original_pbCommandPhaseLoop pbCommandPhaseLoop

      def pbCommandPhaseLoop(isPlayer)

        if !@multiplayer_battle_id
          return multiplayer_original_pbCommandPhaseLoop(isPlayer)
        end

        puts "[MP PATCH] pbCommandPhaseLoop called - isPlayer: #{isPlayer}, battle ##{@multiplayer_battle_id}"

        if isPlayer
          puts "[MP PATCH] Player's turn - choosing actions normally"

          turn_seed  =  @multiplayer_battle_id.to_i + (@multiplayer_turn || 0) * 1000
          srand(turn_seed)
          puts "[MP SYNC] Reseeded RNG for turn #{@multiplayer_turn}: seed=#{turn_seed}"

          multiplayer_original_pbCommandPhaseLoop(isPlayer)

          if @decision > 0
            puts "[MP BATTLE] Battle ended during player turn (decision: #{@decision})"
            return
          end

          if pbMultiplayerConnected?
            puts "[MP BATTLE] Sending player choices to opponent..."

            choices_data = @choices.map do |choice|
              {
                type: choice[0].to_s,
                move_index: choice[1].to_i,
                target_index: choice[3].to_i
              }
            end

            puts "[MP BATTLE] Serialized choices: #{choices_data.inspect}"

            $multiplayer_client.send_battle_choice(
              @multiplayer_battle_id,
              @multiplayer_opponent_id,
              @multiplayer_turn || 0,
              choices_data
            )

            puts "[MP BATTLE] Waiting for opponent's choices..."

            timeout = 1200
            last_displayed_seconds = -1

            if !@multiplayer_timer_sprite
              @multiplayer_timer_sprite = Sprite.new
              @multiplayer_timer_sprite.z = 99999
              @multiplayer_timer_sprite.bitmap = Bitmap.new(200, 60)
              @multiplayer_timer_sprite.x = (Graphics.width - 200) / 2
              @multiplayer_timer_sprite.y = 10
            end

            while timeout > 0

              remaining_seconds  =  (timeout / 20.0).ceil

              if remaining_seconds != last_displayed_seconds
                @multiplayer_timer_sprite.bitmap.clear

                @multiplayer_timer_sprite.bitmap.fill_rect(0, 0, 200, 60, Color.new(0, 0, 0, 200))
                @multiplayer_timer_sprite.bitmap.fill_rect(2, 2, 196, 56, Color.new(40, 40, 60, 255))

                if remaining_seconds > 30
                  text_color = Color.new(100, 255, 100)
                elsif remaining_seconds > 15
                  text_color = Color.new(255, 255, 100)
                else
                  text_color = Color.new(255, 100, 100)
                end

                pbSetSystemFont(@multiplayer_timer_sprite.bitmap)
                @multiplayer_timer_sprite.bitmap.font.size  =  18
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

              if $multiplayer_battle_forfeited
                puts "[MP BATTLE] Opponent forfeited - instant win!"

                if @multiplayer_timer_sprite
                  @multiplayer_timer_sprite.bitmap.dispose if @multiplayer_timer_sprite.bitmap
                  @multiplayer_timer_sprite.dispose
                  @multiplayer_timer_sprite  =  nil
                end

                @scene.pbDisplayMessage("Your opponent forfeited!")
                @scene.pbDisplayMessage("You win!")
                @decision = 1
                $multiplayer_battle_forfeited = false
                pbAbort
                return
              end

              if !pbMultiplayerConnected?
                puts "[MP BATTLE] Connection lost - instant win!"

                if @multiplayer_timer_sprite
                  @multiplayer_timer_sprite.bitmap.dispose if @multiplayer_timer_sprite.bitmap
                  @multiplayer_timer_sprite.dispose
                  @multiplayer_timer_sprite = nil
                end

                @scene.pbDisplayMessage("Connection lost!")
                @scene.pbDisplayMessage("Your opponent disconnected. You win!")
                @decision = 1
                pbAbort
                return
              end

              begin
                pbMultiplayerClient.update if pbMultiplayerConnected?
              rescue => e
                puts "[MP BATTLE] Client update error: #{e.message}"

                if @multiplayer_timer_sprite
                  @multiplayer_timer_sprite.bitmap.dispose if @multiplayer_timer_sprite.bitmap
                  @multiplayer_timer_sprite.dispose
                  @multiplayer_timer_sprite = nil
                end

                @scene.pbDisplayMessage('Network error occurred!')
                @scene.pbDisplayMessage("Your opponent appears to have disconnected. You win!")

                @decision = 1
                pbAbort
                return
              end

              if $multiplayer_opponent_choice_received
                puts "[MP BATTLE] Opponent ready!"

                if @multiplayer_timer_sprite
                  @multiplayer_timer_sprite.bitmap.dispose if @multiplayer_timer_sprite.bitmap
                  @multiplayer_timer_sprite.dispose
                  @multiplayer_timer_sprite = nil
                end

                $multiplayer_opponent_choice_received = false
                break
              end

              sleep(0.05)
              timeout -= 1
            end

            if timeout <= 0
              puts "[MP BATTLE] Opponent timeout (60s) - instant win!"

              if @multiplayer_timer_sprite
                @multiplayer_timer_sprite.bitmap.dispose if @multiplayer_timer_sprite.bitmap
                @multiplayer_timer_sprite.dispose
                @multiplayer_timer_sprite = nil
              end

              @scene.pbDisplayMessage("Your opponent took too long to respond!")
              @scene.pbDisplayMessage("You win by timeout!")
              @decision = 1
              pbAbort
              return
            end

            @multiplayer_turn = (@multiplayer_turn || 0) + 1
          end
        else

          puts "[MP PATCH] Opponent's turn - applying received choices"

          if @decision > 0
            puts "[MP BATTLE] Battle already ended (decision: #{@decision}), skipping opponent choice application"
            return
          end

          if $multiplayer_opponent_choice_data && $multiplayer_opponent_choice_data.is_a?(Array)
            puts "[MP BATTLE] Applying opponent's choices: #{$multiplayer_opponent_choice_data.inspect}"

            @battlers.each_with_index do |battler, i|
              next if !battler

              next if battler.pbOwnedByPlayer?

              data = $multiplayer_opponent_choice_data[0]
              next unless data

              type_str = data[:type] || data['type'] || 'None'
              type_sym = type_str.to_sym

              move_index  =  (data[:move_index] || data['move_index'] || 0).to_i

              move_object = battler.moves[move_index]

              target_index = data[:target_index] || data['target_index']
              if target_index
                target_index  =  target_index.to_i

                target_index = (target_index == 0) ? 1 : 0
              end

              @choices[i]  =  [type_sym, move_index, move_object, target_index]

              puts "[MP BATTLE] Applied choice to battler #{i}: type=#{type_sym}, move_index=#{move_index}, move=#{move_object ? move_object.name : 'nil'}, target=#{target_index}"
            end

            $multiplayer_opponent_choice_data = nil
          else
            puts "[MP BATTLE] ERROR: No opponent choice data available!"
            @scene.pbDisplayMessage("ERROR: Failed to receive opponent's move!")
            @scene.pbDisplayMessage("Treating as disconnect. You win!")
            @decision = 1
            pbAbort
            return
          end
        end
      end
    end

    $multiplayer_battle_patch_applied = true
    puts "[MP BATTLE] Multiplayer battle patch installed successfully!"
  rescue => e
    puts "[MP BATTLE] Failed to install patch: #{e.message}"
    puts "[MP BATTLE] Error: #{e.backtrace.first(3).join("\n")}" if e.backtrace
  end
end

def apply_multiplayer_battle_patch(battle)
  ensure_multiplayer_battle_patch!
  puts "[MP BATTLE] Battle instance ##{battle.multiplayer_battle_id} ready for multiplayer"
end

$multiplayer_opponent_choice_received = false
$multiplayer_opponent_choice_data = nil
$multiplayer_battle_forfeited = false
