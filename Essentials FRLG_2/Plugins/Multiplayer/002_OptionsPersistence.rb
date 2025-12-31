module OptionsPersistence
  OPTIONS_FILE = "options.dat"

  OPTION_KEYS = [
    :textspeed, :battlescene, :battlestyle, :sendtoboxes, :givenicknames,
    :frame, :textskin, :screensize, :language, :runstyle,
    :bgmvolume, :sevolume, :textinput
  ]

  def self.options_path
    save_folder = System.data_directory rescue "."
    File.join(save_folder, OPTIONS_FILE)
  end

  def self.save_options
    return unless $PokemonSystem

    data = {}
    OPTION_KEYS.each do |key|
      data[key] = $PokemonSystem.send(key) if $PokemonSystem.respond_to?(key)
    end

    begin
      File.open(options_path, "wb") do |file|
        Marshal.dump(data, file)
      end
    rescue StandardError => e
      puts "[OptionsPersistence] Failed to save: #{e.message}"
    end
  end

  def self.load_options
    return unless File.exist?(options_path)

    begin
      data = File.open(options_path, "rb") { |file| Marshal.load(file) }
      return unless data.is_a?(Hash)

      $PokemonSystem ||= PokemonSystem.new
      options_changed = false

      data.each do |key, value|
        setter = "#{key}="
        if $PokemonSystem.respond_to?(setter)
          current_value = $PokemonSystem.send(key)
          if current_value != value
            $PokemonSystem.send(setter, value)
            options_changed = true
          end
        end
      end

      apply_loaded_options if options_changed
    rescue StandardError => e
      puts "[OptionsPersistence] Failed to load: #{e.message}"
    end
  end

  def self.apply_loaded_options
    return unless $PokemonSystem

    pbSetResizeFactor([$PokemonSystem.screensize, 4].min) rescue nil

    if $PokemonSystem.respond_to?(:textspeed)
      speed = MessageConfig.pbSettingToTextSpeed($PokemonSystem.textspeed) rescue nil
      MessageConfig.pbSetTextSpeed(speed) if speed
    end

    if $PokemonSystem.textskin
      idx = $PokemonSystem.textskin
      if defined?(Settings::SPEECH_WINDOWSKINS) && Settings::SPEECH_WINDOWSKINS[idx]
        MessageConfig.pbSetSpeechFrame("Graphics/Windowskins/" + Settings::SPEECH_WINDOWSKINS[idx]) rescue nil
      end
    end

    if $PokemonSystem.frame
      idx = $PokemonSystem.frame
      if defined?(Settings::MENU_WINDOWSKINS) && Settings::MENU_WINDOWSKINS[idx]
        MessageConfig.pbSetSystemFrame("Graphics/Windowskins/" + Settings::MENU_WINDOWSKINS[idx]) rescue nil
      end
    end
  end
end

class PokemonOption_Scene
  alias_method :options_persistence_end_scene, :pbEndScene

  def pbEndScene
    OptionsPersistence.save_options
    options_persistence_end_scene
  end
end

module Game
  class << self
    alias_method :options_persistence_set_up_system, :set_up_system

    def set_up_system
      options_persistence_set_up_system
      OptionsPersistence.load_options
    end
  end
end

puts "[OptionsPersistence] Module loaded"
