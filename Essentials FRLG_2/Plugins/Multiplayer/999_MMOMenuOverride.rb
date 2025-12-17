class PokemonPauseMenu_Scene
  alias mmo_pbShowCommands pbShowCommands

  def pbShowCommands(commands)
    commands.reject! do |cmd|
      cmd[0] && cmd[0].downcase.include?("mon")
    end

    mmo_pbShowCommands(commands)
  end
end

if defined?(MenuHandlers)
  [:pokemon, :pokémon, :POKEMON, :party].each do |key|
    begin
      if defined?(MenuHandlers.handlers) && MenuHandlers.handlers.is_a?(Hash)
        if MenuHandlers.handlers[:pause_menu].is_a?(Hash)
          MenuHandlers.handlers[:pause_menu].delete(key)
        end
      end
    rescue

    end
  end
end

puts "[MMO Menu Override] Pokemon menu removed from pause menu"
