unless defined?(Queue)
  class Queue
    def initialize
      @que = []
      @waiting = []
      @que_lock = Mutex.new
    end

    def push(obj)
      @que_lock.synchronize do        @que.push(obj)
      end
    end

    alias << push

    def pop
      @que_lock.synchronize do        return @que.shift if !@que.empty?
      end
      nil
    end

    def empty?
      @que_lock.synchronize { @que.empty? }
    end

    def clear
      @que_lock.synchronize { @que.clear }
    end

    def length
      @que_lock.synchronize { @que.length }
    end
  end
end

module MultiplayerLibraries
  @libraries_available  =  false
  @error_message = nil

  def self.available?
    @libraries_available
  end

  def self.error_message
    @error_message
  end

  def self.check_and_load
    return @libraries_available if @libraries_available

    begin

      unless defined?(TCPSocket)
        begin
          require 'socket'
        rescue LoadError
          @error_message = "Socket library not available. Multiplayer requires Ruby with socket support."
          return false
        end
      end

      unless defined?(JSON)
        @error_message = "JSON module not loaded. This should not happen - check plugin load order."
        return false
      end

      unless defined?(Thread)
        begin
          require 'thread'
        rescue LoadError
          @error_message  =  "Thread library not available."
          return false
        end
      end

      @libraries_available = true
      puts "Multiplayer libraries loaded successfully!"
      return true

    rescue => e
      @error_message = "Error loading multiplayer libraries: #{e.message}"
      return false
    end
  end
end

MultiplayerLibraries.check_and_load
