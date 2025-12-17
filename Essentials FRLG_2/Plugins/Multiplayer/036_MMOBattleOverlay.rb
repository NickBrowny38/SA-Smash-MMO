module MMOBattleOverlay
  BATTLE_WIDTH = 512
  BATTLE_HEIGHT = 384

  BATTLE_X = (Settings::SCREEN_WIDTH - BATTLE_WIDTH) / 2
  BATTLE_Y = (Settings::SCREEN_HEIGHT - BATTLE_HEIGHT) / 2

  @in_mmo_battle = false
  @battle_frame_sprite  =  nil
  @map_viewport = nil
  @dialog_viewport = nil  # High-z viewport for choice/confirmation dialogs

  def self.in_mmo_battle?
    return @in_mmo_battle
  end

  # Returns viewport for dialog boxes that renders ABOVE the battle
  def self.dialog_viewport
    if @in_mmo_battle && (!@dialog_viewport || @dialog_viewport.disposed?)
      @dialog_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @dialog_viewport.z = 100001  # Above battle frame (99998) and battle viewport (99999)
    end
    return @dialog_viewport
  end

  def self.start_mmo_battle
    @in_mmo_battle = true
    create_battle_frame
    # Create dialog viewport for choice boxes
    @dialog_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @dialog_viewport.z = 100001
    puts "[MMO Battle] Battle started - MMO UI should remain visible"
  end

  def self.end_mmo_battle
    @in_mmo_battle = false
    dispose_battle_frame
    # Dispose dialog viewport
    if @dialog_viewport && !@dialog_viewport.disposed?
      @dialog_viewport.dispose
      @dialog_viewport = nil
    end

    if $scene.is_a?(Scene_Map) && $scene.respond_to?(:restore_mmo_ui_after_battle)
      $scene.restore_mmo_ui_after_battle
    end
    puts "[MMO Battle] Battle ended - restoring MMO UI"
  end

  def self.create_battle_frame
    return if @battle_frame_sprite

    @battle_frame_sprite  =  Sprite.new
    @battle_frame_sprite.z = 99998
    @battle_frame_sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)

    @battle_frame_sprite.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 200))

    @battle_frame_sprite.bitmap.clear_rect(BATTLE_X, BATTLE_Y, BATTLE_WIDTH, BATTLE_HEIGHT)

    draw_battle_frame_border

    puts "[MMO Battle] Created PokéMMO-style battle frame at (#{BATTLE_X}, #{BATTLE_Y})"
  end

  def self.draw_battle_frame_border
    bitmap = @battle_frame_sprite.bitmap

    8.times do |i|
      offset = 8 - i
      opacity = 15 + (i * 10)
      c = Color.new(100, 150, 255, opacity)

      bitmap.fill_rect(BATTLE_X - offset, BATTLE_Y - offset, BATTLE_WIDTH + offset * 2, 1, c)

      bitmap.fill_rect(BATTLE_X - offset, BATTLE_Y + BATTLE_HEIGHT + offset - 1, BATTLE_WIDTH + offset * 2, 1, c)

      bitmap.fill_rect(BATTLE_X - offset, BATTLE_Y - offset, 1, BATTLE_HEIGHT + offset * 2, c)

      bitmap.fill_rect(BATTLE_X + BATTLE_WIDTH + offset - 1, BATTLE_Y - offset, 1, BATTLE_HEIGHT + offset * 2, c)
    end

    border_color = Color.new(255, 255, 255, 240)
    border_width = 3

    bitmap.fill_rect(BATTLE_X - border_width, BATTLE_Y - border_width,
                     BATTLE_WIDTH + border_width * 2, border_width, border_color)

    bitmap.fill_rect(BATTLE_X - border_width, BATTLE_Y + BATTLE_HEIGHT,
                     BATTLE_WIDTH + border_width * 2, border_width, border_color)

    bitmap.fill_rect(BATTLE_X - border_width, BATTLE_Y - border_width,
                     border_width, BATTLE_HEIGHT + border_width * 2, border_color)

    bitmap.fill_rect(BATTLE_X + BATTLE_WIDTH, BATTLE_Y - border_width,
                     border_width, BATTLE_HEIGHT + border_width * 2, border_color)
  end

  def self.dispose_battle_frame
    if @battle_frame_sprite
      @battle_frame_sprite.bitmap.dispose if @battle_frame_sprite.bitmap
      @battle_frame_sprite.dispose
      @battle_frame_sprite = nil
    end
  end

  def self.update_battle_frame

  end
end

class Battle::Scene

  MMO_PLAYER_BASE_X        = 128
  MMO_PLAYER_BASE_Y        = 384 - 80

  MMO_FOE_BASE_X           = 512 - 128
  MMO_FOE_BASE_Y           = (384 * 3 / 4) - 112

  class << self
    alias mmo_pbBattlerPosition pbBattlerPosition
    alias mmo_pbTrainerPosition pbTrainerPosition

    def pbBattlerPosition(index, sideSize = 1)
      if MMOBattleOverlay.in_mmo_battle?

        if (index & 1) == 0
          ret = [MMO_PLAYER_BASE_X, MMO_PLAYER_BASE_Y]
        else
          ret = [MMO_FOE_BASE_X, MMO_FOE_BASE_Y]
        end

        case sideSize
        when 2
          ret[0] += [-48, 48, 32, -32][index]
          ret[1] += [  0,  0, 16, -16][index]
        when 3
          ret[0] += [-80, 80,  0,  0, 80, -80][index]
          ret[1] += [  0,  0,  8, -8, 16, -16][index]
        end
        return ret
      end
      return mmo_pbBattlerPosition(index, sideSize)
    end

    def pbTrainerPosition(side, index = 0, sideSize = 1)
      if MMOBattleOverlay.in_mmo_battle?

        if side == 0
          ret = [MMO_PLAYER_BASE_X, MMO_PLAYER_BASE_Y - 16]
        else
          ret = [MMO_FOE_BASE_X, MMO_FOE_BASE_Y + 6]
        end

        case sideSize
        when 2
          ret[0] += [-48, 48, 32, -32][(2 * index) + side]
          ret[1] += [  0,  0,  0, -16][(2 * index) + side]
        when 3
          ret[0] += [-80, 80,  0,  0, 80, -80][(2 * index) + side]
          ret[1] += [  0,  0,  0, -8,  0, -16][(2 * index) + side]
        end
        return ret
      end
      return mmo_pbTrainerPosition(side, index, sideSize)
    end
  end

  alias mmo_pbStartBattle pbStartBattle

  def pbStartBattle(battle)
    @battle = battle
    @lastCmd = Array.new(@battle.battlers.length, 0)
    @lastMove = Array.new(@battle.battlers.length, 0)

    @mmo_battle_mode = defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?

    if @mmo_battle_mode

      @viewport = Viewport.new(
        MMOBattleOverlay::BATTLE_X,
        MMOBattleOverlay::BATTLE_Y,
        MMOBattleOverlay::BATTLE_WIDTH,
        MMOBattleOverlay::BATTLE_HEIGHT
      )
      @viewport.z = 99999
      MMOBattleOverlay.start_mmo_battle
      puts "[MMO Battle] Using constrained viewport: #{MMOBattleOverlay::BATTLE_WIDTH}x#{MMOBattleOverlay::BATTLE_HEIGHT} at (#{MMOBattleOverlay::BATTLE_X}, #{MMOBattleOverlay::BATTLE_Y})"
    else

      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99999
    end

    pbInitSprites
    pbBattleIntroAnimation
  end

  alias mmo_pbEndBattle pbEndBattle

  def pbEndBattle(result)
    MMOBattleOverlay.end_mmo_battle if MMOBattleOverlay.in_mmo_battle?
    mmo_pbEndBattle(result)
  end

  alias mmo_pbInitSprites pbInitSprites

  def pbInitSprites
    mmo_pbInitSprites

    if MMOBattleOverlay.in_mmo_battle?

      msg_y = 384 - 96
      msg_width  =  512

      if @sprites["messageBox"]
        @sprites["messageBox"].y = msg_y

        if @sprites["messageBox"].bitmap && @sprites["messageBox"].bitmap.width > msg_width
          old_bitmap = @sprites["messageBox"].bitmap
          @sprites['messageBox'].bitmap = Bitmap.new(msg_width, old_bitmap.height)
          @sprites["messageBox"].bitmap.blt(0, 0, old_bitmap, Rect.new(0, 0, msg_width, old_bitmap.height))
          old_bitmap.dispose
        end
      end

      if @sprites["messageWindow"]
        @sprites["messageWindow"].y = msg_y + 2
        @sprites["messageWindow"].width = msg_width - 32 if @sprites["messageWindow"].respond_to?(:width=)
      end

      if @sprites['commandWindow']
        @sprites["commandWindow"].x = 0
        @sprites["commandWindow"].y  =  msg_y
      end

      if @sprites["fightWindow"]
        @sprites["fightWindow"].x = 0
        @sprites["fightWindow"].y = msg_y
      end

      if @sprites["targetWindow"]
        @sprites['targetWindow'].x = 0
        @sprites["targetWindow"].y = msg_y
      end

      @battle.battlers.each_with_index do |battler, i|
        next if !battler
        databox = @sprites["dataBox_#{i}"]
        if databox

          databox.refresh
          puts "[MMO Battle] Databox #{i} positioned for #{battler.name}"
        end
      end

      puts '[MMO Battle] Adjusted UI positions for 512x384 viewport'
    end
  end

  alias mmo_pbCreateBackdropSprites pbCreateBackdropSprites

  def pbCreateBackdropSprites

    case @battle.time
    when 1 then time = "eve"
    when 2 then time = "night"
    end

    backdropFilename = @battle.backdrop
    baseFilename = @battle.backdrop
    baseFilename = sprintf("%s_%s", baseFilename, @battle.backdropBase) if @battle.backdropBase
    messageFilename = @battle.backdrop

    if time
      trialName = sprintf("%s_%s", backdropFilename, time)
      backdropFilename = trialName if pbResolveBitmap(sprintf("Graphics/Battlebacks/%s_bg", trialName))

      trialName = sprintf("%s_%s", baseFilename, time)
      baseFilename = trialName if pbResolveBitmap(sprintf('Graphics/Battlebacks/%s_base0', trialName))

      trialName = sprintf("%s_%s", messageFilename, time)
      messageFilename = trialName if pbResolveBitmap(sprintf('Graphics/Battlebacks/%s_message', trialName))
    end

    if !pbResolveBitmap(sprintf("Graphics/Battlebacks/%s_base0", baseFilename)) && @battle.backdropBase
      baseFilename = @battle.backdropBase
      if time
        trialName = sprintf('%s_%s', baseFilename, time)
        baseFilename = trialName if pbResolveBitmap(sprintf('Graphics/Battlebacks/%s_base0', trialName))
      end
    end

    battleBG   = "Graphics/Battlebacks/" + backdropFilename + "_bg"
    playerBase  =  "Graphics/Battlebacks/" + baseFilename + "_base0"
    enemyBase  = "Graphics/Battlebacks/" + baseFilename + "_base1"
    messageBG  = "Graphics/Battlebacks/" + messageFilename + "_message"

    bg_width  =  MMOBattleOverlay.in_mmo_battle? ? 512 : Graphics.width

    bg = pbAddSprite("battle_bg", 0, 0, battleBG, @viewport)
    bg.z  =  0

    bg2 = pbAddSprite("battle_bg2", -bg_width, 0, battleBG, @viewport)
    bg2.z = 0
    bg2.mirror = true

    2.times do |side|
      baseX, baseY = Battle::Scene.pbBattlerPosition(side)
      base = pbAddSprite("base_#{side}", baseX, baseY,
                         (side == 0) ? playerBase : enemyBase, @viewport)
      base.z = 1
      if base.bitmap
        base.ox = base.bitmap.width / 2
        base.oy  =  (side == 0) ? base.bitmap.height : base.bitmap.height / 2
      end
    end

    msg_y = MMOBattleOverlay.in_mmo_battle? ? (384 - 96) : (Graphics.height - 96)
    cmdBarBG  =  pbAddSprite("cmdBar_bg", 0, msg_y, messageBG, @viewport)
    cmdBarBG.z  =  180
  end
end

class Battle::Scene::Animation::Intro < Battle::Scene::Animation
  alias mmo_makeSlideSprite makeSlideSprite

  def makeSlideSprite(spriteName, deltaMult, appearTime, origin = nil)
    return if !@sprites[spriteName]

    if MMOBattleOverlay.in_mmo_battle?
      s = addSprite(@sprites[spriteName], origin)
      slide_distance = (512 * deltaMult).floor
      s.setDelta(0, slide_distance, 0)
      s.moveDelta(0, appearTime, -slide_distance, 0)
    else

      mmo_makeSlideSprite(spriteName, deltaMult, appearTime, origin)
    end
  end
end

alias mmo_pbSceneStandby pbSceneStandby unless defined?(mmo_pbSceneStandby)
alias mmo_pbBattleAnimation pbBattleAnimation unless defined?(mmo_pbBattleAnimation)

def pbSceneStandby

  if defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?

    RPG::Cache.clear
    Graphics.frame_reset
    yield

  else

    mmo_pbSceneStandby { yield }
  end
end

def pbBattleAnimation(bgm = nil, battletype = 0, foe = nil)

  if defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?
    pbBattleAnimationMMO(bgm, battletype, foe) { yield if block_given? }
  else

    mmo_pbBattleAnimation(bgm, battletype, foe) { yield if block_given? }
  end
end

def pbBattleAnimationMMO(bgm = nil, battletype = 0, foe = nil)
  $game_temp.in_battle = true

  playingBGS = nil
  playingBGM = nil
  if $game_system.is_a?(Game_System)
    playingBGS = $game_system.getPlayingBGS
    playingBGM = $game_system.getPlayingBGM
    $game_system.bgm_pause
    $game_system.bgs_pause
    if $game_temp.memorized_bgm
      playingBGM = $game_temp.memorized_bgm
      $game_system.bgm_position = $game_temp.memorized_bgm_position
    end
  end

  bgm = pbGetWildBattleBGM([]) if !bgm
  pbBGMPlay(bgm)

  yield if block_given?

  if $game_system.is_a?(Game_System)
    $game_system.bgm_resume(playingBGM)
    $game_system.bgs_resume(playingBGS)
  end

  $game_temp.memorized_bgm            = nil
  $game_temp.memorized_bgm_position   = 0
  $PokemonGlobal.nextBattleBGM        = nil
  $PokemonGlobal.nextBattleVictoryBGM  =  nil
  $PokemonGlobal.nextBattleCaptureME   =  nil
  $PokemonGlobal.nextBattleBack        =  nil
  $PokemonEncounters.reset_step_count

  $game_temp.in_battle  =  false
end

class Scene_Map
  alias mmo_battle_update update

  def update
    mmo_battle_update

    if MMOBattleOverlay.in_mmo_battle?

      if @remote_player_manager
        @remote_player_manager.update rescue nil
      end

      MMOBattleOverlay.update_battle_frame

      if $multiplayer_chat

        if !@chat_viewport
          @chat_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
          @chat_viewport.z = 100000
        end

        if !$multiplayer_chat.instance_variable_get(:@sprite)
          $multiplayer_chat.initialize_sprite(@chat_viewport)
        end

        $multiplayer_chat.update
      end
    end
  end
end

class Battle::Scene
  alias mmo_pbUpdate pbUpdate

  def pbUpdate(cw = nil)

    if MMOBattleOverlay.in_mmo_battle? && defined?($multiplayer_chat) && $multiplayer_chat

      if Input.triggerex?(0x54)
        $multiplayer_chat.open_input
      end
    end

    mmo_pbUpdate(cw)
  end
end

class Battle::Scene::PokemonDataBox < Sprite
  alias mmo_initializeDataBoxGraphic initializeDataBoxGraphic

  def initializeDataBoxGraphic(sideSize)
    mmo_initializeDataBoxGraphic(sideSize)

    if MMOBattleOverlay.in_mmo_battle?
      battle_width = 512
      battle_height = 384
      onPlayerSide = @battler.index.even?

      if onPlayerSide

        @spriteX  =  battle_width - 244
        @spriteY = battle_height - 192
      else

      end

      puts "[MMO Battle] Databox for #{@battler.name} will be positioned at (#{@spriteX}, #{@spriteY})"
    end
  end
end

class Battle::Scene::CommandMenu < Battle::Scene::MenuBase
  alias mmo_initialize initialize

  def initialize(viewport, z)
    mmo_initialize(viewport, z)

    if MMOBattleOverlay.in_mmo_battle?
      battle_width = 512
      battle_height = 384

      self.x  =  0
      self.y = battle_height - 96

      if @msgBox
        @msgBox.y = self.y + 2
        @msgBox.height = battle_height - self.y
      end

      if @sprites['background']
        @sprites["background"].y  =  self.y
      end

      if @buttons
        @buttons.each_with_index do |button, i|
          button.x = self.x + battle_width - 260
          button.x += (i.even? ? 0 : (@buttonBitmap.width / 2) - 4)
          button.y = self.y + 6
          button.y += (((i / 2) == 0) ? 0 : BUTTON_HEIGHT - 4)
        end
      end

      if @cmdWindow
        @cmdWindow.x  =  self.x + battle_width - 240
        @cmdWindow.y = self.y
        @cmdWindow.height = battle_height - self.y
      end

      puts "[MMO Battle] Repositioned CommandMenu for 512x384 viewport"
    end
  end
end

class Battle::Scene::FightMenu < Battle::Scene::MenuBase
  alias mmo_initialize initialize

  def initialize(viewport, z)
    mmo_initialize(viewport, z)

    if MMOBattleOverlay.in_mmo_battle?
      battle_width = 512
      battle_height = 384

      self.x = 0
      self.y = battle_height - 96

      if @sprites["background"]
        @sprites["background"].y = self.y
      end

      if @overlay
        old_bitmap = @overlay.bitmap
        @overlay.bitmap = Bitmap.new(battle_width, battle_height - self.y)
        @overlay.y = self.y

        pbSetNarrowFont(@overlay.bitmap) if defined?(pbSetNarrowFont)
      end

      if @infoOverlay
        old_bitmap = @infoOverlay.bitmap
        @infoOverlay.bitmap = Bitmap.new(battle_width, battle_height - self.y)
        @infoOverlay.y  =  self.y

        pbSetNarrowFont(@infoOverlay.bitmap) if defined?(pbSetNarrowFont)
      end

      if @buttons
        @buttons.each_with_index do |button, i|
          button.x = self.x + 4
          button.x += (i.even? ? 0 : (@buttonBitmap.width / 2) - 4)
          button.y = self.y + 6
          button.y += (((i / 2) == 0) ? 0 : BUTTON_HEIGHT - 4)
        end
      end

      if @typeIcon
        @typeIcon.x = self.x + battle_width - 96
        @typeIcon.y = self.y + 20
      end

      if @megaButton
        @megaButton.x  =  self.x + 120
        @megaButton.y = self.y - (@megaEvoBitmap.height / 2)
      end

      if @shiftButton
        @shiftButton.x = self.x + 4
        @shiftButton.y = self.y - @shiftBitmap.height
      end

      if @msgBox
        @msgBox.x = self.x + 320
        @msgBox.y = self.y
        @msgBox.width = battle_width - 320
        @msgBox.height = battle_height - self.y
      end

      if @cmdWindow
        @cmdWindow.x = self.x
        @cmdWindow.y = self.y
        @cmdWindow.width = 320
        @cmdWindow.height = battle_height - self.y
      end

      puts "[MMO Battle] Repositioned FightMenu for 512x384 viewport"
    end
  end
end

class Battle::Scene::TargetMenu < Battle::Scene::MenuBase
  alias mmo_initialize initialize

  def initialize(viewport, z, sideSize)
    mmo_initialize(viewport, z, sideSize)

    if MMOBattleOverlay.in_mmo_battle?
      battle_height = 384

      self.y = battle_height - 96

      if @infoDisplay
        @infoDisplay.y  =  self.y + 2
      end

      puts '[MMO Battle] Repositioned TargetMenu for 512x384 viewport'
    end
  end
end

class Battle::Scene

  MMO_FOCUSUSER_X    =  128
  MMO_FOCUSUSER_Y   = 224
  MMO_FOCUSTARGET_X = 384
  MMO_FOCUSTARGET_Y = 96

  alias mmo_pbAnimationCore pbAnimationCore

  def pbAnimationCore(animation, user, target, oppMove = false)

    if MMOBattleOverlay.in_mmo_battle?

      old_user_x  =  Battle::Scene::FOCUSUSER_X
      old_user_y = Battle::Scene::FOCUSUSER_Y
      old_target_x = Battle::Scene::FOCUSTARGET_X
      old_target_y = Battle::Scene::FOCUSTARGET_Y

      Battle::Scene.const_set(:FOCUSUSER_X, MMO_FOCUSUSER_X)
      Battle::Scene.const_set(:FOCUSUSER_Y, MMO_FOCUSUSER_Y)
      Battle::Scene.const_set(:FOCUSTARGET_X, MMO_FOCUSTARGET_X)
      Battle::Scene.const_set(:FOCUSTARGET_Y, MMO_FOCUSTARGET_Y)

      result  =  mmo_pbAnimationCore(animation, user, target, oppMove)

      Battle::Scene.const_set(:FOCUSUSER_X, old_user_x)
      Battle::Scene.const_set(:FOCUSUSER_Y, old_user_y)
      Battle::Scene.const_set(:FOCUSTARGET_X, old_target_x)
      Battle::Scene.const_set(:FOCUSTARGET_Y, old_target_y)

      return result
    else
      return mmo_pbAnimationCore(animation, user, target, oppMove)
    end
  end
end

# NOTE: Dialog patches removed - they were causing crashes and conflicts
# The battle system uses its own message windows within the battle viewport
# For now, dialogs will render within the battle area (may be clipped but functional)

puts "[MMO Battle Overlay] PokéMMO-style battle system loaded"
puts '[MMO Battle Overlay] Battles render in constrained 512x384 viewport'
puts "[MMO Battle Overlay] Map and remote players visible during battles"
