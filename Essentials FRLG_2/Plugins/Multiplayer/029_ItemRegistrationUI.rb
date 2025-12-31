class MMOItemRegistrationUI
  ITEMS_PER_ROW = 6
  ITEMS_PER_PAGE = 18
  ITEM_SIZE = 40
  ITEM_PADDING = 4

  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @disposed = false
    @selected_index = 0
    @scroll_offset = 0
    @available_items = []
    @registered_items = []
    @hovered_index = -1

    load_items
    create_ui
  end

  def load_items
    @registered_items = []
    if $player && $player.respond_to?(:registered_key_items)
      @registered_items = $player.registered_key_items || []
    end

    @available_items = []
    return unless $bag

    hm_items = [:HM01, :HM02, :HM03, :HM04, :HM05, :HM06]
    hm_items.each do |hm|
      next unless GameData::Item.exists?(hm)
      next unless $bag.has?(hm)
      next if @registered_items.include?(hm)
      @available_items << hm
    end

    $bag.pockets.each_with_index do |pocket, pocket_idx|
      next unless pocket
      pocket.each do |item_slot|
        item_id = item_slot[0]
        next if @registered_items.include?(item_id)
        next if @available_items.include?(item_id)
        item_data = GameData::Item.get(item_id) rescue nil
        next unless item_data
        @available_items << item_id
      end
    end
  end

  def create_ui
    @sprites[:background] = Sprite.new(@viewport)
    @sprites[:background].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites[:background].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))
    @sprites[:background].z = 0

    panel_width = 300
    panel_height = 340
    panel_x = (Graphics.width - panel_width) / 2
    panel_y = (Graphics.height - panel_height) / 2

    @sprites[:panel] = Sprite.new(@viewport)
    @sprites[:panel].bitmap = Bitmap.new(panel_width, panel_height)
    @sprites[:panel].bitmap.fill_rect(0, 0, panel_width, panel_height, Color.new(40, 40, 60, 240))
    @sprites[:panel].bitmap.fill_rect(2, 2, panel_width - 4, panel_height - 4, Color.new(60, 60, 80, 240))
    @sprites[:panel].x = panel_x
    @sprites[:panel].y = panel_y
    @sprites[:panel].z = 1

    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(panel_width, 30)
    @sprites[:title].bitmap.font.size = 22
    @sprites[:title].bitmap.font.color = Color.new(255, 255, 255)
    @sprites[:title].bitmap.draw_text(0, 0, panel_width, 30, "Register Item", 1)
    @sprites[:title].x = panel_x
    @sprites[:title].y = panel_y + 5
    @sprites[:title].z = 2

    @sprites[:instructions] = Sprite.new(@viewport)
    @sprites[:instructions].bitmap = Bitmap.new(panel_width, 20)
    @sprites[:instructions].bitmap.font.size = 14
    @sprites[:instructions].bitmap.font.color = Color.new(180, 180, 180)
    @sprites[:instructions].bitmap.draw_text(0, 0, panel_width, 20, "Click or A: Register  B/RClick: Cancel", 1)
    @sprites[:instructions].x = panel_x
    @sprites[:instructions].y = panel_y + panel_height - 25
    @sprites[:instructions].z = 2

    @panel_x = panel_x
    @panel_y = panel_y
    @panel_width = panel_width
    @panel_height = panel_height

    @items_start_x = panel_x + 20
    @items_start_y = panel_y + 45

    create_item_grid
    update_selection
  end

  def create_item_grid
    ITEMS_PER_PAGE.times do |i|
      row = i / ITEMS_PER_ROW
      col = i % ITEMS_PER_ROW

      slot_x = @items_start_x + (col * (ITEM_SIZE + ITEM_PADDING))
      slot_y = @items_start_y + (row * (ITEM_SIZE + ITEM_PADDING))

      @sprites["slot_#{i}"] = Sprite.new(@viewport)
      @sprites["slot_#{i}"].bitmap = Bitmap.new(ITEM_SIZE, ITEM_SIZE)
      @sprites["slot_#{i}"].x = slot_x
      @sprites["slot_#{i}"].y = slot_y
      @sprites["slot_#{i}"].z = 2

      @sprites["icon_#{i}"] = Sprite.new(@viewport)
      @sprites["icon_#{i}"].x = slot_x + 4
      @sprites["icon_#{i}"].y = slot_y + 4
      @sprites["icon_#{i}"].z = 3
    end

    @sprites[:item_name] = Sprite.new(@viewport)
    @sprites[:item_name].bitmap = Bitmap.new(@panel_width - 20, 24)
    @sprites[:item_name].x = @panel_x + 10
    @sprites[:item_name].y = @panel_y + @panel_height - 55
    @sprites[:item_name].z = 2

    refresh_grid
  end

  def refresh_grid
    ITEMS_PER_PAGE.times do |i|
      item_index = @scroll_offset + i
      slot = @sprites["slot_#{i}"]
      icon = @sprites["icon_#{i}"]

      slot.bitmap.clear
      slot.bitmap.fill_rect(0, 0, ITEM_SIZE, ITEM_SIZE, Color.new(50, 50, 70, 200))

      if item_index < @available_items.length
        item_id = @available_items[item_index]
        item_bitmap = pbLoadItemIconBitmap(item_id) rescue nil
        if item_bitmap
          icon.bitmap = item_bitmap
          scale = (ITEM_SIZE - 8).to_f / [item_bitmap.width, item_bitmap.height].max
          icon.zoom_x = scale
          icon.zoom_y = scale
          icon.visible = true
        else
          icon.visible = false
        end
      else
        icon.bitmap = nil
        icon.visible = false
      end
    end
  end

  def get_slot_at_mouse
    mouse_x = Input.mouse_x rescue 0
    mouse_y = Input.mouse_y rescue 0

    ITEMS_PER_PAGE.times do |i|
      slot = @sprites["slot_#{i}"]
      next unless slot

      if mouse_x >= slot.x && mouse_x < slot.x + ITEM_SIZE &&
         mouse_y >= slot.y && mouse_y < slot.y + ITEM_SIZE
        return i
      end
    end
    -1
  end

  def update_selection
    mouse_hovered = get_slot_at_mouse

    ITEMS_PER_PAGE.times do |i|
      slot = @sprites["slot_#{i}"]
      next unless slot

      slot.bitmap.clear
      item_index = @scroll_offset + i

      if i == @selected_index
        slot.bitmap.fill_rect(0, 0, ITEM_SIZE, ITEM_SIZE, Color.new(100, 140, 200, 240))
        slot.bitmap.fill_rect(2, 2, ITEM_SIZE - 4, ITEM_SIZE - 4, Color.new(60, 80, 120, 240))
      elsif i == mouse_hovered && item_index < @available_items.length
        slot.bitmap.fill_rect(0, 0, ITEM_SIZE, ITEM_SIZE, Color.new(80, 100, 150, 220))
        slot.bitmap.fill_rect(1, 1, ITEM_SIZE - 2, ITEM_SIZE - 2, Color.new(55, 65, 95, 220))
      else
        slot.bitmap.fill_rect(0, 0, ITEM_SIZE, ITEM_SIZE, Color.new(50, 50, 70, 200))
      end
    end

    display_index = mouse_hovered >= 0 ? mouse_hovered : @selected_index
    @sprites[:item_name].bitmap.clear
    item_index = @scroll_offset + display_index
    if item_index < @available_items.length
      item_id = @available_items[item_index]
      item_data = GameData::Item.get(item_id) rescue nil
      if item_data
        @sprites[:item_name].bitmap.font.size = 18
        @sprites[:item_name].bitmap.font.color = Color.new(255, 255, 255)
        @sprites[:item_name].bitmap.draw_text(0, 0, @panel_width - 20, 24, item_data.name, 1)
      end
    end
  end

  def update
    return if @disposed

    update_selection

    if Input.trigger?(Input::BACK)
      pbPlayCloseMenuSE
      return :cancel
    end

    left_click = Input.trigger?(Input::MOUSELEFT) rescue false
    right_click = Input.trigger?(Input::MOUSERIGHT) rescue false

    if right_click
      pbPlayCloseMenuSE
      return :cancel
    end

    if left_click
      clicked_slot = get_slot_at_mouse
      if clicked_slot >= 0
        item_index = @scroll_offset + clicked_slot
        if item_index < @available_items.length
          @selected_index = clicked_slot
          return try_register_selected
        end
      end
    end

    if Input.trigger?(Input::USE)
      return try_register_selected
    end

    moved = false
    if Input.repeat?(Input::LEFT)
      @selected_index -= 1 if @selected_index % ITEMS_PER_ROW > 0
      moved = true
    elsif Input.repeat?(Input::RIGHT)
      @selected_index += 1 if @selected_index % ITEMS_PER_ROW < ITEMS_PER_ROW - 1
      moved = true
    elsif Input.repeat?(Input::UP)
      if @selected_index >= ITEMS_PER_ROW
        @selected_index -= ITEMS_PER_ROW
        moved = true
      elsif @scroll_offset > 0
        @scroll_offset -= ITEMS_PER_ROW
        refresh_grid
        moved = true
      end
    elsif Input.repeat?(Input::DOWN)
      if @selected_index < ITEMS_PER_PAGE - ITEMS_PER_ROW
        @selected_index += ITEMS_PER_ROW
        moved = true
      elsif @scroll_offset + ITEMS_PER_PAGE < @available_items.length
        @scroll_offset += ITEMS_PER_ROW
        refresh_grid
        moved = true
      end
    end

    if moved
      pbPlayCursorSE
      update_selection
    end

    nil
  end

  def try_register_selected
    item_index = @scroll_offset + @selected_index
    return nil if item_index >= @available_items.length

    item_id = @available_items[item_index]
    if $mmo_key_items_bar
      $mmo_key_items_bar.register_item(item_id)
      pbPlayDecisionSE
      return :registered
    end
    nil
  end

  def dispose
    return if @disposed
    @sprites.each_value { |s| s.dispose if s && !s.disposed? }
    @sprites.clear
    @viewport.dispose
    @disposed = true
  end

  def disposed?
    @disposed
  end
end

def pbOpenItemRegistrationUI
  ui = MMOItemRegistrationUI.new
  loop do
    Graphics.update
    Input.update
    result = ui.update
    break if result == :cancel || result == :registered
  end
  ui.dispose
end

puts "[MMO Item Registration] Item registration UI loaded"
