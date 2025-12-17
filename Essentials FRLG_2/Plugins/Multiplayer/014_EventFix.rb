puts "Loading Event Loop Fix (014_EventFix.rb)..."

if true

class Game_Event
  if method_defined?(:refresh)
    alias mp_event_fix_original_refresh refresh

    def refresh
      begin
        if !defined?(pbIsMultiplayerMode?) || !pbIsMultiplayerMode?
          return mp_event_fix_original_refresh
        end
      rescue
        return mp_event_fix_original_refresh
      end

      return if @mp_refreshing
      @mp_refreshing  =  true

      begin

        mp_event_fix_original_refresh

        if @interpreter

          if @interpreter.instance_variable_defined?(:@event_ended)
            @starting = false if @interpreter.instance_variable_get(:@event_ended)
          end
        end
      rescue => e

      ensure
        @mp_refreshing = false
      end
    end
  end

  if method_defined?(:start)
    alias mp_event_fix_original_start start

    def start

      is_mp = false
      begin
        if defined?(pbIsMultiplayerMode?)
          is_mp = pbIsMultiplayerMode?
        end
      rescue

      end

      return mp_event_fix_original_start unless is_mp

      should_block = false
      if $game_player
        event_pos = [@x, @y]

        is_touch_trigger = (@trigger == 1 || @trigger == 2)

        if !is_touch_trigger &&
           $game_player.instance_variable_get(:@mp_blocked_events) &&
           $game_player.instance_variable_get(:@mp_blocked_events)[event_pos]

          should_block = true
        end
      end

      unless should_block
        mp_event_fix_original_start
      end
    end
  end
end

class Interpreter
  if method_defined?(:command_end)
    alias mp_event_fix_original_command_end command_end

    def command_end

      begin
        if !defined?(pbIsMultiplayerMode?) || !pbIsMultiplayerMode?
          return mp_event_fix_original_command_end
        end
      rescue
        return mp_event_fix_original_command_end
      end

      result  =  mp_event_fix_original_command_end

      @event_ended = true

      result
    end
  end

  if method_defined?(:command_115)
    alias mp_event_fix_original_command_115 command_115

    def command_115

      begin
        if !defined?(pbIsMultiplayerMode?) || !pbIsMultiplayerMode?
          return mp_event_fix_original_command_115
        end
      rescue
        return mp_event_fix_original_command_115
      end

      result = mp_event_fix_original_command_115

      @event_ended = true
      @list  =  nil

      $game_player.mp_block_current_event if $game_player

      result
    end
  end

  if method_defined?(:setup)
    alias mp_event_fix_original_setup setup

    def setup(*args)

      begin
        if !defined?(pbIsMultiplayerMode?) || !pbIsMultiplayerMode?
          return mp_event_fix_original_setup(*args)
        end
      rescue
        return mp_event_fix_original_setup(*args)
      end

      @event_ended = false
      mp_event_fix_original_setup(*args)
    end
  end
end

class Game_Player
  if method_defined?(:check_event_trigger_touch)
    alias mp_event_fix_original_check_event_trigger_touch check_event_trigger_touch

    def check_event_trigger_touch(*args)

      begin
        if !defined?(pbIsMultiplayerMode?) || !pbIsMultiplayerMode?
          return mp_event_fix_original_check_event_trigger_touch(*args)
        end
      rescue
        return mp_event_fix_original_check_event_trigger_touch(*args)
      end

      return false if @mp_checking_touch
      @mp_checking_touch  =  true

      result = false
      begin

        @mp_blocked_events ||= {}
        current_pos = [@x, @y]

        if @mp_blocked_events[current_pos]
          @mp_checking_touch = false
          return false
        end

        result = mp_event_fix_original_check_event_trigger_touch(*args)
      rescue => e

        begin
          result = mp_event_fix_original_check_event_trigger_touch(*args)
        rescue
          result = false
        end
      ensure
        @mp_checking_touch = false
      end

      result
    end
  end

  if method_defined?(:move_generic)
    alias mp_event_fix_original_move_generic move_generic

    def move_generic(dir, turn_enabled = true)

      begin
        if !defined?(pbIsMultiplayerMode?) || !pbIsMultiplayerMode?
          return mp_event_fix_original_move_generic(dir, turn_enabled)
        end
      rescue
        return mp_event_fix_original_move_generic(dir, turn_enabled)
      end

      old_pos  =  [@x, @y]

      result = mp_event_fix_original_move_generic(dir, turn_enabled)

      if [@x, @y] != old_pos
        @mp_blocked_events ||= {}
        @mp_blocked_events.delete(old_pos)
      end

      result
    end
  end

  def mp_block_current_event
    begin
      if !defined?(pbIsMultiplayerMode?) || !pbIsMultiplayerMode?
        return
      end
    rescue
      return
    end

    @mp_blocked_events ||= {}
    @mp_blocked_events[[@x, @y]] = true
  end
end

if defined?(MessageConfig)
  module MessageConfig
    class << self
      alias mp_event_fix_original_pbShowCommands pbShowCommands if respond_to?(:pbShowCommands)
    end

    def self.pbShowCommands(msgwindow, commands = nil, cmdIfCancel = 0, defaultCmd = 0, skin = nil)

      begin
        if !defined?(pbIsMultiplayerMode?) || !pbIsMultiplayerMode?
          if respond_to?(:mp_event_fix_original_pbShowCommands)
            return mp_event_fix_original_pbShowCommands(msgwindow, commands, cmdIfCancel, defaultCmd, skin)
          else
            return cmdIfCancel
          end
        end
      rescue
        if respond_to?(:mp_event_fix_original_pbShowCommands)
          return mp_event_fix_original_pbShowCommands(msgwindow, commands, cmdIfCancel, defaultCmd, skin)
        else
          return cmdIfCancel
        end
      end

      result = nil

      if respond_to?(:mp_event_fix_original_pbShowCommands)
        result = mp_event_fix_original_pbShowCommands(msgwindow, commands, cmdIfCancel, defaultCmd, skin)
      else

        result = cmdIfCancel
      end

      if result == cmdIfCancel && cmdIfCancel >= 0
        $game_player.mp_block_current_event if $game_player
      end

      result
    end
  end
end

end

puts "Event Loop Fix loaded - recursion guards active"
