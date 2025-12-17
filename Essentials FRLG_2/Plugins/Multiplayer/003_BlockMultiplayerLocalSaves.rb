module SaveData
  class << self
    alias multiplayer_save_to_file save_to_file

    def save_to_file(file_path)
      if defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?
        puts "[SAVE BLOCKED] Multiplayer mode - saves are server-side only!"
        puts "[SAVE BLOCKED] Attempted to save: #{file_path}"
        return false
      end

      puts "[SAVE] Singleplayer mode - saving to: #{file_path}"
      multiplayer_save_to_file(file_path)
    end
  end
end

MenuHandlers.add(:pause_menu, :save, {
  "name"      => _INTL("Save"),
  "order"     => 50,
  "condition" => proc {
    next !pbIsMultiplayerMode? && $game_system && !$game_system.save_disabled
  },
  'effect'    => proc { |menu|
    menu.pbHideMenu
    scene  =  PokemonSave_Scene.new
    screen = PokemonSaveScreen.new(scene)
    if screen.pbSaveScreen
      menu.pbEndScene
      next true
    end
    menu.pbShowMenu
    next false
  }
})

puts "Multiplayer local save blocking initialized - MP saves are server-side only"
