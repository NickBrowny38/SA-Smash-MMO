class Battle::Scene
  remove_const(:MESSAGE_BOX_HEIGHT) if const_defined?(:MESSAGE_BOX_HEIGHT)
  remove_const(:PLAYER_BASE_X) if const_defined?(:PLAYER_BASE_X)
  remove_const(:PLAYER_BASE_Y) if const_defined?(:PLAYER_BASE_Y)
  remove_const(:FOE_BASE_X) if const_defined?(:FOE_BASE_X)
  remove_const(:FOE_BASE_Y) if const_defined?(:FOE_BASE_Y)
  remove_const(:FOCUSUSER_X) if const_defined?(:FOCUSUSER_X)
  remove_const(:FOCUSUSER_Y) if const_defined?(:FOCUSUSER_Y)
  remove_const(:FOCUSTARGET_X) if const_defined?(:FOCUSTARGET_X)
  remove_const(:FOCUSTARGET_Y) if const_defined?(:FOCUSTARGET_Y)

  MESSAGE_BOX_HEIGHT    =  Settings::SCREEN_HEIGHT / 4
  PLAYER_BASE_X        = Settings::SCREEN_WIDTH / 4
  PLAYER_BASE_Y         =  Settings::SCREEN_HEIGHT - (Settings::SCREEN_HEIGHT * 80 / 384).round
  FOE_BASE_X            =  Settings::SCREEN_WIDTH * 3 / 4
  FOE_BASE_Y           = (Settings::SCREEN_HEIGHT * 3 / 4) - (Settings::SCREEN_HEIGHT * 112 / 384).round
  FOCUSUSER_X          = Settings::SCREEN_WIDTH / 4
  FOCUSUSER_Y          = (Settings::SCREEN_HEIGHT * 7 / 12).round
  FOCUSTARGET_X        = Settings::SCREEN_WIDTH * 3 / 4
  FOCUSTARGET_Y        = Settings::SCREEN_HEIGHT / 4
end

puts "[MMO Battle Constants] Overridden battle constants to scale with resolution"
puts "[MMO Battle Constants] MESSAGE_BOX_HEIGHT=#{Battle::Scene::MESSAGE_BOX_HEIGHT}, PLAYER_BASE=#{Battle::Scene::PLAYER_BASE_X},#{Battle::Scene::PLAYER_BASE_Y}"
