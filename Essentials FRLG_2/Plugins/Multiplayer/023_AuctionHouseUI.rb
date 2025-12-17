class AuctionHouseUI
  TABS = [:browse, :my_listings, :sell]
  FILTER_TYPES  =  ['ALL', 'ITEM', 'POKEMON']

  def initialize
    @active = false
    @viewport = nil
    @sprites = {}
    @current_tab = :browse
    @listings = []
    @selection = 0
    @scroll_offset = 0
    @visible_count = 4
    @card_height = 90
    @filter_type = 0
    @search_query  =  ""
    @keys_pressed = {}
  end

  def activate
    return unless pbMultiplayerConnected?

    @active = true
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999

    create_sprites

    request_listings
    update_content
  end

  def deactivate
    @active  =  false
    dispose_sprites
    @viewport.dispose if @viewport
    @viewport = nil
  end

  def create_sprites

    @sprites[:bg] = Sprite.new(@viewport)
    @sprites[:bg].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites[:bg].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(10, 10, 20, 250))

    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(Graphics.width, 60)
    draw_gradient(@sprites[:title].bitmap, 0, 0, Graphics.width, 60, Color.new(30, 60, 100), Color.new(15, 30, 60))

    @sprites[:title].bitmap.fill_rect(0, 58, Graphics.width, 2, Color.new(100, 180, 255))

    pbSetSystemFont(@sprites[:title].bitmap)

    @sprites[:title].bitmap.font.size = 36
    @sprites[:title].bitmap.font.bold = true
    @sprites[:title].bitmap.font.color = Color.new(0, 0, 0, 150)
    @sprites[:title].bitmap.draw_text(22, 12, Graphics.width - 44, 40, "[*] Global Auction House", 1)

    @sprites[:title].bitmap.font.color = Color.new(255, 255, 255)
    @sprites[:title].bitmap.draw_text(20, 10, Graphics.width - 40, 40, "[*] Global Auction House", 1)

    @sprites[:money] = Sprite.new(@viewport)
    @sprites[:money].bitmap = Bitmap.new(200, 30)
    @sprites[:money].x = Graphics.width - 210
    @sprites[:money].y = 70
    update_money_display

    @sprites[:tabs] = Sprite.new(@viewport)
    @sprites[:tabs].bitmap = Bitmap.new(Graphics.width, 50)
    @sprites[:tabs].y = 60
    update_tabs

    @sprites[:content] = Sprite.new(@viewport)
    @sprites[:content].bitmap  =  Bitmap.new(Graphics.width - 40, Graphics.height - 200)
    @sprites[:content].x = 20
    @sprites[:content].y  =  120

    @sprites[:instructions] = Sprite.new(@viewport)
    @sprites[:instructions].bitmap  =  Bitmap.new(Graphics.width, 40)
    @sprites[:instructions].y  =  Graphics.height - 40
    draw_instructions
  end

  def draw_gradient(bitmap, x, y, w, h, color1, color2)
    for i in 0...h
      r = color1.red + (color2.red - color1.red) * i / h
      g = color1.green + (color2.green - color1.green) * i / h
      b = color1.blue + (color2.blue - color1.blue) * i / h
      a  =  color1.alpha + (color2.alpha - color1.alpha) * i / h
      bitmap.fill_rect(x, y + i, w, 1, Color.new(r, g, b, a))
    end
  end

  def update_money_display
    return unless @sprites[:money]
    @sprites[:money].bitmap.clear
    pbSetSystemFont(@sprites[:money].bitmap)
    @sprites[:money].bitmap.font.size = 20
    @sprites[:money].bitmap.font.bold = true
    @sprites[:money].bitmap.font.color  =  Color.new(255, 215, 0)

    money = $player ? $player.money : 0
    @sprites[:money].bitmap.draw_text(0, 0, 200, 30, "Money: $#{money}", 2)
  end

  def update_tabs
    return unless @sprites[:tabs]
    @sprites[:tabs].bitmap.clear

    tab_width = Graphics.width / TABS.length
    tab_names = ["[?] Browse", "[#] My Listings", "[$] Sell"]

    TABS.each_with_index do |tab, i|
      x = i * tab_width
      is_selected = (tab == @current_tab)

      if is_selected
        @sprites[:tabs].bitmap.fill_rect(x + 2, 2, tab_width - 4, 48, Color.new(0, 0, 0, 80))
      end

      if is_selected
        @sprites[:tabs].bitmap.fill_rect(x, 0, tab_width, 50, Color.new(100, 180, 255))
        draw_gradient(@sprites[:tabs].bitmap, x + 2, 2, tab_width - 4, 46, Color.new(50, 90, 130), Color.new(35, 65, 100))

        @sprites[:tabs].bitmap.fill_rect(x + 10, 46, tab_width - 20, 4, Color.new(255, 215, 0))
      else
        draw_gradient(@sprites[:tabs].bitmap, x, 0, tab_width, 50, Color.new(30, 30, 50), Color.new(20, 20, 40))
      end

      @sprites[:tabs].bitmap.fill_rect(x, 0, 2, 50, Color.new(80, 120, 160)) if i > 0

      pbSetSystemFont(@sprites[:tabs].bitmap)
      @sprites[:tabs].bitmap.font.size = 22
      @sprites[:tabs].bitmap.font.bold = is_selected
      @sprites[:tabs].bitmap.font.color  =  is_selected ? Color.new(255, 255, 255) : Color.new(180, 180, 180)

      @sprites[:tabs].bitmap.draw_text(x, 10, tab_width, 30, tab_names[i], 1)
    end
  end

  def draw_instructions
    return unless @sprites[:instructions]
    @sprites[:instructions].bitmap.clear

    draw_gradient(@sprites[:instructions].bitmap, 0, 0, Graphics.width, 40, Color.new(25, 25, 40), Color.new(15, 15, 25))

    @sprites[:instructions].bitmap.fill_rect(0, 0, Graphics.width, 2, Color.new(80, 120, 160))

    pbSetSystemFont(@sprites[:instructions].bitmap)
    @sprites[:instructions].bitmap.font.size = 16
    @sprites[:instructions].bitmap.font.color = Color.new(220, 220, 240)

    text = "UP/DN Navigate  •  TAB Switch Tab  •  ENTER Select  •  F Search  •  ESC Close"
    @sprites[:instructions].bitmap.draw_text(0, 10, Graphics.width, 20, text, 1)
  end

  def request_listings
    case @current_tab
    when :browse
      $auction_browse_ready = false
      $auction_browse_results = []
      pbMultiplayerClient.auction_browse(FILTER_TYPES[@filter_type], @search_query, 0, 50)
    when :my_listings
      $auction_my_listings_ready = false
      $auction_my_listings  =  []
      pbMultiplayerClient.auction_my_listings
    when :sell
      @listings = []
    end
  end

  def check_listings_updates
    case @current_tab
    when :browse
      if $auction_browse_ready
        @listings = $auction_browse_results || []
        $auction_browse_ready = false
        @selection = 0
        @scroll_offset  =  0
        update_content
      end
    when :my_listings
      if $auction_my_listings_ready
        @listings = $auction_my_listings || []
        $auction_my_listings_ready = false
        @selection  =  0
        @scroll_offset = 0
        update_content
      end
    end
  end

  def refresh_listings
    request_listings
  end

  def update_content
    return unless @sprites[:content]
    @sprites[:content].bitmap.clear

    case @current_tab
    when :browse, :my_listings
      draw_listings
    when :sell
      draw_sell_menu
    end
  end

  def draw_listings
    return unless @sprites[:content]

    if @current_tab == :browse
      draw_filter_bar
    end

    y_offset = @current_tab == :browse ? 50 : 10
    visible_listings = @listings[@scroll_offset, @visible_count] || []

    if visible_listings.empty?
      pbSetSystemFont(@sprites[:content].bitmap)
      @sprites[:content].bitmap.font.size = 24
      @sprites[:content].bitmap.font.color  =  Color.new(150, 150, 150)
      @sprites[:content].bitmap.draw_text(0, 200, @sprites[:content].bitmap.width, 30, 'No listings found', 1)
      return
    end

    visible_listings.each_with_index do |listing, i|
      real_index = @scroll_offset + i
      is_selected = (real_index == @selection)

      draw_listing_card(listing, y_offset, is_selected)
      y_offset += @card_height + 5
    end

    pbSetSystemFont(@sprites[:content].bitmap)
    if @scroll_offset > 0

      indicator_y = 55
      @sprites[:content].bitmap.fill_rect(0, indicator_y, @sprites[:content].bitmap.width, 20, Color.new(100, 180, 255, 150))
      @sprites[:content].bitmap.font.size = 16
      @sprites[:content].bitmap.font.bold = true
      @sprites[:content].bitmap.font.color = Color.new(255, 255, 255)
      @sprites[:content].bitmap.draw_text(0, indicator_y, @sprites[:content].bitmap.width, 20, "^ More above ^", 1)
    end
    if @scroll_offset + @visible_count < @listings.length

      indicator_y = @sprites[:content].bitmap.height - 20
      @sprites[:content].bitmap.fill_rect(0, indicator_y, @sprites[:content].bitmap.width, 20, Color.new(100, 180, 255, 150))
      @sprites[:content].bitmap.font.size  =  16
      @sprites[:content].bitmap.font.bold = true
      @sprites[:content].bitmap.font.color  =  Color.new(255, 255, 255)
      @sprites[:content].bitmap.draw_text(0, indicator_y, @sprites[:content].bitmap.width, 20, "v More below v", 1)
    end
  end

  def draw_filter_bar
    w = @sprites[:content].bitmap.width

    draw_gradient(@sprites[:content].bitmap, 0, 0, w, 50, Color.new(40, 40, 60), Color.new(30, 30, 45))

    @sprites[:content].bitmap.fill_rect(0, 49, w, 1, Color.new(80, 120, 160))

    pbSetSystemFont(@sprites[:content].bitmap)

    filter_icon = case FILTER_TYPES[@filter_type]
    when 'ALL' then '[*]'
    when 'ITEM' then '[I]'
    when 'POKEMON' then '[P]'
    else '[*]'
    end

    @sprites[:content].bitmap.fill_rect(10, 10, 180, 30, Color.new(0, 0, 0, 100))
    @sprites[:content].bitmap.fill_rect(12, 12, 176, 26, Color.new(50, 80, 120))

    @sprites[:content].bitmap.font.size = 18
    @sprites[:content].bitmap.font.bold = true
    @sprites[:content].bitmap.font.color = Color.new(255, 255, 255)
    filter_text = "#{filter_icon} #{FILTER_TYPES[@filter_type]}"
    @sprites[:content].bitmap.draw_text(15, 13, 170, 24, filter_text, 1)

    search_x = 200
    search_w  =  w - 210
    @sprites[:content].bitmap.fill_rect(search_x, 10, search_w, 30, Color.new(0, 0, 0, 100))
    @sprites[:content].bitmap.fill_rect(search_x + 2, 12, search_w - 4, 26, Color.new(30, 30, 40))

    search_text = @search_query.empty? ? "[?] Click to search (F to filter)" : "[?] #{@search_query}"
    @sprites[:content].bitmap.font.size = 16
    @sprites[:content].bitmap.font.bold = false
    @sprites[:content].bitmap.font.color = @search_query.empty? ? Color.new(150, 150, 170) : Color.new(255, 255, 255)
    @sprites[:content].bitmap.draw_text(search_x + 5, 13, search_w - 10, 24, search_text)

    @search_bar_bounds = {x: search_x, y: 10, width: search_w, height: 30}
  end

  def draw_listing_card(listing, y, selected)
    w  =  @sprites[:content].bitmap.width - 20
    h  =  @card_height

    @sprites[:content].bitmap.fill_rect(13, y + 3, w, h, Color.new(0, 0, 0, 80))

    if selected

      @sprites[:content].bitmap.fill_rect(10, y, w, h, Color.new(100, 180, 255))
      draw_gradient(@sprites[:content].bitmap, 12, y + 2, w - 4, h - 4, Color.new(50, 90, 130), Color.new(35, 65, 100))
    else

      @sprites[:content].bitmap.fill_rect(10, y, w, h, Color.new(60, 60, 80))
      draw_gradient(@sprites[:content].bitmap, 12, y + 2, w - 4, h - 4, Color.new(35, 35, 50), Color.new(25, 25, 40))
    end

    listing_type = (listing[:listing_type] || listing['listing_type']).to_s

    icon_bg_color = listing_type == 'ITEM' ? Color.new(60, 120, 60) : Color.new(120, 60, 120)
    @sprites[:content].bitmap.fill_rect(20, y + 10, 70, 70, Color.new(0, 0, 0, 100))
    @sprites[:content].bitmap.fill_rect(22, y + 12, 66, 66, icon_bg_color)

    if listing_type == 'ITEM'
      item_id = listing[:item_id] || listing['item_id']
      item_quantity = listing[:item_quantity] || listing['item_quantity'] || 1
      item_data_temp = GameData::Item.try_get(item_id.to_sym) rescue nil
      item_name = item_data_temp ? item_data_temp.name : item_id.to_s

      begin
        item_data  =  GameData::Item.try_get(item_id.to_sym)
        if item_data

          if item_data.respond_to?(:icon_filename)
            icon_path = item_data.icon_filename
          else
            icon_path = sprintf("Graphics/Items/%s", item_data.id.to_s)
          end

          if pbResolveBitmap(icon_path)
            icon_bitmap = AnimatedBitmap.new(icon_path).bitmap rescue nil
            if icon_bitmap

              src_rect = Rect.new(0, 0, icon_bitmap.width, icon_bitmap.height)
              dest_rect = Rect.new(30, y + 20, 50, 50)
              @sprites[:content].bitmap.stretch_blt(dest_rect, icon_bitmap, src_rect)
            end
          end
        end
      rescue => e

      end

      name_text = "#{item_name}"
      quantity_text = "x#{item_quantity}"
    else

      pkmn_data = listing[:pokemon_data] || listing['pokemon_data']
      if pkmn_data && !pkmn_data.empty?
        species = pkmn_data[:species] || pkmn_data['species']
        species_data_temp = GameData::Species.try_get(species) rescue nil
        species_name = species_data_temp ? species_data_temp.name : species.to_s
        level = pkmn_data[:level] || pkmn_data['level'] || "?"
        is_shiny = pkmn_data[:shiny] || pkmn_data['shiny']

        begin
          species_data = GameData::Species.try_get(species)
          if species_data
            icon_bitmap = GameData::Species.icon_bitmap(species_data.species, 0, nil, is_shiny) rescue nil
            if icon_bitmap
              # Pokemon icons have 2 frames side by side (64x64 each = 128x64 total)
              # Only use the first frame for static display
              frame_width = icon_bitmap.width / 2
              frame_height = icon_bitmap.height
              src_rect = Rect.new(0, 0, frame_width, frame_height)
              dest_rect = Rect.new(30, y + 20, 50, 50)
              @sprites[:content].bitmap.stretch_blt(dest_rect, icon_bitmap, src_rect)
            end
          end
        rescue

        end

        name_text = species_name
        quantity_text = "Lv.#{level}"
        if is_shiny
          quantity_text += " ★"
        end
      else
        name_text = "Pokemon"
        quantity_text = "(error)"
      end
    end

    pbSetSystemFont(@sprites[:content].bitmap)

    @sprites[:content].bitmap.font.size = 24
    @sprites[:content].bitmap.font.bold = true
    @sprites[:content].bitmap.font.color = Color.new(255, 255, 255)
    @sprites[:content].bitmap.draw_text(100, y + 15, w - 320, 28, name_text)

    @sprites[:content].bitmap.font.size  =  18
    @sprites[:content].bitmap.font.bold = false
    @sprites[:content].bitmap.font.color = Color.new(180, 220, 255)
    @sprites[:content].bitmap.draw_text(100, y + 45, w - 320, 22, quantity_text)

    @sprites[:content].bitmap.font.size  =  14
    @sprites[:content].bitmap.font.color = Color.new(160, 160, 180)
    seller = listing[:seller_username] || listing['seller_username'] || "Unknown"
    @sprites[:content].bitmap.draw_text(100, y + 68, w - 320, 18, "Sold by: #{seller}")

    price = listing[:price] || listing['price'] || 0
    price_w = 140
    price_x = w - price_w - 15

    @sprites[:content].bitmap.fill_rect(price_x, y + 25, price_w, 40, Color.new(255, 215, 0, 200))
    @sprites[:content].bitmap.fill_rect(price_x + 2, y + 27, price_w - 4, 36, Color.new(0, 0, 0, 180))

    @sprites[:content].bitmap.font.size = 28
    @sprites[:content].bitmap.font.bold = true
    @sprites[:content].bitmap.font.color  =  Color.new(255, 215, 0)
    @sprites[:content].bitmap.draw_text(price_x, y + 30, price_w, 32, "$#{price}", 1)
  end

  def draw_sell_menu
    pbSetSystemFont(@sprites[:content].bitmap)

    @sprites[:content].bitmap.font.size = 24
    @sprites[:content].bitmap.font.bold  =  true
    @sprites[:content].bitmap.font.color = Color.new(255, 255, 255)
    @sprites[:content].bitmap.draw_text(0, 5, @sprites[:content].bitmap.width, 28, "What would you like to sell?", 1)

    options = [
      {text: "Sell Item from Bag", icon: "bag", desc: "List an item from your inventory"},
      {text: "Sell Pokemon from Party", icon: "pokemon", desc: "List one of your Pokemon"},
      {text: "Back to Browse", icon: "back", desc: "Return to auction listings"}
    ]

    options.each_with_index do |opt, i|
      y = 35 + (i * 48)
      is_selected = (i == @selection)
      w = @sprites[:content].bitmap.width - 40

      @sprites[:content].bitmap.fill_rect(23, y + 2, w, 45, Color.new(0, 0, 0, 80))

      if is_selected
        @sprites[:content].bitmap.fill_rect(20, y, w, 45, Color.new(100, 180, 255))
        draw_gradient(@sprites[:content].bitmap, 22, y + 2, w - 4, 41, Color.new(50, 90, 130), Color.new(35, 65, 100))
      else
        @sprites[:content].bitmap.fill_rect(20, y, w, 45, Color.new(60, 60, 80))
        draw_gradient(@sprites[:content].bitmap, 22, y + 2, w - 4, 41, Color.new(35, 35, 50), Color.new(25, 25, 40))
      end

      icon_color = case opt[:icon]
                   when "bag" then Color.new(80, 140, 200)
                   when "pokemon" then Color.new(200, 80, 140)
                   else Color.new(120, 120, 120)
                   end
      @sprites[:content].bitmap.fill_rect(28, y + 5, 36, 36, Color.new(0, 0, 0, 100))
      @sprites[:content].bitmap.fill_rect(30, y + 7, 32, 32, icon_color)

      @sprites[:content].bitmap.font.size = 24
      @sprites[:content].bitmap.font.bold = true
      @sprites[:content].bitmap.font.color  =  Color.new(255, 255, 255)
      icon_text = case opt[:icon]
                  when "bag" then "[B]"
                  when "pokemon" then "[P]"
                  else '[<]'
                  end
      @sprites[:content].bitmap.draw_text(30, y + 7, 32, 32, icon_text, 1)

      @sprites[:content].bitmap.font.size = 18
      @sprites[:content].bitmap.font.bold = true
      @sprites[:content].bitmap.font.color  =  Color.new(255, 255, 255)
      @sprites[:content].bitmap.draw_text(75, y + 6, w - 85, 20, opt[:text])

      @sprites[:content].bitmap.font.size = 12
      @sprites[:content].bitmap.font.bold = false
      @sprites[:content].bitmap.font.color = Color.new(180, 180, 200)
      @sprites[:content].bitmap.draw_text(75, y + 27, w - 85, 14, opt[:desc])
    end

    @sprites[:content].bitmap.font.size = 12
    @sprites[:content].bitmap.font.color  =  Color.new(150, 150, 150)
    help_y = 35 + (3 * 48) + 2
    @sprites[:content].bitmap.draw_text(0, help_y, @sprites[:content].bitmap.width, 14, "Use UP/DOWN and ENTER", 1)
  end

  def handle_input
    return unless @active

    # Use Input.triggerex? which respects window focus guard
    if Input.triggerex?(0x09)  # Tab key
      cycle_tab
    end

    if Input.trigger?(Input::UP)
      navigate_up
    elsif Input.trigger?(Input::DOWN)
      navigate_down
    end

    if Input.trigger?(Input::USE)
      handle_select
    end

    if Input.triggerex?(0x46)  # F key
      toggle_filter
    end

    if defined?(MouseInput) && @current_tab == :browse && @search_bar_bounds
      if MouseInput.click?(0)
        mouse_x, mouse_y = MouseInput.pos

        game_x = mouse_x / 2
        game_y  =  mouse_y / 2

        content_x = @sprites[:content].x
        content_y = @sprites[:content].y
        bar_x1 = content_x + @search_bar_bounds[:x]
        bar_y1 = content_y + @search_bar_bounds[:y]
        bar_x2 = bar_x1 + @search_bar_bounds[:width]
        bar_y2 = bar_y1 + @search_bar_bounds[:height]

        if game_x >= bar_x1 && game_x < bar_x2 && game_y >= bar_y1 && game_y < bar_y2
          open_search_dialog
        end
      end
    end

    if Input.trigger?(Input::BACK)
      deactivate
    end
  end

  def cycle_tab
    current_index = TABS.index(@current_tab)
    @current_tab = TABS[(current_index + 1) % TABS.length]
    @selection = 0
    @scroll_offset = 0
    update_tabs
    refresh_listings
    update_content
  end

  def toggle_filter
    return unless @current_tab == :browse
    @filter_type  =  (@filter_type + 1) % FILTER_TYPES.length
    refresh_listings
  end

  def open_search_dialog
    return unless @current_tab == :browse

    search_text = pbMessageFreeText(
      _INTL("Search for Pokemon or Items"),
      @search_query,
      false,
      50
    )

    if search_text
      @search_query = search_text
      refresh_listings
    end
  end

  def navigate_up
    if @current_tab == :sell
      @selection = [@selection - 1, 0].max
    else
      if @selection > 0
        @selection -= 1
        if @selection < @scroll_offset
          @scroll_offset  =  @selection
        end
      end
    end
    update_content
  end

  def navigate_down
    if @current_tab == :sell
      @selection = [@selection + 1, 2].min
    else
      if @selection < @listings.length - 1
        @selection += 1
        if @selection >= @scroll_offset + @visible_count
          @scroll_offset = @selection - @visible_count + 1
        end
      end
    end
    update_content
  end

  def handle_select
    case @current_tab
    when :browse
      handle_buy_listing
    when :my_listings
      handle_cancel_listing
    when :sell
      handle_sell_menu_select
    end
  end

  def handle_buy_listing
    return if @listings.empty?
    listing = @listings[@selection]
    return unless listing

    price = (listing[:price] || listing['price'] || 0).to_i
    money  =  ($player && $player.money) ? $player.money.to_i : 0

    if money < price
      pbMessage("Not enough money! You need $#{price} but only have $#{money}.")
      return
    end

    listing_type = (listing[:listing_type] || listing['listing_type']).to_s
    if listing_type == 'ITEM'
      item_id = listing[:item_id] || listing['item_id']
      item_data_for_name = GameData::Item.try_get(item_id.to_sym) rescue nil
      type_name = item_data_for_name ? item_data_for_name.name : item_id.to_s
    else
      pkmn_data  =  listing[:pokemon_data] || listing['pokemon_data']
      if pkmn_data && !pkmn_data.empty?
        species  =  pkmn_data[:species] || pkmn_data['species']
        species_data_for_name = GameData::Species.try_get(species) rescue nil
        type_name = species_data_for_name ? species_data_for_name.name : species.to_s
      else
        type_name = "Pokemon"
      end
    end

    if pbConfirmMessage("Buy #{type_name} for $#{price}?")
      $auction_last_result  =  nil
      listing_id = listing[:id] || listing['id']
      pbMultiplayerClient.auction_buy(listing_id)

      timeout = 100
      while timeout > 0 && !$auction_last_result
        Graphics.update
        Input.update
        pbMultiplayerClient.update
        sleep(0.05)
        timeout -= 1
      end

      if $auction_last_result && $auction_last_result[:success]
        pbMessage("Purchase successful!")

        update_money_display
        refresh_listings
      elsif $auction_last_result
        pbMessage("Error: #{$auction_last_result[:error]}")
      else
        pbMessage("Server timeout. Please check your purchase later.")
      end
    end
  end

  def handle_cancel_listing
    return if @listings.empty?
    listing = @listings[@selection]
    return unless listing

    if pbConfirmMessage("Cancel this listing?")
      $auction_last_result = nil
      listing_id = listing[:id] || listing['id']
      pbMultiplayerClient.auction_cancel(listing_id)

      timeout = 100
      while timeout > 0 && !$auction_last_result
        Graphics.update
        Input.update
        pbMultiplayerClient.update
        sleep(0.05)
        timeout -= 1
      end

      if $auction_last_result && $auction_last_result[:success]
        pbMessage("Listing cancelled! Item returned.")
        refresh_listings
      elsif $auction_last_result
        pbMessage("Error: #{$auction_last_result[:error]}")
      else
        pbMessage('Server timeout.')
      end
    end
  end

  def handle_sell_menu_select
    case @selection
    when 0
      sell_item
    when 1
      sell_pokemon
    when 2
      cycle_tab
    end
  end

  def sell_item

    item = nil
    scene = PokemonBag_Scene.new
    screen = PokemonBagScreen.new(scene, $bag)

    item = screen.pbChooseItemScreen(proc { |itm|
      item_data = GameData::Item.try_get(itm)
      next false unless item_data
      !item_data.is_key_item?
    })

    return unless item

    max_qty = $bag.quantity(item)
    params = ChooseNumberParams.new
    params.setRange(1, max_qty)
    params.setDefaultValue(1)
    qty  =  pbMessageChooseNumber("How many to sell? (Have: #{max_qty})", params)
    return if qty == 0

    params = ChooseNumberParams.new
    params.setRange(1, 999999)
    params.setDefaultValue(100)
    price = pbMessageChooseNumber("Set price:", params)
    return if price == 0

    if pbConfirmMessage("List #{GameData::Item.get(item).name} x#{qty} for $#{price}?")
      $auction_last_result  =  nil
      pbMultiplayerClient.auction_list_item(item.to_s, qty, price)

      timeout = 100
      while timeout > 0 && !$auction_last_result
        Graphics.update
        Input.update
        pbMultiplayerClient.update
        sleep(0.05)
        timeout -= 1
      end

      if $auction_last_result && $auction_last_result[:success]
        $bag.remove(item, qty)
        pbMessage("Item listed successfully!")
      elsif $auction_last_result
        pbMessage("Error: #{$auction_last_result[:error]}")
      else
        pbMessage("Server timeout.")
      end
    end
  end

  def sell_pokemon
    return if !$player || $player.party.length == 0

    if $player.party.length <= 1
      pbMessage("You can't sell your last Pokemon!")
      return
    end

    scene = PokemonParty_Scene.new
    screen = PokemonPartyScreen.new(scene, $player.party)
    screen.pbStartScene('Choose a Pokemon to sell.', false)
    chosen = screen.pbChoosePokemon
    screen.pbEndScene

    return if chosen < 0

    pkmn = $player.party[chosen]

    params = ChooseNumberParams.new
    params.setRange(1, 999999)
    params.setDefaultValue(500)
    price = pbMessageChooseNumber("Set price for #{pkmn.name}:", params)
    return if price == 0

    if pbConfirmMessage("List #{pkmn.name} for $#{price}?")

      pkmn_data = pbModernTradeManager.serialize_pokemon(pkmn)

      $auction_last_result = nil
      pbMultiplayerClient.auction_list_pokemon(pkmn_data, chosen, price)

      timeout  =  100
      while timeout > 0 && !$auction_last_result
        Graphics.update
        Input.update
        pbMultiplayerClient.update
        sleep(0.05)
        timeout -= 1
      end

      if $auction_last_result && $auction_last_result[:success]
        $player.party.delete_at(chosen)
        pbMessage("Pokemon listed successfully!")
      elsif $auction_last_result
        pbMessage("Error: #{$auction_last_result[:error]}")
      else
        pbMessage("Server timeout.")
      end
    end
  end

  def update
    return unless @active

    Graphics.update
    Input.update
    handle_input
    pbMultiplayerClient.update if pbMultiplayerConnected?
    check_listings_updates
  end

  def dispose_sprites
    @sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite.bitmap
      sprite.dispose
    end
    @sprites.clear
  end
end

$auction_house_ui = nil

def pbOpenAuctionHouse
  return unless pbMultiplayerConnected?

  $auction_house_ui ||= AuctionHouseUI.new
  $auction_house_ui.activate

  loop do    $auction_house_ui.update
    break unless $auction_house_ui.instance_variable_get(:@active)
  end
end

if defined?(QuickMultiplayerMenu)
  class QuickMultiplayerMenu
    alias auction_original_show show if method_defined?(:show)

    def show
      return unless pbIsMultiplayerMode?

      commands = []
      commands.push('Social UI') if pbMultiplayerConnected?
      commands.push("Auction House") if pbMultiplayerConnected?
      commands.push('Battle') if pbMultiplayerConnected?
      commands.push("Cancel")

      choice = pbMessage("Quick Menu", commands, -1)

      case choice
      when 0
        pbOpenSocialUI if pbMultiplayerConnected?
      when 1
        pbOpenAuctionHouse if pbMultiplayerConnected?
      when 2

        pbOpenSocialUI if pbMultiplayerConnected?
      end
    end
  end
end

puts "Auction House UI loaded - Press Q and select Auction House!"
