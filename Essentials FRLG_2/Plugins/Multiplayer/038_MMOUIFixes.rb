class PokemonPauseMenu_Scene
  def pbRefresh
    pbShowMenu
  end
end

MenuHandlers.add(:pause_menu, :party, {
  "name"      => _INTL("Pokémon"),
  "order"     => 20,
  'condition' => proc { next $player.party_count > 0 },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    hidden_move = nil
    menu.pbHideMenu

    sscene = PokemonParty_Scene.new
    sscreen = PokemonPartyScreen.new(sscene, $player.party)
    hidden_move = sscreen.pbPokemonScreen
    (hidden_move) ? menu.pbEndScene : menu.pbShowMenu

    next false if !hidden_move
    $game_temp.in_menu = false
    pbUseHiddenMove(hidden_move[0], hidden_move[1])
    next true
  }
})

MenuHandlers.add(:pause_menu, :bag, {
  "name"      => _INTL("Bag"),
  'order'     => 20,
  "condition" => proc { next !pbInBugContest? },
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    item = nil
    menu.pbHideMenu

    scene = PokemonBag_Scene.new
    screen = PokemonBagScreen.new(scene, $bag)
    item = screen.pbStartScreen

    item ? menu.pbEndScene : menu.pbShowMenu
    next false unless item
    $game_temp.in_menu = false
    pbUseKeyItemInField(item)
    next true
  }
})

MenuHandlers.add(:pause_menu, :trainer_card, {
  "name"      => proc { next $player.name },
  "order"     => 50,
  "effect"    => proc { |menu|
    pbPlayDecisionSE
    menu.pbHideMenu
    pbFadeOutIn do      scene = PokemonTrainerCard_Scene.new
      screen = PokemonTrainerCardScreen.new(scene)
      screen.pbStartScreen
    end
    menu.pbShowMenu
    next false
  }
})

class PokemonTrainerCard_Scene
  alias mmo_ui_pbStartScene pbStartScene

  def pbStartScene

    Graphics.freeze

    mmo_ui_pbStartScene

    if @sprites["card"] && @sprites["card"].bitmap
      @sprites["card"].x = (Graphics.width - @sprites["card"].bitmap.width) / 2
      @sprites["card"].y = (Graphics.height - @sprites["card"].bitmap.height) / 2

      if @sprites['overlay']
        @sprites["overlay"].x = @sprites["card"].x
        @sprites["overlay"].y  =  @sprites["card"].y
      end

      if @sprites['trainer']
        card_offset_x = @sprites["card"].x
        card_offset_y  =  @sprites["card"].y
        @sprites["trainer"].x = 336 + card_offset_x
        @sprites["trainer"].y = 112 + card_offset_y
        @sprites["trainer"].x -= (@sprites["trainer"].bitmap.width - 128) / 2 if @sprites["trainer"].bitmap
        @sprites["trainer"].y -= (@sprites["trainer"].bitmap.height - 128) if @sprites["trainer"].bitmap
      end
    end

    Graphics.transition(0)
  end

  alias mmo_ui_pbDrawTrainerCardFront pbDrawTrainerCardFront

  def pbDrawTrainerCardFront

    mmo_ui_pbDrawTrainerCardFront

    overlay = @sprites["overlay"].bitmap
    overlay.clear

    baseColor   = Color.new(72, 72, 72)
    shadowColor = Color.new(160, 160, 160)

    totalsec = $stats.play_time.to_i
    hour = totalsec / 60 / 60
    min = totalsec / 60 % 60
    time = (hour > 0) ? _INTL("{1}h {2}m", hour, min) : _INTL("{1}m", min)

    if defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode? && defined?($multiplayer_created_at) && $multiplayer_created_at
      begin
        if $multiplayer_created_at =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/
          year, month, day, hour, min, sec  =  $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i
          created_time = Time.local(year, month, day, hour, min, sec)
          starttime  =  _INTL("{1} {2}, {3}", pbGetAbbrevMonthName(created_time.mon), created_time.day, created_time.year)
        else
          raise "Invalid timestamp format"
        end
      rescue => e
        $PokemonGlobal.startTime  =  Time.now if !$PokemonGlobal.startTime
        starttime = _INTL("{1} {2}, {3}", pbGetAbbrevMonthName($PokemonGlobal.startTime.mon), $PokemonGlobal.startTime.day, $PokemonGlobal.startTime.year)
      end
    else
      $PokemonGlobal.startTime  =  Time.now if !$PokemonGlobal.startTime
      starttime = _INTL('{1} {2}, {3}', pbGetAbbrevMonthName($PokemonGlobal.startTime.mon), $PokemonGlobal.startTime.day, $PokemonGlobal.startTime.year)
    end

    textPositions = [
      [_INTL("Name"), 34, 70, :left, baseColor, shadowColor],
      [$player.name, 302, 70, :right, baseColor, shadowColor],
      [_INTL('ID No.'), 332, 70, :left, baseColor, shadowColor],
      [sprintf("%05d", $player.public_ID), 468, 70, :right, baseColor, shadowColor],
      [_INTL("Money"), 34, 118, :left, baseColor, shadowColor],
      [_INTL("${1}", $player.money.to_s_formatted), 302, 118, :right, baseColor, shadowColor],
      [_INTL('Pokédex'), 34, 166, :left, baseColor, shadowColor],
      [sprintf('%d/%d', $player.pokedex.owned_count, $player.pokedex.seen_count), 302, 166, :right, baseColor, shadowColor],
      [_INTL("Time"), 34, 214, :left, baseColor, shadowColor],
      [time, 302, 214, :right, baseColor, shadowColor],
      [_INTL("Started"), 34, 262, :left, baseColor, shadowColor],
      [starttime, 302, 262, :right, baseColor, shadowColor]
    ]
    pbDrawTextPositions(overlay, textPositions)

    x = 72
    region = pbGetCurrentRegion(0)
    imagePositions = []
    8.times do |i|
      if $player.badges[i + (region * 8)]
        imagePositions.push(["Graphics/UI/Trainer Card/icon_badges", x, 310, i * 32, region * 32, 32, 32])
      end
      x += 48
    end
    pbDrawImagePositions(overlay, imagePositions)
  end
end

# Patch MoveSelectionSprite to respect MMO offsets
class MoveSelectionSprite < Sprite
  alias mmo_ui_refresh refresh

  def refresh
    # Call original refresh which sets x and y
    mmo_ui_refresh

    # Apply MMO offset if it exists
    if defined?(@mmo_offset_x) && @mmo_offset_x
      self.x += @mmo_offset_x
    end
    if defined?(@mmo_offset_y) && @mmo_offset_y
      self.y += @mmo_offset_y
    end
  end
end

class PokemonSummary_Scene
  alias mmo_ui_pbStartScene pbStartScene
  alias mmo_ui_pbStartForgetScene pbStartForgetScene
  alias mmo_ui_pbEndScene pbEndScene

  def pbStartScene(party, partyindex = 0, inbattle = false)
    Graphics.freeze

    mmo_ui_pbStartScene(party, partyindex, inbattle)

    # Calculate centering offsets (same as Bag scene)
    bg_width = 512   # Standard summary screen width
    bg_height = 384  # Standard summary screen height
    offset_x = (Graphics.width - bg_width) / 2
    offset_y = (Graphics.height - bg_height) / 2

    puts "[MMO Summary] Centering with offset (#{offset_x}, #{offset_y})"

    # Create dark overlay (covers entire screen)
    @sprites["mmo_overlay_bg"] = Sprite.new
    @sprites["mmo_overlay_bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["mmo_overlay_bg"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 150))
    @sprites["mmo_overlay_bg"].z = 99998

    # Create border (at centered position)
    @sprites["mmo_border"] = Sprite.new
    @sprites["mmo_border"].bitmap = Bitmap.new(bg_width + 8, bg_height + 8)
    @sprites["mmo_border"].x = offset_x - 4
    @sprites["mmo_border"].y = offset_y - 4
    @sprites["mmo_border"].z = 99999

    border_color = Color.new(60, 100, 180)
    border_color2 = Color.new(80, 140, 220)
    @sprites["mmo_border"].bitmap.fill_rect(0, 0, bg_width + 8, 4, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(0, bg_height + 4, bg_width + 8, 4, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(0, 0, 4, bg_height + 8, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(bg_width + 4, 0, 4, bg_height + 8, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(4, 4, bg_width, 1, border_color)
    @sprites["mmo_border"].bitmap.fill_rect(4, bg_height + 3, bg_width, 1, border_color)
    @sprites["mmo_border"].bitmap.fill_rect(4, 4, 1, bg_height, border_color)
    @sprites["mmo_border"].bitmap.fill_rect(bg_width + 3, 4, 1, bg_height, border_color)

    # Adjust ALL sprite positions by offset (same approach as Bag scene)
    @sprites.each do |key, sprite|
      next unless sprite && !sprite.disposed?
      next if key == "mmo_overlay_bg" || key == "mmo_border"

      # Offset sprite positions to center them
      # IMPORTANT: Don't check "if sprite.x" because 0 is falsy in Ruby!
      if sprite.respond_to?(:x=) && sprite.respond_to?(:y=)
        sprite.x += offset_x
        sprite.y += offset_y
        puts "[MMO Summary] Centered sprite '#{key}' at (#{sprite.x}, #{sprite.y})"
      end

      # Store offset in move selection sprite for refresh method
      if sprite.is_a?(MoveSelectionSprite)
        sprite.instance_variable_set(:@mmo_offset_x, offset_x)
        sprite.instance_variable_set(:@mmo_offset_y, offset_y)
      end
    end

    # Don't transition if in battle learn mode - let 046_BattleMoveLearningFix handle it
    unless defined?(@battle_learn_mode) && @battle_learn_mode
      Graphics.transition(0)
    end
  end

  def pbStartForgetScene(party, partyindex, move_to_learn)
    Graphics.freeze

    mmo_ui_pbStartForgetScene(party, partyindex, move_to_learn)

    # Calculate centering offsets (same as pbStartScene)
    bg_width = 512
    bg_height = 384
    offset_x = (Graphics.width - bg_width) / 2
    offset_y = (Graphics.height - bg_height) / 2

    puts "[MMO Forget Scene] Centering with offset (#{offset_x}, #{offset_y})"

    # Create dark overlay (covers entire screen)
    @sprites["mmo_overlay_bg"] = Sprite.new
    @sprites["mmo_overlay_bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["mmo_overlay_bg"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 150))
    @sprites["mmo_overlay_bg"].z = 99998

    # Create border (at centered position)
    @sprites["mmo_border"] = Sprite.new
    @sprites["mmo_border"].bitmap = Bitmap.new(bg_width + 8, bg_height + 8)
    @sprites["mmo_border"].x = offset_x - 4
    @sprites["mmo_border"].y = offset_y - 4
    @sprites["mmo_border"].z = 99999

    border_color = Color.new(60, 100, 180)
    border_color2 = Color.new(80, 140, 220)
    @sprites["mmo_border"].bitmap.fill_rect(0, 0, bg_width + 8, 4, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(0, bg_height + 4, bg_width + 8, 4, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(0, 0, 4, bg_height + 8, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(bg_width + 4, 0, 4, bg_height + 8, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(4, 4, bg_width, 1, border_color)
    @sprites["mmo_border"].bitmap.fill_rect(4, bg_height + 3, bg_width, 1, border_color)
    @sprites["mmo_border"].bitmap.fill_rect(4, 4, 1, bg_height, border_color)
    @sprites["mmo_border"].bitmap.fill_rect(bg_width + 3, 4, 1, bg_height, border_color)

    # Adjust ALL sprite positions by offset
    @sprites.each do |key, sprite|
      next unless sprite && !sprite.disposed?
      next if key == "mmo_overlay_bg" || key == "mmo_border"

      # Offset sprite positions to center them
      if sprite.respond_to?(:x=) && sprite.respond_to?(:y=)
        sprite.x += offset_x
        sprite.y += offset_y
        puts "[MMO Forget Scene] Centered sprite '#{key}' at (#{sprite.x}, #{sprite.y})"
      end

      # Store offset in move selection sprite for refresh method
      if sprite.is_a?(MoveSelectionSprite)
        sprite.instance_variable_set(:@mmo_offset_x, offset_x)
        sprite.instance_variable_set(:@mmo_offset_y, offset_y)
      end
    end

    Graphics.transition(0)
  end

  def pbEndScene

    if @sprites["mmo_overlay_bg"]
      @sprites["mmo_overlay_bg"].bitmap.dispose if @sprites["mmo_overlay_bg"].bitmap
      @sprites["mmo_overlay_bg"].dispose
      @sprites.delete("mmo_overlay_bg")
    end
    if @sprites["mmo_border"]
      @sprites["mmo_border"].bitmap.dispose if @sprites["mmo_border"].bitmap
      @sprites['mmo_border'].dispose
      @sprites.delete("mmo_border")
    end
    mmo_ui_pbEndScene
  end
end

class PokemonParty_Scene
  alias mmo_ui_party_pbStartScene pbStartScene
  alias mmo_ui_party_pbEndScene pbEndScene

  def pbStartScene(party, starthelptext, annotations = nil, multiselect = false, can_access_storage = false)

    Graphics.freeze

    if $player && $player.party && $player.party.length > 0 && $player.party[0]
      @initial_first_pokemon = {
        species: $player.party[0].species,
        form: $player.party[0].form,
        shiny: $player.party[0].shiny?
      }
    else
      @initial_first_pokemon  =  nil
    end

    mmo_ui_party_pbStartScene(party, starthelptext, annotations, multiselect, can_access_storage)

    center_offset_x = (Graphics.width - 512) / 2
    center_offset_y = (Graphics.height - 384) / 2

    if @sprites["partybg"]
      @sprites["partybg"].dispose
      @sprites.delete("partybg")
    end

    @sprites["mmo_overlay_bg"] = Sprite.new(@viewport)
    @sprites["mmo_overlay_bg"].bitmap  =  Bitmap.new(Graphics.width, Graphics.height)
    @sprites['mmo_overlay_bg'].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 200))
    @sprites["mmo_overlay_bg"].z = -2

    @sprites["mmo_partybg"] = IconSprite.new(center_offset_x, center_offset_y, @viewport)
    @sprites["mmo_partybg"].setBitmap("Graphics/UI/Party/bg")
    @sprites["mmo_partybg"].z = -1

    6.times do |i|
      panel_key = "pokemon#{i}"
      panel = @sprites[panel_key]

      if panel

        original_y = (16 * (i % 2)) + (96 * (i / 2))
        correct_x = center_offset_x + (i % 2) * 256
        correct_y = center_offset_y + original_y

        panel.x = correct_x
        panel.y = correct_y

        panel.visible = (i < @party.length)
      end
    end

    cancel_idx = @multiselect ? 7 : 6
    cancel_sprite = @sprites["pokemon#{cancel_idx}"]
    if cancel_sprite

      cancel_sprite.x = center_offset_x + 398
      cancel_sprite.y = center_offset_y + (@multiselect ? 346 : 328)
      cancel_sprite.visible = true
    end

    @sprites.each do |key, sprite|
      next unless sprite && !sprite.disposed?
      next if key.start_with?("pokemon")
      next if ["mmo_overlay_bg", "mmo_partybg"].include?(key)

      if sprite.respond_to?(:y) && sprite.y
        sprite.y += center_offset_y
      end
    end

    Graphics.transition(0)
  end

  def pbEndScene

    if @sprites["mmo_overlay_bg"]
      @sprites["mmo_overlay_bg"].bitmap.dispose if @sprites["mmo_overlay_bg"].bitmap && !@sprites["mmo_overlay_bg"].bitmap.disposed?
      @sprites["mmo_overlay_bg"].dispose if !@sprites["mmo_overlay_bg"].disposed?
      @sprites.delete("mmo_overlay_bg")
    end
    if @sprites["mmo_partybg"]
      @sprites["mmo_partybg"].dispose if !@sprites["mmo_partybg"].disposed?
      @sprites.delete("mmo_partybg")
    end

    pbDisposeSpriteHash(@sprites)
    @viewport.dispose if @viewport && !@viewport.disposed?

    if Graphics.frozen?
      Graphics.transition(0)
    end

    first_pokemon_changed = false
    if $player && $player.party && $player.party.length > 0 && $player.party[0]
      current_first = {
        species: $player.party[0].species,
        form: $player.party[0].form,
        shiny: $player.party[0].shiny?
      }

      if @initial_first_pokemon.nil?

        first_pokemon_changed = true
      elsif current_first[:species] != @initial_first_pokemon[:species] ||
            current_first[:form] != @initial_first_pokemon[:form] ||
            current_first[:shiny] != @initial_first_pokemon[:shiny]

        first_pokemon_changed = true
      end
    elsif @initial_first_pokemon

      first_pokemon_changed = true
    end

    if defined?(FollowingPkmn) && $player && $player.party && $player.party.length > 0
      FollowingPkmn.refresh(true) if FollowingPkmn.respond_to?(:refresh)

      if first_pokemon_changed && defined?($multiplayer_client) && $multiplayer_client && $multiplayer_client.connected?
        puts "[Following] First Pokemon changed, sending follower update to server"
        $multiplayer_client.send_follower_update
      end
    end
  end
end

class PokemonBag_Scene
  alias mmo_ui_bag_pbStartScene pbStartScene
  alias mmo_ui_bag_pbEndScene pbEndScene

  def pbStartScene(bag, choosing = false, filter_proc = nil, show_menu = true)

    Graphics.freeze

    mmo_ui_bag_pbStartScene(bag, choosing, filter_proc, show_menu)

    @sprites["mmo_overlay_bg"] = Sprite.new(@viewport)
    @sprites["mmo_overlay_bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["mmo_overlay_bg"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 120))
    @sprites["mmo_overlay_bg"].z = 100

    original_width = 512
    original_height = 384
    offset_x  =  (Graphics.width - original_width) / 2
    offset_y  =  (Graphics.height - original_height) / 2

    @sprites.each do |key, sprite|
      next unless sprite && !sprite.disposed?
      next if key == "mmo_overlay_bg" || key == "mmo_border"

      if sprite.respond_to?(:x) && sprite.respond_to?(:y)
        sprite.x += offset_x if sprite.x
        sprite.y += offset_y if sprite.y
      end

      if sprite.respond_to?(:z) && sprite.z
        sprite.z += 200000
      end
    end

    if @sprites["itemicon"]

      @sprites["itemicon"].y = offset_y + 336
    end

    if @sprites["itemtext"]

      @sprites["itemtext"].width = 416

    end

    if @sprites["pocketicon"]
      @sprites["pocketicon"].y -= 2
    end

    @sprites["mmo_border"] = Sprite.new(@viewport)
    @sprites["mmo_border"].bitmap = Bitmap.new(original_width + 8, original_height + 8)
    @sprites["mmo_border"].x = offset_x - 4
    @sprites["mmo_border"].y = offset_y - 4
    @sprites["mmo_border"].z = 100

    border_color = Color.new(60, 100, 180)
    border_color2 = Color.new(80, 140, 220)

    @sprites["mmo_border"].bitmap.fill_rect(0, 0, original_width + 8, 4, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(0, original_height + 4, original_width + 8, 4, border_color2)
    @sprites['mmo_border'].bitmap.fill_rect(0, 0, 4, original_height + 8, border_color2)
    @sprites["mmo_border"].bitmap.fill_rect(original_width + 4, 0, 4, original_height + 8, border_color2)

    @sprites["mmo_border"].bitmap.fill_rect(4, 4, original_width, 1, border_color)
    @sprites["mmo_border"].bitmap.fill_rect(4, original_height + 3, original_width, 1, border_color)
    @sprites["mmo_border"].bitmap.fill_rect(4, 4, 1, original_height, border_color)
    @sprites["mmo_border"].bitmap.fill_rect(original_width + 3, 4, 1, original_height, border_color)

    Graphics.transition(0)
  end

  def pbEndScene

    if @sprites["mmo_overlay_bg"]
      @sprites["mmo_overlay_bg"].bitmap.dispose if @sprites["mmo_overlay_bg"].bitmap
      @sprites["mmo_overlay_bg"].dispose
      @sprites.delete("mmo_overlay_bg")
    end
    if @sprites["mmo_border"]
      @sprites["mmo_border"].bitmap.dispose if @sprites["mmo_border"].bitmap
      @sprites["mmo_border"].dispose
      @sprites.delete("mmo_border")
    end

    @oldsprites = nil
    dispose
  end
end

MenuHandlers.add(:pc_menu, :pokemon_storage, {
  'name'      => proc {
    next ($player.seen_storage_creator) ? _INTL("{1}'s PC", GameData::Metadata.get.storage_creator) : _INTL("Someone's PC")
  },
  "order"     => 10,
  'effect'    => proc { |menu|
    pbMessage("\\se[PC access]" + _INTL("The Pokémon Storage System was opened."))
    command = 0
    loop do      command = pbShowCommandsWithHelp(nil,
                                       [_INTL("Organize Boxes"),
                                        _INTL("Withdraw Pokémon"),
                                        _INTL('Deposit Pokémon'),
                                        _INTL("See ya!")],
                                       [_INTL("Organize the Pokémon in Boxes and in your party."),
                                        _INTL("Move Pokémon stored in Boxes to your party."),
                                        _INTL('Store Pokémon in your party in Boxes.'),
                                        _INTL("Return to the previous menu.")], -1, command)
      break if command < 0
      case command
      when 0
        scene = PokemonStorageScene.new
        screen = PokemonStorageScreen.new(scene, $PokemonStorage)
        screen.pbStartScreen(0)
      when 1
        if $PokemonStorage.party_full?
          pbMessage(_INTL("Your party is full!"))
          next
        end

        scene = PokemonStorageScene.new
        screen = PokemonStorageScreen.new(scene, $PokemonStorage)
        screen.pbStartScreen(1)
      when 2
        count = 0
        $PokemonStorage.party.each do |p|
          count += 1 if p && !p.egg? && p.hp > 0
        end
        if count <= 1
          pbMessage(_INTL("Can't deposit the last Pokémon!"))
          next
        end

        scene = PokemonStorageScene.new
        screen = PokemonStorageScreen.new(scene, $PokemonStorage)
        screen.pbStartScreen(2)
      else
        break
      end
    end
    next false
  }
})

class PokemonStorageScene
  alias mmo_ui_storage_pbStartBox pbStartBox
  alias mmo_ui_storage_pbCloseBox pbCloseBox

  def pbStartBox(screen, command)

    @screen = screen
    @storage = screen.storage

    @bgviewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @bgviewport.z = 99999
    @boxviewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @boxviewport.z = 99999
    @boxsidesviewport  =  Viewport.new(0, 0, Graphics.width, Graphics.height)
    @boxsidesviewport.z = 99999
    @arrowviewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @arrowviewport.z = 99999
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @selection = 0
    @quickswap = false
    @sprites = {}
    @choseFromParty = false
    @command = command

    @sprites['mmo_overlay_bg'] = Sprite.new
    @sprites["mmo_overlay_bg"].bitmap  =  Bitmap.new(Graphics.width, Graphics.height)
    @sprites["mmo_overlay_bg"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 120))
    @sprites["mmo_overlay_bg"].z = 99996

    offset_x = (Graphics.width - 512) / 2
    offset_y = (Graphics.height - 384) / 2

    @mmo_storage_offset_x = offset_x
    @mmo_storage_offset_y = offset_y

    @sprites["box"] = PokemonBoxSprite.new(@storage, @storage.currentBox, @boxviewport)
    @sprites["box"].x += offset_x
    @sprites["box"].y += offset_y

    @sprites['boxsides'] = IconSprite.new(offset_x, offset_y, @boxsidesviewport)
    @sprites["boxsides"].setBitmap("Graphics/UI/Storage/overlay_main")

    @sprites["overlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @boxsidesviewport)
    pbSetSystemFont(@sprites['overlay'].bitmap)

    @sprites["pokemon"] = AutoMosaicPokemonSprite.new(@boxsidesviewport)
    @sprites['pokemon'].setOffset(PictureOrigin::CENTER)
    @sprites["pokemon"].x = 90 + offset_x
    @sprites["pokemon"].y = 134 + offset_y

    @sprites["boxparty"] = PokemonBoxPartySprite.new(@storage.party, @boxsidesviewport)
    if command != 2
      @sprites["boxparty"].x  =  182 + offset_x
      @sprites["boxparty"].y = Graphics.height
    else

      @sprites["boxparty"].x = 182 + offset_x
      @sprites["boxparty"].y = 32 + offset_y
    end

    @markingbitmap = AnimatedBitmap.new('Graphics/UI/Storage/markings')
    @sprites["markingbg"] = IconSprite.new(292 + offset_x, 68 + offset_y, @boxsidesviewport)
    @sprites["markingbg"].setBitmap("Graphics/UI/Storage/overlay_marking")
    @sprites['markingbg'].z = 10
    @sprites["markingbg"].visible = false

    @sprites["markingoverlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @boxsidesviewport)
    @sprites['markingoverlay'].z = 11
    @sprites["markingoverlay"].visible = false
    pbSetSystemFont(@sprites["markingoverlay"].bitmap)

    @sprites["arrow"] = PokemonBoxArrow.new(@arrowviewport)
    @sprites["arrow"].z += 1

    if command == 2
      pbPartySetArrow(@sprites["arrow"], @selection)
      pbUpdateOverlay(@selection, @storage.party)
    else
      pbSetArrow(@sprites['arrow'], @selection)
      pbUpdateOverlay(@selection)
    end

    pbSetMosaic(@selection)
    pbSEPlay("PC access")

    Graphics.freeze
    Graphics.transition(0)
  end

  alias mmo_ui_storage_pbSetArrow pbSetArrow

  def pbSetArrow(arrow, selection)
    mmo_ui_storage_pbSetArrow(arrow, selection)

    if @mmo_storage_offset_x && @mmo_storage_offset_y
      arrow.x += @mmo_storage_offset_x
      arrow.y += @mmo_storage_offset_y
    end
  end

  alias mmo_ui_storage_pbPartySetArrow pbPartySetArrow

  def pbPartySetArrow(arrow, selection)
    mmo_ui_storage_pbPartySetArrow(arrow, selection)

    if @mmo_storage_offset_x && @mmo_storage_offset_y
      arrow.x += @mmo_storage_offset_x
      arrow.y += @mmo_storage_offset_y
    end
  end

  MARK_WIDTH = 16
  MARK_HEIGHT = 16

  def drawMarkings(bitmap, x, y, _width, _height, markings)
    mark_variants = @markingbitmap.bitmap.height / MARK_HEIGHT
    markrect = Rect.new(0, 0, MARK_WIDTH, MARK_HEIGHT)
    (@markingbitmap.bitmap.width / MARK_WIDTH).times do |i|
      markrect.x = i * MARK_WIDTH
      markrect.y = [(markings[i] || 0), mark_variants - 1].min * MARK_HEIGHT
      bitmap.blt(x + (i * MARK_WIDTH), y, @markingbitmap.bitmap, markrect)
    end
  end

  def pbUpdateOverlay(selection, party = nil)
    overlay = @sprites["overlay"].bitmap
    overlay.clear

    offset_x  =  @mmo_storage_offset_x || 0
    offset_y = @mmo_storage_offset_y || 0

    buttonbase = Color.new(248, 248, 248)
    buttonshadow = Color.new(80, 80, 80)

    pbDrawTextPositions(
      overlay,
      [[_INTL("Party: {1}", (@storage.party.length rescue 0)), 270 + offset_x, 334 + offset_y, :center, buttonbase, buttonshadow, :outline],
       [_INTL("Exit"), 446 + offset_x, 334 + offset_y, :center, buttonbase, buttonshadow, :outline]]
    )

    pokemon  =  nil
    if @screen.pbHeldPokemon
      pokemon = @screen.pbHeldPokemon
    elsif selection >= 0
      pokemon = (party) ? party[selection] : @storage[@storage.currentBox, selection]
    end

    if !pokemon
      @sprites["pokemon"].visible = false
      return
    end

    @sprites['pokemon'].visible = true
    base   = Color.new(88, 88, 80)
    shadow = Color.new(168, 184, 184)
    nonbase   = Color.new(208, 208, 208)
    nonshadow = Color.new(224, 224, 224)
    pokename = pokemon.name

    textstrings = [
      [pokename, 10 + offset_x, 14 + offset_y, :left, base, shadow]
    ]

    if !pokemon.egg?
      imagepos = []

      if pokemon.male?
        textstrings.push([_INTL("♂"), 148 + offset_x, 14 + offset_y, :left, Color.new(24, 112, 216), Color.new(136, 168, 208)])
      elsif pokemon.female?
        textstrings.push([_INTL('♀'), 148 + offset_x, 14 + offset_y, :left, Color.new(248, 56, 32), Color.new(224, 152, 144)])
      end

      imagepos.push([_INTL("Graphics/UI/Storage/overlay_lv"), 6 + offset_x, 246 + offset_y])
      textstrings.push([pokemon.level.to_s, 28 + offset_x, 240 + offset_y, :left, base, shadow])

      if pokemon.ability
        textstrings.push([pokemon.ability.name, 86 + offset_x, 312 + offset_y, :center, base, shadow])
      else
        textstrings.push([_INTL("No ability"), 86 + offset_x, 312 + offset_y, :center, nonbase, nonshadow])
      end

      if pokemon.item
        textstrings.push([pokemon.item.name, 86 + offset_x, 348 + offset_y, :center, base, shadow])
      else
        textstrings.push([_INTL('No item'), 86 + offset_x, 348 + offset_y, :center, nonbase, nonshadow])
      end

      imagepos.push(["Graphics/UI/shiny", 156 + offset_x, 198 + offset_y]) if pokemon.shiny?

      typebitmap  =  AnimatedBitmap.new(_INTL('Graphics/UI/types'))
      pokemon.types.each_with_index do |type, i|
        type_number = GameData::Type.get(type).icon_position
        type_rect  =  Rect.new(0, type_number * 28, 64, 28)
        type_x = (pokemon.types.length == 1) ? 52 : 18 + (70 * i)
        overlay.blt(type_x + offset_x, 272 + offset_y, typebitmap.bitmap, type_rect)
      end

      drawMarkings(overlay, 70 + offset_x, 240 + offset_y, 128, 20, pokemon.markings)
      pbDrawImagePositions(overlay, imagepos)
    end

    pbDrawTextPositions(overlay, textstrings)
    @sprites["pokemon"].setPokemonBitmap(pokemon)
  end

  def pbShowPartyTab
    @sprites['arrow'].visible = false
    if !@screen.pbHeldPokemon
      pbUpdateOverlay(-1)
      pbSetMosaic(-1)
    end
    pbSEPlay("GUI storage show party panel")

    offset_y = @mmo_storage_offset_y || 0

    target_y = 32 + offset_y
    start_y = @sprites['boxparty'].y

    timer_start  =  System.uptime
    loop do      @sprites["boxparty"].y = lerp(start_y, target_y, 0.4, timer_start, System.uptime)
      self.update
      Graphics.update
      break if @sprites["boxparty"].y == target_y
    end
    Input.update
    @sprites["arrow"].visible = true
  end

  def pbHidePartyTab
    @sprites['arrow'].visible = false
    if !@screen.pbHeldPokemon
      pbUpdateOverlay(-1)
      pbSetMosaic(-1)
    end
    pbSEPlay("GUI storage hide party panel")

    start_y  =  @sprites["boxparty"].y
    target_y = Graphics.height

    timer_start = System.uptime
    loop do      @sprites['boxparty'].y = lerp(start_y, target_y, 0.4, timer_start, System.uptime)
      self.update
      Graphics.update
      break if @sprites["boxparty"].y == target_y
    end
    Input.update
    @sprites["arrow"].visible = true
  end

  alias mmo_ui_storage_pbSwitchBoxToRight pbSwitchBoxToRight

  def pbSwitchBoxToRight(new_box_number)
    start_x = @sprites["box"].x
    start_y = @sprites["box"].y
    newbox = PokemonBoxSprite.new(@storage, new_box_number, @boxviewport)
    newbox.x = start_x + 336
    newbox.y = start_y
    timer_start = System.uptime
    loop do      @sprites["box"].x = lerp(start_x, start_x - 336, 0.25, timer_start, System.uptime)
      newbox.x = @sprites["box"].x + 336
      self.update
      Graphics.update
      break if newbox.x == start_x
    end
    @sprites["box"].dispose
    @sprites["box"] = newbox
    Input.update
  end

  alias mmo_ui_storage_pbSwitchBoxToLeft pbSwitchBoxToLeft

  def pbSwitchBoxToLeft(new_box_number)
    start_x = @sprites['box'].x
    start_y = @sprites['box'].y
    newbox = PokemonBoxSprite.new(@storage, new_box_number, @boxviewport)
    newbox.x = start_x - 336
    newbox.y = start_y
    timer_start = System.uptime
    loop do      @sprites['box'].x = lerp(start_x, start_x + 336, 0.25, timer_start, System.uptime)
      newbox.x = @sprites["box"].x - 336
      self.update
      Graphics.update
      break if newbox.x == start_x
    end
    @sprites["box"].dispose
    @sprites["box"]  =  newbox
    Input.update
  end

  def pbCloseBox

    if @sprites['mmo_overlay_bg']
      @sprites["mmo_overlay_bg"].bitmap.dispose if @sprites["mmo_overlay_bg"].bitmap
      @sprites["mmo_overlay_bg"].dispose
      @sprites.delete("mmo_overlay_bg")
    end

    pbDisposeSpriteHash(@sprites)
    @markingbitmap&.dispose
    @bgviewport.dispose
    @boxviewport.dispose
    @boxsidesviewport.dispose
    @arrowviewport.dispose
  end
end

def pbForgetMove(pkmn, moveToLearn)
  ret = -1

  scene = PokemonSummary_Scene.new
  screen = PokemonSummaryScreen.new(scene)
  ret = screen.pbStartForgetScreen([pkmn], 0, moveToLearn)
  return ret
end

class PokemonEvolutionScene
  def pbStartScreen(pokemon, newspecies)

    @mmo_ui_was_visible  =  false
    if $scene && $scene.respond_to?(:spriteset) && $scene.spriteset && $scene.spriteset.respond_to?(:mmo_ui_overlay)
      mmo_ui = $scene.spriteset.mmo_ui_overlay
      if mmo_ui && mmo_ui.respond_to?(:visible)
        @mmo_ui_was_visible = mmo_ui.visible
        mmo_ui.hide_ui if mmo_ui.respond_to?(:hide_ui)
      end
    end

    @pokemon = pokemon
    @newspecies  =  newspecies
    @sprites = {}

    offset_x = (Graphics.width - 512) / 2
    offset_y = (Graphics.height - 384) / 2

    @bgviewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @bgviewport.z = 99999
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @msgviewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @msgviewport.z = 99999

    @sprites["mmo_dark_overlay"] = Sprite.new(@bgviewport)
    @sprites['mmo_dark_overlay'].bitmap  =  Bitmap.new(Graphics.width, Graphics.height)
    @sprites["mmo_dark_overlay"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 160))
    @sprites["mmo_dark_overlay"].z = 0

    @sprites['background'] = IconSprite.new(offset_x, offset_y, @bgviewport)
    @sprites["background"].setBitmap("Graphics/UI/evolution_bg")
    @sprites['background'].z = 100

    rsprite1 = PokemonSprite.new(@viewport)
    rsprite1.setOffset(PictureOrigin::CENTER)
    rsprite1.setPokemonBitmap(@pokemon, false)
    rsprite1.x = offset_x + 256
    rsprite1.y = offset_y + (384 - 64) / 2
    rsprite1.z = 200

    rsprite2 = PokemonSprite.new(@viewport)
    rsprite2.setOffset(PictureOrigin::CENTER)
    rsprite2.setPokemonBitmapSpecies(@pokemon, @newspecies, false)
    rsprite2.x = rsprite1.x
    rsprite2.y = rsprite1.y
    rsprite2.z = 200
    rsprite2.visible = false

    @sprites["rsprite1"]  =  rsprite1
    @sprites["rsprite2"] = rsprite2

    @sprites["msgwindow"] = pbCreateMessageWindow(@msgviewport)
    @sprites["msgwindow"].x = offset_x
    @sprites["msgwindow"].width = 512 if @sprites["msgwindow"].respond_to?(:width=)
    @sprites["msgwindow"].z  =  300

    set_up_animation
    pbFadeInAndShow(@sprites) { pbUpdate }
  end

  alias mmo_ui_evo_pbEndScreen pbEndScreen

  def pbEndScreen(need_fade_out = true)

    mmo_ui_evo_pbEndScreen(need_fade_out)

    if @mmo_ui_was_visible && $scene && $scene.respond_to?(:spriteset) && $scene.spriteset && $scene.spriteset.respond_to?(:mmo_ui_overlay)
      mmo_ui = $scene.spriteset.mmo_ui_overlay
      mmo_ui.show_ui if mmo_ui && mmo_ui.respond_to?(:show_ui)
    end

    if defined?($client) && $client && $client.connected?
      $client.send_player_data
    end
  end

  alias mmo_ui_evo_pbEvolutionSuccess pbEvolutionSuccess

  def pbEvolutionSuccess
    $stats.evolution_count += 1

    cry_time = GameData::Species.cry_length(@newspecies, @pokemon.form)
    Pokemon.play_cry(@newspecies, @pokemon.form)
    timer_start = System.uptime
    loop do      Graphics.update
      pbUpdate
      break if System.uptime - timer_start >= cry_time
    end
    pbBGMStop

    pbMEPlay("Evolution success")
    newspeciesname = GameData::Species.get(@newspecies).name
    pbMessageDisplay(@sprites['msgwindow'],
                     "\\se[]" + _INTL("Congratulations! Your {1} evolved into {2}!",
                                      @pokemon.name, newspeciesname) + '\\wt[80]') { pbUpdate }
    @sprites["msgwindow"].text = ""

    pbEvolutionMethodAfterEvolution

    was_fainted = @pokemon.fainted?
    @pokemon.species = @newspecies
    @pokemon.hp = 0 if was_fainted
    @pokemon.calc_stats
    @pokemon.ready_to_evolve  =  false

    was_owned = $player.owned?(@newspecies)
    $player.pokedex.register(@pokemon)
    $player.pokedex.set_owned(@newspecies)
    moves_to_learn = []
    movelist = @pokemon.getMoveList
    movelist.each do |i|
      next if i[0] != 0 && i[0] != @pokemon.level
      moves_to_learn.push(i[1])
    end

    if Settings::SHOW_NEW_SPECIES_POKEDEX_ENTRY_MORE_OFTEN && !was_owned &&
       $player.has_pokedex && $player.pokedex.species_in_unlocked_dex?(@pokemon.species)
      pbMessageDisplay(@sprites["msgwindow"],
                       _INTL("{1}'s data was added to the Pokédex.", newspeciesname)) { pbUpdate }
      $player.pokedex.register_last_seen(@pokemon)

      scene = PokemonPokedexInfo_Scene.new
      screen = PokemonPokedexInfoScreen.new(scene)
      screen.pbDexEntry(@pokemon.species)
      @sprites["msgwindow"].text = "" if moves_to_learn.length > 0
      pbEndScreen(false) if moves_to_learn.length == 0
    end

    moves_to_learn.each do |move|
      pbLearnMove(@pokemon, move, true) { pbUpdate }
    end
  end
end

def pbTopRightWindow(text, scene = nil)
  window = Window_AdvancedTextPokemon.new(text)
  window.width = 198

  offset_x = (Graphics.width - 512) / 2
  window.x = offset_x + 512 - window.width
  window.y = 0
  window.z = 99999

  pbPlayDecisionSE
  loop do    Graphics.update
    Input.update
    window.update
    scene&.pbUpdate
    break if Input.trigger?(Input::USE)
  end
  window.dispose
end

alias mmo_ui_original_pbFadeOutInWithMusic pbFadeOutInWithMusic

def pbFadeOutInWithMusic(zViewport  =  99999, nofadeout  =  false)

  yield
end

alias mmo_ui_original_pbFadeOutIn pbFadeOutIn

def pbFadeOutIn(zViewport = 99999, nofadeout = false)

  yield
end

ItemHandlers::UseOnPokemon.add(:RARECANDY, proc { |item, qty, pkmn, scene|
  if pkmn.shadowPokemon?
    scene.pbDisplay(_INTL("It won't have any effect."))
    next false
  end
  if pkmn.level >= GameData::GrowthRate.max_level
    new_species = pkmn.check_evolution_on_level_up
    if !Settings::RARE_CANDY_USABLE_AT_MAX_LEVEL || !new_species
      scene.pbDisplay(_INTL("It won't have any effect."))
      next false
    end

    evo = PokemonEvolutionScene.new
    evo.pbStartScreen(pkmn, new_species)
    evo.pbEvolution
    evo.pbEndScreen

    if defined?($client) && $client && $client.connected?
      $client.send_player_data
    end

    if scene.is_a?(PokemonPartyScreen)
      scene.pbHardRefresh
    end
    next true
  end

  pbSEPlay("Pkmn level up")
  pbChangeLevel(pkmn, pkmn.level + qty, scene)
  scene.pbHardRefresh
  next true
})

class Sprite_Picture
  alias mmo_ui_original_update update

  def update
    mmo_ui_original_update

    if @sprite && defined?(MMOResolution)

      horizontal_offset = (Graphics.width - 512) / 2
      vertical_offset = (Graphics.height - 384) / 2

      @sprite.x = @picture.x + horizontal_offset
      @sprite.y = @picture.y + vertical_offset
    end
  end
end

puts "[MMO UI Fixes] Pause menu hiding/showing fixed"
puts "[MMO UI Fixes] Trainer card centered on screen"
puts "[MMO UI Fixes] Pokemon summary screen centered with overlay"
puts "[MMO UI Fixes] Pokemon party screen centered with border (shifted from 800px to 512px layout)"
puts '[MMO UI Fixes] Bag screen centered with border, fixed item icon/text positioning'
puts "[MMO UI Fixes] PC Storage screen centered with overlay, no background, cursor positioned correctly"
puts "[MMO UI Fixes] All menus now display instantly without fade effects"
puts "[MMO UI Fixes] TM/HM usage opens summary without fade"
puts "[MMO UI Fixes] Evolution screen: centered 512x384 with light background, dimmed map outside, saves to server"
puts "[MMO UI Fixes] Stat window (rare candy/level up) positioned within centered area"
puts '[MMO UI Fixes] pbFadeOutInWithMusic & pbFadeOutIn overridden - all fade/black screens removed'
puts "[MMO UI Fixes] Party screen shows overworld behind (no black screen), double-save for evolution persistence"
puts "[MMO UI Fixes] Event pictures (Show Picture) centered for 800x600 resolution"
