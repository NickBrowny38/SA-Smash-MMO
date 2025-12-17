EventHandlers.add(:on_player_change_map, :debug_resolution,
  proc { |_new_map_id, _old_map_id, _is_transfer|
    next if $resolution_debug_printed
    $resolution_debug_printed = true

    puts ""
    puts "=== RESOLUTION DEBUG INFO ==="
    puts "Settings::SCREEN_WIDTH = #{Settings::SCREEN_WIDTH}"
    puts "Settings::SCREEN_HEIGHT = #{Settings::SCREEN_HEIGHT}"
    puts "Graphics.width = #{Graphics.width}"
    puts "Graphics.height  =  #{Graphics.height}"
    puts ''
    puts "=== BATTLE SCENE CONSTANTS ==="
    puts "Battle::Scene::MESSAGE_BOX_HEIGHT  =  #{Battle::Scene::MESSAGE_BOX_HEIGHT}"
    puts "Battle::Scene::PLAYER_BASE_X = #{Battle::Scene::PLAYER_BASE_X}"
    puts "Battle::Scene::PLAYER_BASE_Y = #{Battle::Scene::PLAYER_BASE_Y}"
    puts "Battle::Scene::FOE_BASE_X = #{Battle::Scene::FOE_BASE_X}"
    puts "Battle::Scene::FOE_BASE_Y = #{Battle::Scene::FOE_BASE_Y}"
    puts "Battle::Scene::FOCUSUSER_X  =  #{Battle::Scene::FOCUSUSER_X}"
    puts "Battle::Scene::FOCUSUSER_Y  =  #{Battle::Scene::FOCUSUSER_Y}"
    puts "Battle::Scene::FOCUSTARGET_X = #{Battle::Scene::FOCUSTARGET_X}"
    puts "Battle::Scene::FOCUSTARGET_Y  =  #{Battle::Scene::FOCUSTARGET_Y}"
    puts ''
    puts '=== EXPECTED VALUES (for 800x600) ==='
    puts "MESSAGE_BOX_HEIGHT should be: 150"
    puts "PLAYER_BASE_X should be: 200"
    puts "FOE_BASE_X should be: 600"
    puts "FOCUSUSER_X should be: 200"
    puts 'FOCUSUSER_Y should be: 350'
    puts "FOCUSTARGET_X should be: 600"
    puts "FOCUSTARGET_Y should be: 150"
    puts "============================"
    puts ""
  }
)
