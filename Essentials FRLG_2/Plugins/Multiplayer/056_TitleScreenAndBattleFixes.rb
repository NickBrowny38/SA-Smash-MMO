#===============================================================================
# Fix 1: Add version number to title screen
# Fix 2: Hide MMO UI bars when quitting to title
# Fix 3: Disable switch prompt after opponent KO in multiplayer battles
#===============================================================================

# Fix 1: Update title screen version text to show actual multiplayer version
class MMOTitleScreen_Scene
  alias mmo_version_create_version_info create_version_info

  def create_version_info
    @sprites["version"] = Sprite.new(@viewport)
    @sprites["version"].bitmap = Bitmap.new(Graphics.width, 40)
    @sprites["version"].y = Graphics.height - 50
    @sprites["version"].z = 1

    bitmap = @sprites['version'].bitmap

    # Show actual multiplayer version from MultiplayerVersion module
    version_string = if defined?(MultiplayerVersion)
      "v#{MultiplayerVersion::MAJOR}.#{MultiplayerVersion::MINOR}.#{MultiplayerVersion::PATCH}"
    else
      "v0.1.6"
    end

    version_text = "v21.1 FRLG | Multiplayer #{version_string}"
    copyright_text = '© Pokemon Essentials'

    pbDrawTextPositions(bitmap, [
      [version_text, Graphics.width / 2, 0, 2,
       Color.new(180, 180, 200), Color.new(0, 0, 0, 100), true],
      [copyright_text, Graphics.width / 2, 20, 2,
       Color.new(150, 150, 170), Color.new(0, 0, 0, 80), true]
    ])
  end
end

# Fix 2: MMO UI cleanup is now handled in 021_QuitGameFix.rb
# This avoids the SystemStackError from recursive SceneManager calls

# Fix 3: Force "Set" battle style for multiplayer battles (no switch prompt after opponent KO)
# In competitive online Pokemon battles, you should NOT get a switch prompt when opponent's Pokemon faints
class Battle
  alias mmo_switch_initialize initialize

  def initialize(scene, p1, p2, player, opponent)
    mmo_switch_initialize(scene, p1, p2, player, opponent)

    # Force "Set" style (no switch prompt) for multiplayer battles
    # switchStyle = true means "Switch" style (prompt to switch when opponent faints)
    # switchStyle = false means "Set" style (no prompt, like competitive battles)
    if defined?(@multiplayer_battle_id) && @multiplayer_battle_id
      puts "[MP Battle] Forcing Set battle style (no switch prompt after opponent KO)"
      @switchStyle = false
    end
  end
end

puts "[MMO Fixes] Title screen version display, MMO UI cleanup on quit, and Set battle style for multiplayer loaded"
