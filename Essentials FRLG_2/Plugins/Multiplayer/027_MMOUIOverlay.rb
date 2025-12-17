class MMOUIOverlay
  attr_reader :sprites
  attr_reader :viewport

  def initialize(viewport = nil)
    @viewport  =  viewport
    @sprites = {}
    @disposed = false
    @visible = true

    create_ui_elements
  end

  def create_ui_elements
    create_top_panel
    create_right_panel

    puts '[MMO UI] UI overlay created'
  end

  def create_top_panel
    @sprites[:top_panel] = Sprite.new(@viewport)
    @sprites[:top_panel].bitmap  =  Bitmap.new(MMOResolution::TARGET_WIDTH, MMOResolution::UI_TOP_HEIGHT)
    @sprites[:top_panel].bitmap.fill_rect(0, 0, MMOResolution::TARGET_WIDTH, MMOResolution::UI_TOP_HEIGHT, Color.new(0, 0, 0, 90))
    @sprites[:top_panel].z = 95000
  end

  def create_right_panel

    @sprites[:right_panel] = Sprite.new(@viewport)
    @sprites[:right_panel].bitmap = Bitmap.new(MMOResolution::UI_RIGHT_WIDTH, MMOResolution::GAME_HEIGHT)
    @sprites[:right_panel].bitmap.fill_rect(0, 0, MMOResolution::UI_RIGHT_WIDTH, MMOResolution::GAME_HEIGHT, Color.new(0, 0, 0, 90))
    @sprites[:right_panel].x = MMOResolution::GAME_WIDTH
    @sprites[:right_panel].y = MMOResolution::UI_TOP_HEIGHT
    @sprites[:right_panel].z = 95000
  end

  def visible=(value)
    @visible = value
    @sprites.each_value { |sprite| sprite.visible = value if sprite }
  end

  def visible?
    @visible
  end

  def update
    return if @disposed

  end

  def dispose
    return if @disposed
    @sprites.each_value { |sprite| sprite.dispose if sprite && !sprite.disposed? }
    @sprites.clear
    @disposed  =  true
  end

  def disposed?
    @disposed
  end
end

class MMOPartyUI
  SLOT_HEIGHT = 72
  SLOT_PADDING = 3
  POKEMON_ICON_SIZE = 48

  attr_reader :sprites
  attr_reader :selected_slot
  attr_reader :dragging_slot

  def initialize(viewport = nil)
    @viewport = viewport
    @sprites = {}
    @disposed = false
    @visible = true
    @party_data = []
    @selected_slot  =  nil
    @dragging_slot  =  nil
    @drag_start_x  =  0
    @drag_start_y = 0

    @icon_bitmaps  =  []
    @icon_frames_count  =  []
    @icon_current_frame  =  []

    create_party_slots
  end

  def create_party_slots

    6.times do |i|
      slot_y = MMOResolution::UI_TOP_HEIGHT + (i * (SLOT_HEIGHT + SLOT_PADDING))

      @sprites["slot_#{i}_bg"] = Sprite.new(@viewport)
      @sprites["slot_#{i}_bg"].bitmap = Bitmap.new(MMOResolution::UI_RIGHT_WIDTH - 8, SLOT_HEIGHT)
      @sprites["slot_#{i}_bg"].bitmap.fill_rect(0, 0, MMOResolution::UI_RIGHT_WIDTH - 8, SLOT_HEIGHT, Color.new(40, 40, 40, 200))
      @sprites["slot_#{i}_bg"].x = MMOResolution::GAME_WIDTH + 4
      @sprites["slot_#{i}_bg"].y = slot_y
      @sprites["slot_#{i}_bg"].z = 95001

      @sprites["slot_#{i}_icon"] = Sprite.new(@viewport)
      @sprites["slot_#{i}_icon"].x = MMOResolution::GAME_WIDTH + 4
      @sprites["slot_#{i}_icon"].y = slot_y + 4
      @sprites["slot_#{i}_icon"].z = 95002

      @sprites["slot_#{i}_text"]  =  Sprite.new(@viewport)
      @sprites["slot_#{i}_text"].bitmap = Bitmap.new(MMOResolution::UI_RIGHT_WIDTH - 56, SLOT_HEIGHT)
      @sprites["slot_#{i}_text"].x = MMOResolution::GAME_WIDTH + 54
      @sprites["slot_#{i}_text"].y = slot_y
      @sprites["slot_#{i}_text"].z = 95003
    end

    puts "[MMO Party UI] Created 6 party slots"
  end

  def refresh_party
    return unless $player && $player.party

    $player.party.each_with_index do |pkmn, i|
      break if i >= 6
      next unless pkmn

      begin
        # Clear existing icon sprite first to prevent overlapping
        icon_sprite = @sprites["slot_#{i}_icon"]
        if icon_sprite
          icon_sprite.bitmap = nil
          icon_sprite.src_rect = Rect.new(0, 0, 0, 0)
        end

        # Dispose old bitmap
        if @icon_bitmaps[i]
          @icon_bitmaps[i].dispose
          @icon_bitmaps[i] = nil
        end

        filename = GameData::Species.icon_filename_from_pokemon(pkmn)
        @icon_bitmaps[i] = AnimatedBitmap.new(filename)

        icon_sprite.bitmap = @icon_bitmaps[i].bitmap

        icon_height = @icon_bitmaps[i].height
        icon_sprite.src_rect = Rect.new(0, 0, icon_height, icon_height)
        @icon_frames_count[i] = @icon_bitmaps[i].width / icon_height
        @icon_current_frame[i]  =  0

        scale = POKEMON_ICON_SIZE.to_f / icon_height
        icon_sprite.zoom_x = scale
        icon_sprite.zoom_y = scale
      rescue => e
        puts "[MMO Party UI] Error loading icon for #{pkmn.name}: #{e.message}"
        @icon_bitmaps[i] = nil
      end

      text_bitmap = @sprites["slot_#{i}_text"].bitmap
      text_bitmap.clear

      text_bitmap.font.size = 20

      name = pkmn.name
      text_bitmap.draw_text(0, 2, text_bitmap.width, 20, name, 0)

      level_text = "Lv.#{pkmn.level}"
      text_bitmap.draw_text(0, 22, text_bitmap.width, 20, level_text, 0)

      hp_percent = pkmn.hp.to_f / pkmn.totalhp
      hp_bar_width = 90
      hp_bar_height = 6

      text_bitmap.fill_rect(0, 44, hp_bar_width, hp_bar_height, Color.new(60, 60, 60))

      hp_color = Color.new(0, 200, 0)
      hp_color = Color.new(255, 200, 0) if hp_percent < 0.5
      hp_color = Color.new(255, 0, 0) if hp_percent < 0.25

      text_bitmap.fill_rect(0, 44, (hp_bar_width * hp_percent).to_i, hp_bar_height, hp_color)

      hp_text = "#{pkmn.hp}/#{pkmn.totalhp}"
      text_bitmap.font.size  =  16
      text_bitmap.draw_text(0, 52, text_bitmap.width, 18, hp_text, 0)

      text_bitmap.font.size = 20
    end

    ($player.party.length...6).each do |i|
      if @icon_bitmaps[i]
        @icon_bitmaps[i].dispose
        @icon_bitmaps[i] = nil
      end
      @sprites["slot_#{i}_icon"].bitmap = nil if @sprites["slot_#{i}_icon"]
      @sprites["slot_#{i}_icon"].src_rect = Rect.new(0, 0, 0, 0)
      @sprites["slot_#{i}_text"].bitmap.clear if @sprites["slot_#{i}_text"]
    end
  end

  def update
    return if @disposed

    update_icon_animations

    if defined?(MouseInput)
      mouse_x = MouseInput.mouse_x / 2.0
      mouse_y = MouseInput.mouse_y / 2.0
      hovered_slot = get_slot_at_position(mouse_x, mouse_y)

      6.times do |i|
        if @sprites["slot_#{i}_bg"]
          if hovered_slot == i && $player.party[i]

            @sprites["slot_#{i}_bg"].bitmap.fill_rect(0, 0, MMOResolution::UI_RIGHT_WIDTH, SLOT_HEIGHT, Color.new(80, 100, 140, 180))
          else

            @sprites["slot_#{i}_bg"].bitmap.fill_rect(0, 0, MMOResolution::UI_RIGHT_WIDTH, SLOT_HEIGHT, Color.new(40, 50, 70, 160))
          end
        end
      end
    end

    if @dragging_slot && defined?(MouseInput)

      unless MouseInput.left_down?

        mouse_x = MouseInput.mouse_x / 2.0
        mouse_y = MouseInput.mouse_y / 2.0

        target_slot = get_slot_at_position(mouse_x, mouse_y)

        if target_slot && target_slot != @dragging_slot

          swap_party_positions(@dragging_slot, target_slot)
        end

        @dragging_slot = nil
      else

        update_drag_visual
      end
    end
  end

  ICON_ANIMATION_DURATION = 0.25

  def update_icon_animations
    return unless $player && $player.party

    $player.party.each_with_index do |pkmn, i|
      break if i >= 6
      next unless pkmn
      next unless @icon_bitmaps[i]

      icon_sprite = @sprites["slot_#{i}_icon"]
      next unless icon_sprite

      if pkmn.fainted?
        @icon_current_frame[i] = 0
        icon_sprite.src_rect.x = 0
        next
      end

      duration = ICON_ANIMATION_DURATION
      hp_percent = pkmn.hp.to_f / pkmn.totalhp
      if hp_percent <= 0.25
        duration *= 4
      elsif hp_percent <= 0.5
        duration *= 2
      end

      frames_count  =  @icon_frames_count[i] || 2
      @icon_current_frame[i] = (frames_count * (System.uptime % duration) / duration).floor

      frame_width  =  icon_sprite.src_rect.height
      icon_sprite.src_rect.x = frame_width * @icon_current_frame[i]

      @icon_bitmaps[i].update
      icon_sprite.bitmap = @icon_bitmaps[i].bitmap
    end
  end

  def get_slot_at_position(x, y)
    6.times do |i|
      slot_sprite = @sprites["slot_#{i}_bg"]
      next unless slot_sprite

      if x >= slot_sprite.x && x < slot_sprite.x + slot_sprite.bitmap.width &&
         y >= slot_sprite.y && y < slot_sprite.y + slot_sprite.bitmap.height
        return i
      end
    end
    nil
  end

  def update_drag_visual
    return unless @dragging_slot && defined?(MouseInput)

    slot_bg = @sprites["slot_#{@dragging_slot}_bg"]
    slot_bg.opacity = 128 if slot_bg

  end

  def swap_party_positions(slot1, slot2)
    return unless $player && $player.party

    return unless $player.party[slot1] && $player.party[slot2]

    $player.party[slot1], $player.party[slot2] = $player.party[slot2], $player.party[slot1]

    EventHandlers.trigger(:on_party_changed)

    refresh_party

    @sprites["slot_#{slot1}_bg"].opacity = 255 if @sprites["slot_#{slot1}_bg"]
    @sprites["slot_#{slot2}_bg"].opacity = 255 if @sprites["slot_#{slot2}_bg"]

    pbSEPlay("GUI party switch")
    puts "[MMO Party UI] Swapped Pokemon #{slot1} <-> #{slot2}"
  end

  def handle_mouse_click(x, y, button)

    game_x = x / 2.0
    game_y = y / 2.0

    6.times do |i|
      slot_sprite = @sprites["slot_#{i}_bg"]
      next unless slot_sprite
      next unless slot_sprite.bitmap

      slot_x1 = slot_sprite.x
      slot_y1 = slot_sprite.y
      slot_x2 = slot_sprite.x + slot_sprite.bitmap.width
      slot_y2  =  slot_sprite.y + slot_sprite.bitmap.height

      if game_x >= slot_x1 && game_x < slot_x2 && game_y >= slot_y1 && game_y < slot_y2
        if button == 1
          @selected_slot = i
          @dragging_slot = i
          @drag_start_x = game_x
          @drag_start_y  =  game_y
          puts "[MMO Party UI] Started dragging slot #{i}"
          return true
        elsif button == 2
          show_pokemon_menu(i)
          return true
        end
      end
    end

    false
  end

  def show_pokemon_menu(slot_index)
    return unless $player && $player.party[slot_index]

    pkmn  =  $player.party[slot_index]
    commands = ["Summary", "Item", "Switch", "Cancel"]

    choice = pbMessage("#{pkmn.name}", commands, -1)

    case choice
    when 0

      scene = PokemonSummary_Scene.new
      screen = PokemonSummaryScreen.new(scene)
      screen.pbStartScreen($player.party, slot_index)
    when 1

      item = pkmn.item_id
      if item && item != :NONE

        if pbConfirmMessage("Take #{GameData::Item.get(item).name}?")
          $bag.add(item)
          pkmn.item = nil
          pbMessage("Took #{GameData::Item.get(item).name} from #{pkmn.name}.")
          refresh_party
        end
      else

        scene = PokemonBag_Scene.new
        screen = PokemonBagScreen.new(scene, $bag)
        item_chosen = screen.pbChooseItemScreen(proc { |item_id| GameData::Item.get(item_id).can_hold? })
        if item_chosen
          pkmn.item = item_chosen
          $bag.remove(item_chosen)
          pbMessage("Gave #{GameData::Item.get(item_chosen).name} to #{pkmn.name}.")
          refresh_party
        end
      end
    when 2

      @selected_slot = slot_index
      pbMessage('Click another Pokemon to switch positions')
    end
  end

  def visible=(value)
    @visible  =  value
    @sprites.each_value { |sprite| sprite.visible = value if sprite }
  end

  def dispose
    return if @disposed

    @icon_bitmaps.each do |bitmap|
      bitmap.dispose if bitmap
    end
    @icon_bitmaps.clear

    @sprites.each_value { |sprite| sprite.dispose if sprite && !sprite.disposed? }
    @sprites.clear
    @disposed  =  true
  end

  def disposed?
    @disposed
  end
end

class MMOKeyItemsBar
  ITEM_SLOT_SIZE  =  32
  ITEM_SLOT_PADDING = 3
  MAX_REGISTERED_ITEMS  =  12

  attr_reader :sprites
  attr_reader :registered_items

  def initialize(viewport = nil)
    @viewport  =  viewport
    @sprites = {}
    @disposed = false
    @visible = true
    @registered_items = []

    @dragging_slot  =  nil
    @drag_start_x = nil
    @drag_start_y = nil

    create_item_slots
    load_registered_items
  end

  def create_item_slots

    MAX_REGISTERED_ITEMS.times do |i|
      slot_x  =  10 + (i * (ITEM_SLOT_SIZE + ITEM_SLOT_PADDING))

      @sprites["item_slot_#{i}"] = Sprite.new(@viewport)
      @sprites["item_slot_#{i}"].bitmap = Bitmap.new(ITEM_SLOT_SIZE, ITEM_SLOT_SIZE)
      @sprites["item_slot_#{i}"].bitmap.fill_rect(0, 0, ITEM_SLOT_SIZE, ITEM_SLOT_SIZE, Color.new(60, 60, 60, 200))
      @sprites["item_slot_#{i}"].x = slot_x
      @sprites["item_slot_#{i}"].y = 4
      @sprites["item_slot_#{i}"].z = 95001

      @sprites["item_icon_#{i}"] = Sprite.new(@viewport)
      @sprites["item_icon_#{i}"].x = slot_x + 4
      @sprites["item_icon_#{i}"].y = 8
      @sprites["item_icon_#{i}"].z = 95002
    end

    puts "[MMO Key Items] Created #{MAX_REGISTERED_ITEMS} item slots"
  end

  def load_registered_items

    if $player && $player.respond_to?(:registered_key_items)
      @registered_items = $player.registered_key_items.clone
    else

      if $player
        $player.registered_key_items = [] unless $player.respond_to?(:registered_key_items)
      end
      @registered_items = []
    end

    if @registered_items.empty? && $bag
      auto_register_common_items
    end

    refresh_items
    puts "[MMO Key Items] Loaded #{@registered_items.length} registered items"
  end

  def auto_register_common_items

    common_items = [
      :BICYCLE,
      :ITEMFINDER,
      :OLDROD,
      :GOODROD,
      :SUPERROD,
      :DOWSINGMACHINE,
      :COINCASE,
      :POKERADAR
    ]

    common_items.each do |item_symbol|
      break if @registered_items.length >= MAX_REGISTERED_ITEMS

      if GameData::Item.exists?(item_symbol) && $bag.has?(item_symbol)
        item_id = GameData::Item.get(item_symbol).id
        @registered_items << item_id
      end
    end

    save_registered_items
  end

  def save_registered_items

    if $player
      $player.registered_key_items = @registered_items.clone
    end

    if defined?($multiplayer_client) && $multiplayer_client && $multiplayer_client.connected?
      sync_registered_items_to_server
    end
  end

  def sync_registered_items_to_server

    $multiplayer_client.send_message(MultiplayerProtocol.create_message("registered_items_update", {
      items: @registered_items
    }))
  end

  def register_item(item_id)
    return if @registered_items.include?(item_id)

    if @registered_items.length >= MAX_REGISTERED_ITEMS
      pbMultiplayerNotify("Item bar is full!", 2.0) if defined?(pbMultiplayerNotify)
      return
    end

    unless $bag && $bag.has?(item_id)
      pbMultiplayerNotify("You don't have this item!", 2.0) if defined?(pbMultiplayerNotify)
      return
    end

    @registered_items << item_id
    save_registered_items
    refresh_items
    pbMultiplayerNotify("Registered #{GameData::Item.get(item_id).name}", 2.0) if defined?(pbMultiplayerNotify)
  end

  def unregister_item(item_id)
    @registered_items.delete(item_id)
    save_registered_items
    refresh_items
    pbMultiplayerNotify("Unregistered #{GameData::Item.get(item_id).name}", 2.0) if defined?(pbMultiplayerNotify)
  end

  def refresh_items
    puts "[MMO Items] Refreshing #{@registered_items.length} items: #{@registered_items.inspect}"
    @registered_items.each_with_index do |item_id, i|
      puts "[MMO Items] Loading icon for slot #{i}: #{item_id}"
      item_icon = pbLoadItemIconBitmap(item_id)
      if item_icon
        @sprites["item_icon_#{i}"].bitmap = item_icon
        @sprites["item_icon_#{i}"].visible = true
        scale = (ITEM_SLOT_SIZE - 8).to_f / [item_icon.width, item_icon.height].max
        @sprites["item_icon_#{i}"].zoom_x = scale
        @sprites["item_icon_#{i}"].zoom_y = scale
        puts "[MMO Items] Icon loaded for slot #{i}"
      else
        puts "[MMO Items] Failed to load icon for #{item_id}"
      end
    end

    (@registered_items.length...MAX_REGISTERED_ITEMS).each do |i|
      @sprites["item_icon_#{i}"].bitmap = nil if @sprites["item_icon_#{i}"]
    end
  end

  def handle_mouse_click(x, y, button)

    game_x = x / 2.0
    game_y = y / 2.0

    MAX_REGISTERED_ITEMS.times do |i|
      slot_sprite  =  @sprites["item_slot_#{i}"]
      next unless slot_sprite

      if game_x >= slot_sprite.x && game_x < slot_sprite.x + ITEM_SLOT_SIZE &&
         game_y >= slot_sprite.y && game_y < slot_sprite.y + ITEM_SLOT_SIZE

        if button == 0
          if @registered_items[i]

            @dragging_slot = i
            @drag_start_x = game_x
            @drag_start_y = game_y
            return true
          end
        elsif button == 1
          if @registered_items[i]
            unregister_item(@registered_items[i])
            return true
          end
        end
      end
    end

    false
  end

  def handle_mouse_release(x, y, button)
    return false unless @dragging_slot

    game_x  =  x / 2.0
    game_y = y / 2.0

    drag_distance = Math.sqrt((@drag_start_x - game_x)**2 + (@drag_start_y - game_y)**2)

    if drag_distance < 5

      use_item(@registered_items[@dragging_slot])
    else

      MAX_REGISTERED_ITEMS.times do |i|
        slot_sprite = @sprites["item_slot_#{i}"]
        next unless slot_sprite

        if game_x >= slot_sprite.x && game_x < slot_sprite.x + ITEM_SLOT_SIZE &&
           game_y >= slot_sprite.y && game_y < slot_sprite.y + ITEM_SLOT_SIZE

          swap_items(@dragging_slot, i)
          break
        end
      end
    end

    @dragging_slot = nil
    @drag_start_x = nil
    @drag_start_y = nil

    true
  end

  def swap_items(from_index, to_index)
    return if from_index == to_index

    @registered_items[from_index], @registered_items[to_index] =
      @registered_items[to_index], @registered_items[from_index]

    save_registered_items
    refresh_items
  end

  def use_item(item_id)
    puts "[MMO Items] use_item called for #{item_id}"

    unless $bag && $bag.has?(item_id)
      puts "[MMO Items] Item not in bag"
      pbMultiplayerNotify("You don't have this item!", 2.0) if defined?(pbMultiplayerNotify)
      return
    end

    itm = GameData::Item.get(item_id)
    puts "[MMO Items] Showing menu for #{itm.name}"

    cmdRead = -1
    cmdUse = -1
    cmdRegister = -1
    cmdGive = -1
    cmdToss = -1
    cmdMMOUnregister = -1
    cmdDebug = -1
    commands = []

    commands[cmdRead = commands.length] = _INTL("Read") if itm.is_mail?
    if ItemHandlers.hasOutHandler(item_id) || (itm.is_machine? && $player.party.length > 0)
      if ItemHandlers.hasUseText(item_id)
        commands[cmdUse = commands.length] = ItemHandlers.getUseText(item_id)
      else
        commands[cmdUse = commands.length] = _INTL("Use")
      end
    end
    commands[cmdGive = commands.length] = _INTL("Give") if $player.pokemon_party.length > 0 && itm.can_hold?
    commands[cmdToss = commands.length] = _INTL("Toss") if !itm.is_important? || $DEBUG

    if $bag.registered?(item_id)
      commands[cmdRegister = commands.length] = _INTL("Deselect")
    elsif defined?(pbCanRegisterItem?) && pbCanRegisterItem?(item_id)
      commands[cmdRegister = commands.length] = _INTL("Register")
    end

    if @registered_items.include?(item_id)
      commands[cmdMMOUnregister = commands.length] = _INTL("MMO Unregister")
    end

    commands[cmdDebug = commands.length] = _INTL("Debug") if $DEBUG
    commands[commands.length] = _INTL("Cancel")

    msgwindow = pbCreateMessageWindow
    command = pbMessage(_INTL("{1} is selected.", itm.name), commands.dup, -1, msgwindow)
    pbDisposeMessageWindow(msgwindow)

    puts "[MMO Items] Selected command: #{command}"

    if cmdRead >= 0 && command == cmdRead
      pbFadeOutIn do
        pbDisplayMail(Mail.new(item_id, "", ""))
      end
    elsif cmdUse >= 0 && command == cmdUse
      ret = ItemHandlers.triggerUseFromBag(item_id)
      refresh_items if ret
    elsif cmdGive >= 0 && command == cmdGive
      if $player.pokemon_count == 0
        pbMessage(_INTL("There is no Pokémon."))
      elsif itm.is_important?
        pbMessage(_INTL("The {1} can't be held.", itm.portion_name))
      else
        pbFadeOutIn do
          sscene = PokemonParty_Scene.new
          sscreen = PokemonPartyScreen.new(sscene, $player.party)
          sscreen.pbPokemonGiveScreen(item_id)
          refresh_items
        end
      end
    elsif cmdToss >= 0 && command == cmdToss
      qty = $bag.quantity(item_id)
      if qty > 1
        helptext = _INTL("Toss out how many {1}?", itm.portion_name_plural)
        params = ChooseNumberParams.new
        params.setRange(1, qty)
        params.setDefaultValue(1)
        qty = pbMessageChooseNumber(helptext, params)
      end
      if qty > 0
        itemname_toss = (qty > 1) ? itm.portion_name_plural : itm.portion_name
        if pbConfirm(_INTL("Is it OK to throw away {1} {2}?", qty, itemname_toss))
          pbMessage(_INTL("Threw away {1} {2}.", qty, itemname_toss))
          qty.times { $bag.remove(item_id) }
          refresh_items
        end
      end
    elsif cmdRegister >= 0 && command == cmdRegister
      if $bag.registered?(item_id)
        $bag.unregister(item_id)
        pbMultiplayerNotify("Deregistered #{itm.name}", 2.0) if defined?(pbMultiplayerNotify)
      else
        $bag.register(item_id)
        pbMultiplayerNotify("Registered #{itm.name}", 2.0) if defined?(pbMultiplayerNotify)
      end
    elsif cmdMMOUnregister >= 0 && command == cmdMMOUnregister
      unregister_item(item_id)
    elsif cmdDebug >= 0 && command == cmdDebug
      qty = $bag.quantity(item_id)
      itemplural = itm.name_plural
      params = ChooseNumberParams.new
      params.setRange(0, Settings::BAG_MAX_PER_SLOT)
      params.setDefaultValue(qty)
      newqty = pbMessageChooseNumber(
        _INTL("Choose new quantity of {1} (max. {2}).", itemplural, Settings::BAG_MAX_PER_SLOT), params
      )
      if newqty > qty
        $bag.add(item_id, newqty - qty)
      elsif newqty < qty
        $bag.remove(item_id, qty - newqty)
      end
      refresh_items
    end
  end

  def visible=(value)
    @visible = value
    @sprites.each_value { |sprite| sprite.visible  =  value if sprite }
  end

  def update
    return if @disposed

    if defined?(MouseInput)
      mouse_x = MouseInput.mouse_x / 2.0
      mouse_y  =  MouseInput.mouse_y / 2.0

      MAX_REGISTERED_ITEMS.times do |i|
        slot_sprite  =  @sprites["item_slot_#{i}"]
        next unless slot_sprite

        is_hovered = mouse_x >= slot_sprite.x && mouse_x < slot_sprite.x + ITEM_SLOT_SIZE &&
                     mouse_y >= slot_sprite.y && mouse_y < slot_sprite.y + ITEM_SLOT_SIZE

        if is_hovered && @registered_items[i]

          slot_sprite.bitmap.fill_rect(0, 0, ITEM_SLOT_SIZE, ITEM_SLOT_SIZE, Color.new(100, 140, 200, 240))

          slot_sprite.bitmap.fill_rect(0, 0, ITEM_SLOT_SIZE, 2, Color.new(150, 190, 255))
          slot_sprite.bitmap.fill_rect(0, ITEM_SLOT_SIZE - 2, ITEM_SLOT_SIZE, 2, Color.new(150, 190, 255))
          slot_sprite.bitmap.fill_rect(0, 0, 2, ITEM_SLOT_SIZE, Color.new(150, 190, 255))
          slot_sprite.bitmap.fill_rect(ITEM_SLOT_SIZE - 2, 0, 2, ITEM_SLOT_SIZE, Color.new(150, 190, 255))
        else

          slot_sprite.bitmap.fill_rect(0, 0, ITEM_SLOT_SIZE, ITEM_SLOT_SIZE, Color.new(60, 60, 60, 200))
        end
      end
    end
  end

  def dispose
    return if @disposed
    @sprites.each_value { |sprite| sprite.dispose if sprite && !sprite.disposed? }
    @sprites.clear
    @disposed = true
  end

  def disposed?
    @disposed
  end
end

def pbLoadItemIconBitmap(item_id)

  if defined?(GameData::Item)
    item_data = GameData::Item.get(item_id)
    filename = sprintf("Graphics/Items/%s", item_data.id.to_s)

    if pbResolveBitmap(filename)
      return Bitmap.new(filename + '.png')
    else
      fallback = "Graphics/Items/000"
      if pbResolveBitmap(fallback)
        return Bitmap.new(fallback + '.png')
      end
    end
  end

  nil
end

puts "[MMO UI Overlay] UI overlay system loaded"
