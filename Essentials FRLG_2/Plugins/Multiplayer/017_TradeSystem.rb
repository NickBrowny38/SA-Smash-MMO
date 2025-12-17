module TradeState
  WAITING_FOR_OFFER      =  0
  SELECTING_POKEMON      =  1
  WAITING_FOR_RESPONSE  = 2
  REVIEWING_TRADE       = 3
  TRADE_ACCEPTED        = 4
  TRADE_DECLINED        = 5
  TRADE_COMPLETE        = 6
end

class ModernPokemonSelector
  def initialize(party, title = "Select a Pokemon")
    @party  =  party
    @title = title
    @selection = 0
    @scroll_offset = 0
    @max_visible_rows = 3
    @viewport  =  Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @hover_offset  =  0
    @animation_timer  =  0
    create_ui
  end

  def create_ui

    @sprites[:bg] = Sprite.new(@viewport)
    @sprites[:bg].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    draw_animated_background(@sprites[:bg].bitmap)

    create_title_bar

    create_pokemon_grid

    create_info_panel

    create_instructions
  end

  def create_title_bar
    width = 480
    height = 60

    @sprites[:title_bg] = Sprite.new(@viewport)
    @sprites[:title_bg].bitmap = Bitmap.new(width, height)
    @sprites[:title_bg].x = (Graphics.width - width) / 2
    @sprites[:title_bg].y = 20

    bitmap = @sprites[:title_bg].bitmap

    for i in 0...height
      r = 30 + (i / height.to_f * 50).to_i
      g  =  60 + (i / height.to_f * 40).to_i
      b = 120 - (i / height.to_f * 20).to_i
      bitmap.fill_rect(0, i, width, 1, Color.new(r, g, b, 255))
    end

    bitmap.fill_rect(0, 0, width, 3, Color.new(100, 150, 255, 200))
    bitmap.fill_rect(0, height - 3, width, 3, Color.new(40, 60, 100, 200))

    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap  =  Bitmap.new(width, height)
    @sprites[:title].x = @sprites[:title_bg].x
    @sprites[:title].y = @sprites[:title_bg].y

    pbSetSystemFont(@sprites[:title].bitmap)
    @sprites[:title].bitmap.font.size = 28
    @sprites[:title].bitmap.font.bold = true
    @sprites[:title].bitmap.font.color = Color.new(255, 255, 255, 255)
    @sprites[:title].bitmap.draw_text(0, 10, width, 40, @title, 1)
  end

  def create_pokemon_grid
    @pokemon_cards = []
    @card_width = 220
    @card_height = 140
    @spacing_x  =  20
    @spacing_y = 20
    @start_x = (Graphics.width - (@card_width * 2 + @spacing_x)) / 2
    @start_y = 100

    @party.each_with_index do |pokemon, index|
      next unless pokemon

      row = index / 2
      col = index % 2

      x = @start_x + col * (@card_width + @spacing_x)
      y = @start_y + (row - @scroll_offset) * (@card_height + @spacing_y)

      card = create_pokemon_card(pokemon, x, y, @card_width, @card_height, index, row)
      @pokemon_cards << card
    end

    create_scroll_indicators
  end

  def create_pokemon_card(pokemon, x, y, width, height, index, row)
    card = {}
    card[:pokemon] = pokemon
    card[:index] = index
    card[:row] = row
    card[:base_x]  =  x
    card[:base_y] = y
    card[:x] = x
    card[:y] = y
    card[:width] = width
    card[:height] = height

    card[:sprite] = Sprite.new(@viewport)
    card[:sprite].bitmap  =  Bitmap.new(width, height)
    card[:sprite].x = x
    card[:sprite].y = y

    card[:pkmn_sprite] = Sprite.new(@viewport)
    card[:pkmn_sprite].bitmap = Bitmap.new(96, 96)
    card[:pkmn_sprite].x = x + 10
    card[:pkmn_sprite].y = y + 10

    begin
      icon = GameData::Species.icon_bitmap_from_pokemon(pokemon)
      if icon

        card[:pkmn_sprite].bitmap.stretch_blt(
          Rect.new(0, 0, 96, 96),
          icon,
          Rect.new(0, 0, 64, 64)
        )
      end
    rescue => e
      puts "[SELECTOR] Error loading Pokemon sprite: #{e.message}"
    end

    card[:text] = Sprite.new(@viewport)
    card[:text].bitmap = Bitmap.new(width, height)
    card[:text].x = x
    card[:text].y = y

    draw_card_text(card[:text].bitmap, pokemon, width, height)

    return card
  end

  def truncate_text(bitmap, text, max_width)
    return text if bitmap.text_size(text).width <= max_width

    truncated  =  text
    while bitmap.text_size(truncated + "...").width > max_width && truncated.length > 1
      truncated = truncated[0...-1]
    end

    return truncated.length > 0 ? truncated + "..." : text[0] + "..."
  end

  def draw_card_text(bitmap, pokemon, width, height)
    pbSetSystemFont(bitmap)

    bitmap.font.size = 20
    bitmap.font.bold = true
    max_name_width = width - 130
    pokemon_name = truncate_text(bitmap, pokemon.name, max_name_width)

    if pokemon.shiny?
      bitmap.font.color = Color.new(255, 215, 0, 255)
      bitmap.draw_text(115, 10, max_name_width, 24, pokemon_name)

      name_width = bitmap.text_size(pokemon_name).width
      if name_width < max_name_width - 20
        bitmap.font.size = 16
        bitmap.draw_text(115 + name_width + 2, 12, 20, 20, '✦')
      end
    else
      bitmap.font.color = Color.new(255, 255, 255, 255)
      bitmap.draw_text(115, 10, max_name_width, 24, pokemon_name)
    end

    bitmap.font.size = 18
    bitmap.font.bold = false
    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(115, 35, width - 125, 22, "Lv. #{pokemon.level}")

    hp_ratio = pokemon.hp / pokemon.totalhp.to_f
    bar_width  =  90
    bar_x = 115
    bar_y = 62

    bitmap.fill_rect(bar_x, bar_y, bar_width, 10, Color.new(60, 60, 60, 255))

    if hp_ratio > 0.5
      hp_color = Color.new(100, 220, 100, 255)
    elsif hp_ratio > 0.25
      hp_color = Color.new(255, 200, 80, 255)
    else
      hp_color = Color.new(255, 100, 100, 255)
    end

    bitmap.fill_rect(bar_x, bar_y, (bar_width * hp_ratio).to_i, 10, hp_color)

    bitmap.font.size  =  14
    bitmap.font.color = Color.new(255, 255, 255, 255)
    bitmap.draw_text(bar_x, bar_y + 12, bar_width, 18, "#{pokemon.hp}/#{pokemon.totalhp}", 1)

    type1 = pokemon.types[0]
    draw_type_badge(bitmap, type1, 115, 95, 40, 18) if type1

    type2 = pokemon.types[1]
    draw_type_badge(bitmap, type2, 160, 95, 40, 18) if type2 && type2 != type1
  end

  def draw_type_badge(bitmap, type, x, y, width, height)
    type_color = get_type_color(type)

    bitmap.fill_rect(x, y, width, height, type_color)
    bitmap.fill_rect(x + 1, y + 1, width - 2, height - 2, lighten_color(type_color, 20))

    bitmap.font.size = 12
    bitmap.font.bold = true
    bitmap.font.color = Color.new(255, 255, 255, 255)
    type_name = GameData::Type.get(type).name
    bitmap.draw_text(x, y + 2, width, height - 4, type_name, 1)
  end

  def get_type_color(type)

    case type
    when :NORMAL   then Color.new(168, 168, 120)
    when :FIRE     then Color.new(240, 128, 48)
    when :WATER    then Color.new(104, 144, 240)
    when :ELECTRIC then Color.new(248, 208, 48)
    when :GRASS    then Color.new(120, 200, 80)
    when :ICE      then Color.new(152, 216, 216)
    when :FIGHTING then Color.new(192, 48, 40)
    when :POISON   then Color.new(160, 64, 160)
    when :GROUND   then Color.new(224, 192, 104)
    when :FLYING   then Color.new(168, 144, 240)
    when :PSYCHIC  then Color.new(248, 88, 136)
    when :BUG      then Color.new(168, 184, 32)
    when :ROCK     then Color.new(184, 160, 56)
    when :GHOST    then Color.new(112, 88, 152)
    when :DRAGON   then Color.new(112, 56, 248)
    when :DARK     then Color.new(112, 88, 72)
    when :STEEL    then Color.new(184, 184, 208)
    when :FAIRY    then Color.new(238, 153, 172)
    else Color.new(120, 120, 120)
    end
  end

  def lighten_color(color, amount)
    Color.new(
      [color.red + amount, 255].min,
      [color.green + amount, 255].min,
      [color.blue + amount, 255].min,
      color.alpha
    )
  end

  def create_info_panel
    width = 480
    height = 80

    @sprites[:info_bg] = Sprite.new(@viewport)
    @sprites[:info_bg].bitmap = Bitmap.new(width, height)
    @sprites[:info_bg].x  =  (Graphics.width - width) / 2
    @sprites[:info_bg].y  =  Graphics.height - height - 60

    bitmap = @sprites[:info_bg].bitmap

    for i in 0...height
      alpha = 180 + (i / height.to_f * 40).to_i
      bitmap.fill_rect(0, i, width, 1, Color.new(30, 30, 50, alpha))
    end

    @sprites[:info_text] = Sprite.new(@viewport)
    @sprites[:info_text].bitmap = Bitmap.new(width - 40, height - 20)
    @sprites[:info_text].x = @sprites[:info_bg].x + 20
    @sprites[:info_text].y = @sprites[:info_bg].y + 10

    update_info_panel
  end

  def update_info_panel
    return unless @sprites[:info_text]

    bitmap = @sprites[:info_text].bitmap
    bitmap.clear

    pokemon = @party[@selection]
    return unless pokemon

    pbSetSystemFont(bitmap)
    bitmap.font.size = 16
    bitmap.font.color = Color.new(200, 220, 255, 255)

    ability_name = pokemon.ability ? GameData::Ability.get(pokemon.ability).name : 'Unknown'
    ability_text = "Ability: #{ability_name}"
    ability_text  =  truncate_text(bitmap, ability_text, bitmap.width / 2 - 10)
    bitmap.draw_text(0, 0, bitmap.width / 2, 24, ability_text)

    nature_name = pokemon.nature ? GameData::Nature.get(pokemon.nature).name : 'Unknown'
    nature_text = "Nature: #{nature_name}"
    nature_text = truncate_text(bitmap, nature_text, bitmap.width / 2 - 10)
    bitmap.draw_text(bitmap.width / 2, 0, bitmap.width / 2, 24, nature_text)

    ot_name = pokemon.owner ? pokemon.owner.name : "Unknown"
    ot_text = "Original Trainer: #{ot_name}"
    ot_text = truncate_text(bitmap, ot_text, bitmap.width - 10)
    bitmap.draw_text(0, 28, bitmap.width, 24, ot_text)
  end

  def create_instructions
    width = 480
    height = 40

    @sprites[:instructions] = Sprite.new(@viewport)
    @sprites[:instructions].bitmap = Bitmap.new(width, height)
    @sprites[:instructions].x  =  (Graphics.width - width) / 2
    @sprites[:instructions].y = Graphics.height - 50

    bitmap = @sprites[:instructions].bitmap
    pbSetSystemFont(bitmap)
    bitmap.font.size = 15
    bitmap.font.bold = true
    bitmap.font.color = Color.new(255, 255, 255, 255)
    bitmap.draw_text(0, 0, width, height, "Arrows: Select  C: Confirm  A/X: Summary  B: Cancel", 1)
  end

  def draw_animated_background(bitmap)

    for i in 0...Graphics.height
      r = 20 + (i / Graphics.height.to_f * 40).to_i
      g = 30 + (i / Graphics.height.to_f * 50).to_i
      b  =  60 + (i / Graphics.height.to_f * 80).to_i
      bitmap.fill_rect(0, i, Graphics.width, 1, Color.new(r, g, b, 255))
    end
  end

  def create_scroll_indicators
    total_rows = (@party.length + 1) / 2
    return if total_rows <= @max_visible_rows

    @sprites[:scroll_up] = Sprite.new(@viewport)
    @sprites[:scroll_up].bitmap = Bitmap.new(40, 40)
    @sprites[:scroll_up].x = (Graphics.width - 40) / 2
    @sprites[:scroll_up].y = 85
    draw_arrow(@sprites[:scroll_up].bitmap, :up)

    @sprites[:scroll_down] = Sprite.new(@viewport)
    @sprites[:scroll_down].bitmap = Bitmap.new(40, 40)
    @sprites[:scroll_down].x = (Graphics.width - 40) / 2
    @sprites[:scroll_down].y = Graphics.height - 150
    draw_arrow(@sprites[:scroll_down].bitmap, :down)
  end

  def draw_arrow(bitmap, direction)

    bitmap.clear
    color  =  Color.new(255, 255, 255, 200)

    if direction == :up

      for i in 0...15
        x_offset  =  15 - i
        y = 20 - i
        bitmap.fill_rect(x_offset, y, 1 + i * 2, 1, color)
      end
    else

      for i in 0...15
        x_offset = 15 - i
        y = 5 + i
        bitmap.fill_rect(x_offset, y, 1 + i * 2, 1, color)
      end
    end
  end

  def update_scroll_indicators
    total_rows  =  (@party.length + 1) / 2
    return if total_rows <= @max_visible_rows

    if @sprites[:scroll_up]
      @sprites[:scroll_up].visible = (@scroll_offset > 0)
    end

    if @sprites[:scroll_down]
      @sprites[:scroll_down].visible = (@scroll_offset + @max_visible_rows < total_rows)
    end
  end

  def update_card_displays
    @pokemon_cards.each_with_index do |card, index|
      selected = (index == @selection)
      row = card[:row]

      visible  =  (row >= @scroll_offset && row < @scroll_offset + @max_visible_rows)

      card[:y] = @start_y + (row - @scroll_offset) * (@card_height + @spacing_y)
      card[:sprite].y = card[:y]
      card[:pkmn_sprite].y = card[:y] + 10
      card[:text].y = card[:y]

      card[:sprite].visible  =  visible
      card[:pkmn_sprite].visible = visible
      card[:text].visible = visible

      next unless visible

      bitmap = card[:sprite].bitmap
      bitmap.clear

      if selected

        offset = (@hover_offset / 10.0).to_i

        bitmap.fill_rect(0, 0, card[:width], card[:height], Color.new(100, 150, 255, 200 + offset))
        bitmap.fill_rect(3, 3, card[:width] - 6, card[:height] - 6, Color.new(80, 130, 220, 220 + offset))

        for i in 0...card[:height] - 10
          shade  =  60 + (i / (card[:height] - 10).to_f * 40).to_i
          bitmap.fill_rect(6, 6 + i, card[:width] - 12, 1, Color.new(shade, shade + 30, shade + 80, 255))
        end

        card[:sprite].y = card[:y] - 5
        card[:pkmn_sprite].y = card[:y] + 5
        card[:text].y = card[:y] - 5
      else

        bitmap.fill_rect(0, 0, card[:width], card[:height], Color.new(80, 80, 100, 255))
        bitmap.fill_rect(2, 2, card[:width] - 4, card[:height] - 4, Color.new(50, 50, 65, 255))

        for i in 0...card[:height] - 4
          shade = 40 + (i / (card[:height] - 4).to_f * 30).to_i
          bitmap.fill_rect(2, 2 + i, card[:width] - 4, 1, Color.new(shade, shade, shade + 15, 255))
        end

        card[:sprite].y = card[:y]
        card[:pkmn_sprite].y = card[:y] + 10
        card[:text].y = card[:y]
      end
    end
  end

  def run
    loop do      Graphics.update
      Input.update

      @animation_timer += 1
      @hover_offset = (Math.sin(@animation_timer / 10.0) * 20).to_i

      update_card_displays if @animation_timer % 2 == 0
      update_scroll_indicators if @animation_timer % 10 == 0

      old_selection = @selection

      if Input.trigger?(Input::UP)
        @selection = (@selection - 2) % @party.length
        @selection = @party.length - 1 if @selection < 0
      elsif Input.trigger?(Input::DOWN)
        @selection = (@selection + 2) % @party.length
      elsif Input.trigger?(Input::LEFT)
        @selection -= 1 if @selection % 2 == 1
      elsif Input.trigger?(Input::RIGHT)
        @selection += 1 if @selection % 2 == 0 && @selection + 1 < @party.length
      end

      if @selection != old_selection

        selected_row = @selection / 2
        total_rows = (@party.length + 1) / 2

        if selected_row < @scroll_offset

          @scroll_offset = selected_row
        elsif selected_row >= @scroll_offset + @max_visible_rows

          @scroll_offset = selected_row - @max_visible_rows + 1
        end

        max_scroll = [total_rows - @max_visible_rows, 0].max
        @scroll_offset = [[@scroll_offset, 0].max, max_scroll].min

        update_info_panel
        update_card_displays
        update_scroll_indicators
      end

      if Input.trigger?(Input::ACTION) || Input.trigger?(Input::JUMPUP)
        pokemon  =  @party[@selection]
        if pokemon
          summary = PokemonTradeSummary.new(pokemon)
          summary.run

          update_card_displays
          update_scroll_indicators
        end
      end

      if Input.trigger?(Input::USE)
        pokemon = @party[@selection]
        if pokemon
          dispose
          return pokemon
        end
      end

      if Input.trigger?(Input::BACK)
        dispose
        return nil
      end
    end
  end

  def dispose
    @pokemon_cards.each do |card|
      card[:sprite].bitmap.dispose if card[:sprite].bitmap
      card[:sprite].dispose if card[:sprite]
      card[:pkmn_sprite].bitmap.dispose if card[:pkmn_sprite].bitmap
      card[:pkmn_sprite].dispose if card[:pkmn_sprite]
      card[:text].bitmap.dispose if card[:text].bitmap
      card[:text].dispose if card[:text]
    end

    @sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite && sprite.bitmap
      sprite.dispose if sprite
    end

    @viewport.dispose
  end
end

class PokemonTradeSummary
  def initialize(pokemon, owner_name  =  nil)
    @pokemon = pokemon
    @owner_name = owner_name
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites  =  {}
    @page = 0
    create_ui
  end

  def create_ui

    @sprites[:bg] = Sprite.new(@viewport)
    @sprites[:bg].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    draw_background(@sprites[:bg].bitmap)

    create_title_bar

    @sprites[:content] = Sprite.new(@viewport)
    @sprites[:content].bitmap = Bitmap.new(500, 370)
    @sprites[:content].x = (Graphics.width - 500) / 2
    @sprites[:content].y = 80

    create_instructions

    update_display
  end

  def create_title_bar
    width = 480
    height = 60

    @sprites[:title_bg] = Sprite.new(@viewport)
    @sprites[:title_bg].bitmap = Bitmap.new(width, height)
    @sprites[:title_bg].x = (Graphics.width - width) / 2
    @sprites[:title_bg].y = 20

    bitmap = @sprites[:title_bg].bitmap

    for i in 0...height
      r = 40 + (i / height.to_f * 30).to_i
      g  =  70 + (i / height.to_f * 30).to_i
      b = 130 - (i / height.to_f * 20).to_i
      bitmap.fill_rect(0, i, width, 1, Color.new(r, g, b, 255))
    end

    bitmap.fill_rect(0, 0, width, 3, Color.new(100, 150, 255, 200))
    bitmap.fill_rect(0, height - 3, width, 3, Color.new(40, 60, 100, 200))

    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap  =  Bitmap.new(width, height)
    @sprites[:title].x = @sprites[:title_bg].x
    @sprites[:title].y = @sprites[:title_bg].y

    pbSetSystemFont(@sprites[:title].bitmap)
    @sprites[:title].bitmap.font.size = 24
    @sprites[:title].bitmap.font.bold = true
    @sprites[:title].bitmap.font.color = Color.new(255, 255, 255, 255)

    name = @pokemon.name
    name = name[0..12] + "..." if name.length > 15
    title_text = "#{name} - Summary"
    @sprites[:title].bitmap.draw_text(0, 15, width, 40, title_text, 1)
  end

  def create_instructions
    width  =  500
    height = 40

    @sprites[:instructions] = Sprite.new(@viewport)
    @sprites[:instructions].bitmap = Bitmap.new(width, height)
    @sprites[:instructions].x  =  (Graphics.width - width) / 2
    @sprites[:instructions].y = Graphics.height - 50

    bitmap  =  @sprites[:instructions].bitmap
    pbSetSystemFont(bitmap)
    bitmap.font.size = 15
    bitmap.font.bold = true
    bitmap.font.color = Color.new(255, 255, 255, 255)
    bitmap.draw_text(0, 0, width, height, "Left/Right: Change Page   B: Close", 1)
  end

  def draw_background(bitmap)
    for i in 0...Graphics.height
      r = 25 + (i / Graphics.height.to_f * 35).to_i
      g  =  35 + (i / Graphics.height.to_f * 45).to_i
      b  =  65 + (i / Graphics.height.to_f * 75).to_i
      bitmap.fill_rect(0, i, Graphics.width, 1, Color.new(r, g, b, 255))
    end
  end

  def update_display
    bitmap = @sprites[:content].bitmap
    bitmap.clear

    for i in 0...370
      shade = 35 + (i / 370.to_f * 25).to_i
      bitmap.fill_rect(0, i, 500, 1, Color.new(shade, shade, shade + 20, 230))
    end

    bitmap.fill_rect(0, 0, 500, 2, Color.new(100, 150, 255, 200))
    bitmap.fill_rect(0, 368, 500, 2, Color.new(100, 150, 255, 200))

    case @page
    when 0 then draw_stats_page(bitmap)
    when 1 then draw_moves_page(bitmap)
    when 2 then draw_details_page(bitmap)
    end

    pbSetSystemFont(bitmap)
    bitmap.font.size = 14
    bitmap.font.color  =  Color.new(200, 200, 200, 255)
    page_names = ["Stats", "Moves", "Details"]
    bitmap.draw_text(0, 345, 500, 20, "#{page_names[@page]} (#{@page + 1}/3)", 1)
  end

  def draw_stats_page(bitmap)
    pbSetSystemFont(bitmap)

    begin
      icon  =  GameData::Species.icon_bitmap_from_pokemon(@pokemon)
      if icon
        bitmap.stretch_blt(
          Rect.new(210, 10, 80, 80),
          icon,
          Rect.new(0, 0, 64, 64)
        )
      end
    rescue => e
      puts "[SUMMARY] Error loading sprite: #{e.message}"
    end

    bitmap.font.size = 22
    bitmap.font.bold  =  true
    gender_symbol = @pokemon.male? ? " ♂" : (@pokemon.female? ? " ♀" : "")
    gender_color = @pokemon.male? ? Color.new(100, 150, 255) : Color.new(255, 100, 150)

    if @pokemon.shiny?
      bitmap.font.color = Color.new(255, 215, 0, 255)
      name_text = "#{@pokemon.name} ✦"
    else
      bitmap.font.color = Color.new(255, 255, 255, 255)
      name_text = @pokemon.name
    end

    bitmap.draw_text(20, 100, 460, 28, name_text, 1)

    if gender_symbol != ""

      name_width = bitmap.text_size(name_text).width
      gender_x = 250 + (name_width / 2) + 5
      bitmap.font.color = gender_color
      bitmap.draw_text(gender_x, 100, 40, 28, gender_symbol)
    end

    bitmap.font.size = 18
    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(20, 130, 460, 24, "Level #{@pokemon.level}", 1)

    bitmap.font.size = 16
    bitmap.font.color = Color.new(255, 255, 255, 255)
    bitmap.draw_text(40, 165, 100, 22, "HP:")
    bitmap.draw_text(360, 165, 100, 22, "#{@pokemon.hp}/#{@pokemon.totalhp}", 2)

    hp_ratio = @pokemon.hp / @pokemon.totalhp.to_f
    bar_x = 140
    bar_width = 210
    bitmap.fill_rect(bar_x, 170, bar_width, 12, Color.new(60, 60, 60))

    hp_color  =  hp_ratio > 0.5 ? Color.new(100, 220, 100) :
               hp_ratio > 0.25 ? Color.new(255, 200, 80) : Color.new(255, 100, 100)
    bitmap.fill_rect(bar_x, 170, (bar_width * hp_ratio).to_i, 12, hp_color)

    y_offset = 200
    stats = [
      ["Attack", @pokemon.attack],
      ["Defense", @pokemon.defense],
      ["Sp. Atk", @pokemon.spatk],
      ["Sp. Def", @pokemon.spdef],
      ["Speed", @pokemon.speed]
    ]

    bitmap.font.size = 16
    stats.each_with_index do |(name, value), i|
      y = y_offset + (i * 22)
      bitmap.font.color = Color.new(200, 220, 255, 255)
      bitmap.draw_text(40, y, 120, 22, "#{name}:")
      bitmap.font.color  =  Color.new(255, 255, 255, 255)
      bitmap.draw_text(360, y, 100, 22, value.to_s, 2)
    end
  end

  def draw_moves_page(bitmap)
    pbSetSystemFont(bitmap)

    bitmap.font.size = 20
    bitmap.font.bold = true
    bitmap.font.color = Color.new(255, 255, 255, 255)
    bitmap.draw_text(20, 15, 460, 28, 'Moves', 1)

    y_offset = 55
    @pokemon.moves.each_with_index do |move, i|
      next if !move || move.id.nil?

      y = y_offset + (i * 65)

      for j in 0...60
        shade = 50 + (j / 60.to_f * 15).to_i
        bitmap.fill_rect(25, y + j, 450, 1, Color.new(shade, shade, shade + 30, 200))
      end

      type_color  =  get_type_color(move.type)
      bitmap.fill_rect(25, y, 450, 2, type_color)

      bitmap.font.size = 18
      bitmap.font.bold  =  true
      bitmap.font.color = Color.new(255, 255, 255, 255)
      move_name = GameData::Move.get(move.id).name
      bitmap.draw_text(35, y + 5, 250, 24, move_name)

      draw_type_badge(bitmap, move.type, 310, y + 5, 60, 22)

      bitmap.font.size = 14
      bitmap.font.color  =  Color.new(200, 220, 255, 255)
      bitmap.draw_text(380, y + 5, 85, 22, "PP: #{move.pp}/#{move.total_pp}", 2)

      bitmap.font.size = 14
      bitmap.font.color = Color.new(180, 180, 200, 255)
      power = move.power > 0 ? move.power.to_s : "—"
      accuracy = move.accuracy > 0 ? move.accuracy.to_s : "—"
      bitmap.draw_text(35, y + 30, 150, 20, "Power: #{power}")
      bitmap.draw_text(200, y + 30, 150, 20, "Acc: #{accuracy}")
    end

    if @pokemon.moves.length == 0
      bitmap.font.size = 16
      bitmap.font.color = Color.new(150, 150, 150, 255)
      bitmap.draw_text(20, 120, 460, 24, "No moves learned", 1)
    end
  end

  def draw_details_page(bitmap)
    pbSetSystemFont(bitmap)

    bitmap.font.size = 20
    bitmap.font.bold = true
    bitmap.font.color = Color.new(255, 255, 255, 255)
    bitmap.draw_text(20, 15, 460, 28, "Details", 1)

    y_offset = 55
    bitmap.font.size = 15
    bitmap.font.bold  =  false
    line_height = 28

    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(30, y_offset, 140, 24, "Nature:")
    bitmap.font.color = Color.new(255, 255, 255, 255)
    nature_name = @pokemon.nature ? GameData::Nature.get(@pokemon.nature).name : "Unknown"
    bitmap.draw_text(180, y_offset, 290, 24, nature_name)

    y_offset += line_height
    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(30, y_offset, 140, 24, "Ability:")
    bitmap.font.color = Color.new(255, 255, 255, 255)
    ability_name = @pokemon.ability ? GameData::Ability.get(@pokemon.ability).name : "Unknown"

    ability_name = ability_name[0..25] + "..." if ability_name.length > 28
    bitmap.draw_text(180, y_offset, 290, 24, ability_name)

    y_offset += line_height
    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(30, y_offset, 140, 24, "Held Item:")
    bitmap.font.color = Color.new(255, 255, 255, 255)
    item_name = @pokemon.item ? GameData::Item.get(@pokemon.item).name : "None"
    item_name = item_name[0..25] + '...' if item_name.length > 28
    bitmap.draw_text(180, y_offset, 290, 24, item_name)

    y_offset += line_height
    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(30, y_offset, 140, 24, 'OT:')
    bitmap.font.color = Color.new(255, 255, 255, 255)
    ot_name = @owner_name || (@pokemon.owner ? @pokemon.owner.name : 'Unknown')
    ot_name = ot_name[0..20] + "..." if ot_name.length > 23
    bitmap.draw_text(180, y_offset, 290, 24, ot_name)

    y_offset += line_height
    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(30, y_offset, 140, 24, "ID No.:")
    bitmap.font.color = Color.new(255, 255, 255, 255)
    id_no = @pokemon.owner ? sprintf("%05d", @pokemon.owner.public_id) : "?????"
    bitmap.draw_text(180, y_offset, 290, 24, id_no)

    y_offset += line_height + 5
    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(30, y_offset, 140, 24, 'Type:')

    types = @pokemon.types.uniq
    types.each_with_index do |type, i|
      draw_type_badge(bitmap, type, 180 + (i * 80), y_offset, 70, 24)
    end

    y_offset += line_height + 10
    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(30, y_offset, 140, 24, 'Exp. Points:')
    bitmap.font.color  =  Color.new(255, 255, 255, 255)
    bitmap.draw_text(180, y_offset, 290, 24, @pokemon.exp.to_s)

    if @pokemon.level < GameData::GrowthRate.max_level
      y_offset += line_height - 5
      exp_to_next = @pokemon.growth_rate.minimum_exp_for_level(@pokemon.level + 1) - @pokemon.exp
      bitmap.font.color = Color.new(180, 200, 230, 255)
      bitmap.font.size  =  14
      bitmap.draw_text(30, y_offset, 440, 22, "To Next Lv.: #{exp_to_next}")
    end
  end

  def draw_type_badge(bitmap, type, x, y, width, height)
    type_color = get_type_color(type)
    bitmap.fill_rect(x, y, width, height, type_color)
    bitmap.fill_rect(x + 1, y + 1, width - 2, height - 2, lighten_color(type_color, 30))

    bitmap.font.size = 13
    bitmap.font.bold = true
    bitmap.font.color = Color.new(255, 255, 255, 255)
    type_name = GameData::Type.get(type).name
    bitmap.draw_text(x, y + 3, width, height - 6, type_name, 1)
  end

  def get_type_color(type)
    case type
    when :NORMAL   then Color.new(168, 168, 120)
    when :FIRE     then Color.new(240, 128, 48)
    when :WATER    then Color.new(104, 144, 240)
    when :ELECTRIC then Color.new(248, 208, 48)
    when :GRASS    then Color.new(120, 200, 80)
    when :ICE      then Color.new(152, 216, 216)
    when :FIGHTING then Color.new(192, 48, 40)
    when :POISON   then Color.new(160, 64, 160)
    when :GROUND   then Color.new(224, 192, 104)
    when :FLYING   then Color.new(168, 144, 240)
    when :PSYCHIC  then Color.new(248, 88, 136)
    when :BUG      then Color.new(168, 184, 32)
    when :ROCK     then Color.new(184, 160, 56)
    when :GHOST    then Color.new(112, 88, 152)
    when :DRAGON   then Color.new(112, 56, 248)
    when :DARK     then Color.new(112, 88, 72)
    when :STEEL    then Color.new(184, 184, 208)
    when :FAIRY    then Color.new(238, 153, 172)
    else Color.new(120, 120, 120)
    end
  end

  def lighten_color(color, amount)
    Color.new(
      [color.red + amount, 255].min,
      [color.green + amount, 255].min,
      [color.blue + amount, 255].min,
      color.alpha
    )
  end

  def run
    loop do      Graphics.update
      Input.update

      if Input.trigger?(Input::LEFT)
        @page = (@page - 1) % 3
        update_display
      elsif Input.trigger?(Input::RIGHT)
        @page = (@page + 1) % 3
        update_display
      end

      if Input.trigger?(Input::BACK) || Input.trigger?(Input::USE)
        dispose
        return
      end
    end
  end

  def dispose
    @sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite && sprite.bitmap
      sprite.dispose if sprite
    end
    @viewport.dispose
  end
end

class ModernTradeConfirmation
  def initialize(my_pokemon, their_pokemon, my_name, their_name)
    @my_pokemon = my_pokemon
    @their_pokemon = their_pokemon
    @my_name = my_name
    @their_name  =  their_name
    @viewport  =  Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @animation_timer = 0
    create_ui
  end

  def create_ui

    @sprites[:bg]  =  Sprite.new(@viewport)
    @sprites[:bg].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    draw_background(@sprites[:bg].bitmap)

    create_title

    create_offer_panel(@my_pokemon, @my_name, 50, 120, true)

    create_center_indicator

    create_offer_panel(@their_pokemon, @their_name, Graphics.width / 2 + 50, 120, false)

    create_buttons
  end

  def create_title
    width = 500
    height = 70

    @sprites[:title_bg] = Sprite.new(@viewport)
    @sprites[:title_bg].bitmap = Bitmap.new(width, height)
    @sprites[:title_bg].x = (Graphics.width - width) / 2
    @sprites[:title_bg].y  =  30

    bitmap  =  @sprites[:title_bg].bitmap

    for i in 0...height
      r = 40 + (i / height.to_f * 60).to_i
      g  =  70 + (i / height.to_f * 50).to_i
      b = 140 - (i / height.to_f * 30).to_i
      bitmap.fill_rect(0, i, width, 1, Color.new(r, g, b, 255))
    end

    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(width, height)
    @sprites[:title].x  =  @sprites[:title_bg].x
    @sprites[:title].y = @sprites[:title_bg].y

    pbSetSystemFont(@sprites[:title].bitmap)
    @sprites[:title].bitmap.font.size = 32
    @sprites[:title].bitmap.font.bold = true
    @sprites[:title].bitmap.font.color = Color.new(255, 255, 255, 255)
    @sprites[:title].bitmap.draw_text(0, 15, width, 40, "Trade Confirmation", 1)
  end

  def create_offer_panel(pokemon, trainer_name, x, y, is_mine)
    panel_key = is_mine ? :my_panel : :their_panel

    width = (Graphics.width / 2) - 100
    height = 320

    @sprites[panel_key] = Sprite.new(@viewport)
    @sprites[panel_key].bitmap  =  Bitmap.new(width, height)
    @sprites[panel_key].x = x
    @sprites[panel_key].y  =  y

    bitmap = @sprites[panel_key].bitmap

    border_color = is_mine ? Color.new(100, 150, 255, 255) : Color.new(255, 150, 100, 255)
    bitmap.fill_rect(0, 0, width, height, border_color)
    bitmap.fill_rect(3, 3, width - 6, height - 6, Color.new(60, 60, 80, 255))

    for i in 0...height - 6
      shade = 50 + (i / (height - 6).to_f * 40).to_i
      bitmap.fill_rect(3, 3 + i, width - 6, 1, Color.new(shade, shade, shade + 20, 255))
    end

    pbSetSystemFont(bitmap)
    bitmap.font.size = 20
    bitmap.font.bold = true
    bitmap.font.color = is_mine ? Color.new(150, 200, 255, 255) : Color.new(255, 200, 150, 255)
    bitmap.draw_text(10, 10, width - 20, 28, trainer_name, 1)

    sprite_key = is_mine ? :my_sprite : :their_sprite
    @sprites[sprite_key]  =  Sprite.new(@viewport)
    @sprites[sprite_key].bitmap  =  Bitmap.new(128, 128)
    @sprites[sprite_key].x = x + (width - 128) / 2
    @sprites[sprite_key].y = y + 45

    begin
      icon = GameData::Species.icon_bitmap_from_pokemon(pokemon)
      if icon
        @sprites[sprite_key].bitmap.stretch_blt(
          Rect.new(0, 0, 128, 128),
          icon,
          Rect.new(0, 0, 64, 64)
        )
      end
    rescue => e
      puts "[TRADE CONFIRM] Error loading sprite: #{e.message}"
    end

    bitmap.font.size  =  24
    bitmap.font.bold = true
    max_name_width  =  width - 40
    pokemon_name = truncate_text_conf(bitmap, pokemon.name, max_name_width)

    if pokemon.shiny?
      bitmap.font.color  =  Color.new(255, 215, 0, 255)
      bitmap.draw_text(10, 180, width - 20, 30, pokemon_name, 1)

      name_display_width = bitmap.text_size(pokemon_name).width
      if name_display_width < max_name_width - 25
        bitmap.font.size = 18
        bitmap.draw_text(10 + name_display_width / 2 + width / 2 - 10, 182, 20, 26, "✦")
      end
    else
      bitmap.font.color = Color.new(255, 255, 255, 255)
      bitmap.draw_text(10, 180, width - 20, 30, pokemon_name, 1)
    end

    bitmap.font.size = 18
    bitmap.font.color = Color.new(200, 220, 255, 255)
    bitmap.draw_text(10, 215, width - 20, 24, "Level #{pokemon.level}", 1)

    y_offset = 245
    types = pokemon.types.uniq
    types.each_with_index do |type, i|
      type_x = (width - (types.length * 60 + (types.length - 1) * 10)) / 2 + i * 70
      draw_type_badge(bitmap, type, type_x, y_offset, 60, 20)
    end

    bitmap.font.size = 14
    bitmap.font.color = Color.new(180, 180, 200, 255)
    ot_name = pokemon.owner ? pokemon.owner.name : 'Unknown'
    ot_text = truncate_text_conf(bitmap, "OT: #{ot_name}", width - 20)
    bitmap.draw_text(10, 275, width - 20, 20, ot_text, 1)
  end

  def truncate_text_conf(bitmap, text, max_width)
    return text if bitmap.text_size(text).width <= max_width

    truncated = text
    while bitmap.text_size(truncated + '...').width > max_width && truncated.length > 1
      truncated  =  truncated[0...-1]
    end

    return truncated.length > 0 ? truncated + "..." : text[0] + "..."
  end

  def draw_type_badge(bitmap, type, x, y, width, height)
    type_color = get_type_color(type)

    bitmap.fill_rect(x, y, width, height, type_color)
    bitmap.fill_rect(x + 1, y + 1, width - 2, height - 2, lighten_color(type_color, 30))

    bitmap.font.size = 14
    bitmap.font.bold = true
    bitmap.font.color = Color.new(255, 255, 255, 255)
    type_name = GameData::Type.get(type).name
    bitmap.draw_text(x, y + 2, width, height - 4, type_name, 1)
  end

  def get_type_color(type)
    case type
    when :NORMAL   then Color.new(168, 168, 120)
    when :FIRE     then Color.new(240, 128, 48)
    when :WATER    then Color.new(104, 144, 240)
    when :ELECTRIC then Color.new(248, 208, 48)
    when :GRASS    then Color.new(120, 200, 80)
    when :ICE      then Color.new(152, 216, 216)
    when :FIGHTING then Color.new(192, 48, 40)
    when :POISON   then Color.new(160, 64, 160)
    when :GROUND   then Color.new(224, 192, 104)
    when :FLYING   then Color.new(168, 144, 240)
    when :PSYCHIC  then Color.new(248, 88, 136)
    when :BUG      then Color.new(168, 184, 32)
    when :ROCK     then Color.new(184, 160, 56)
    when :GHOST    then Color.new(112, 88, 152)
    when :DRAGON   then Color.new(112, 56, 248)
    when :DARK     then Color.new(112, 88, 72)
    when :STEEL    then Color.new(184, 184, 208)
    when :FAIRY    then Color.new(238, 153, 172)
    else Color.new(120, 120, 120)
    end
  end

  def lighten_color(color, amount)
    Color.new(
      [color.red + amount, 255].min,
      [color.green + amount, 255].min,
      [color.blue + amount, 255].min,
      color.alpha
    )
  end

  def create_center_indicator

    @sprites[:arrow] = Sprite.new(@viewport)
    @sprites[:arrow].bitmap = Bitmap.new(80, 80)
    @sprites[:arrow].x = (Graphics.width - 80) / 2
    @sprites[:arrow].y = 240

    draw_arrow(@sprites[:arrow].bitmap)
  end

  def draw_arrow(bitmap)
    bitmap.clear

    pbSetSystemFont(bitmap)
    bitmap.font.size  =  48
    bitmap.font.bold = true

    pulse = (Math.sin(@animation_timer / 15.0) * 100 + 155).to_i
    bitmap.font.color = Color.new(pulse, pulse, 255, 255)

    bitmap.draw_text(0, 15, 80, 50, "⇄", 1)
  end

  def create_buttons
    @sprites[:confirm_btn] = Sprite.new(@viewport)
    @sprites[:confirm_btn].bitmap = Bitmap.new(180, 50)
    @sprites[:confirm_btn].x = Graphics.width / 2 - 200
    @sprites[:confirm_btn].y = Graphics.height - 80

    draw_button(@sprites[:confirm_btn].bitmap, "CONFIRM TRADE", Color.new(80, 180, 100, 255))

    @sprites[:cancel_btn] = Sprite.new(@viewport)
    @sprites[:cancel_btn].bitmap = Bitmap.new(180, 50)
    @sprites[:cancel_btn].x  =  Graphics.width / 2 + 20
    @sprites[:cancel_btn].y = Graphics.height - 80

    draw_button(@sprites[:cancel_btn].bitmap, "CANCEL", Color.new(200, 80, 80, 255))

    @sprites[:instructions] = Sprite.new(@viewport)
    @sprites[:instructions].bitmap = Bitmap.new(500, 30)
    @sprites[:instructions].x = (Graphics.width - 500) / 2
    @sprites[:instructions].y = Graphics.height - 120

    pbSetSystemFont(@sprites[:instructions].bitmap)
    @sprites[:instructions].bitmap.font.size = 13
    @sprites[:instructions].bitmap.font.color = Color.new(200, 200, 220, 255)
    @sprites[:instructions].bitmap.draw_text(0, 0, 500, 30, "Up/Down: Select  X: Summary  Left/Right: Choose  Enter: Confirm", 1)
  end

  def draw_button(bitmap, text, color)
    width = bitmap.width
    height = bitmap.height

    bitmap.fill_rect(0, 0, width, height, darken_color(color, 40))
    bitmap.fill_rect(2, 2, width - 4, height - 4, color)

    for i in 0...height - 4
      shade_factor = 1.0 - (i / (height - 4).to_f * 0.3)
      bitmap.fill_rect(2, 2 + i, width - 4, 1,
        Color.new(
          (color.red * shade_factor).to_i,
          (color.green * shade_factor).to_i,
          (color.blue * shade_factor).to_i,
          255
        )
      )
    end

    pbSetSystemFont(bitmap)
    bitmap.font.size = 20
    bitmap.font.bold = true
    bitmap.font.color  =  Color.new(255, 255, 255, 255)
    bitmap.draw_text(0, 10, width, 30, text, 1)
  end

  def darken_color(color, amount)
    Color.new(
      [color.red - amount, 0].max,
      [color.green - amount, 0].max,
      [color.blue - amount, 0].max,
      color.alpha
    )
  end

  def draw_background(bitmap)
    for i in 0...Graphics.height
      r = 15 + (i / Graphics.height.to_f * 30).to_i
      g = 25 + (i / Graphics.height.to_f * 40).to_i
      b = 45 + (i / Graphics.height.to_f * 70).to_i
      bitmap.fill_rect(0, i, Graphics.width, 1, Color.new(r, g, b, 255))
    end
  end

  def run
    @selection = 0
    @pokemon_selection = 0

    loop do      Graphics.update
      Input.update

      @animation_timer += 1
      draw_arrow(@sprites[:arrow].bitmap) if @animation_timer % 5 == 0

      if Input.trigger?(Input::UP)
        @pokemon_selection = 0
      elsif Input.trigger?(Input::DOWN)
        @pokemon_selection = 1
      end

      if Input.trigger?(Input::JUMPUP)
        if @pokemon_selection == 0 && @my_pokemon
          summary = PokemonTradeSummary.new(@my_pokemon, @my_name)
          summary.run
        elsif @pokemon_selection == 1 && @their_pokemon

          if @their_pokemon.is_a?(Hash)

            pbMessage(_INTL("Partner's {1} - Level {2}", @their_pokemon[:name] || @their_pokemon["name"], @their_pokemon[:level] || @their_pokemon["level"]))
          else
            summary = PokemonTradeSummary.new(@their_pokemon, @their_name)
            summary.run
          end
        end
      end

      old_selection = @selection

      if Input.trigger?(Input::LEFT)
        @selection = 0
      elsif Input.trigger?(Input::RIGHT)
        @selection = 1
      end

      if @selection != old_selection
        update_button_highlights
      end

      if Input.trigger?(Input::USE)
        if @selection == 0
          dispose
          return true
        else
          dispose
          return false
        end
      end

      if Input.trigger?(Input::BACK)
        dispose
        return false
      end
    end
  end

  def update_button_highlights

    if @selection == 0
      @sprites[:confirm_btn].bitmap.clear
      draw_button(@sprites[:confirm_btn].bitmap, "CONFIRM TRADE", Color.new(100, 220, 120, 255))

      @sprites[:cancel_btn].bitmap.clear
      draw_button(@sprites[:cancel_btn].bitmap, "CANCEL", Color.new(200, 80, 80, 255))
    else
      @sprites[:confirm_btn].bitmap.clear
      draw_button(@sprites[:confirm_btn].bitmap, "CONFIRM TRADE", Color.new(80, 180, 100, 255))

      @sprites[:cancel_btn].bitmap.clear
      draw_button(@sprites[:cancel_btn].bitmap, "CANCEL", Color.new(240, 100, 100, 255))
    end
  end

  def dispose
    @sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite && sprite.bitmap
      sprite.dispose if sprite
    end
    @viewport.dispose
  end
end

class ModernMultiplayerTradeManager
  attr_reader :current_trade_state
  attr_reader :trade_session_id

  def initialize
    @current_trade_state  =  nil
    @trade_session_id = nil
    @my_offer = nil
    @their_offer = nil
    @trade_partner_id = nil
    @trade_partner_name  =  nil
    @trade_confirmed_by_me = false
    @trade_confirmed_by_them = false
    @pokemon_locked = nil
    @trade_timeout_timer  =  0
  end

  def initiate_trade(target_player_id, target_username)

    if @current_trade_state
      choice = pbMessage(_INTL("You're already in a trade! Force reset?"),
                        [_INTL("Yes"), _INTL("No")], 2)
      if choice == 0
        puts "[TRADE] Force resetting stuck trade state"
        reset_trade
      else
        return false
      end
    end

    if $player.party.length == 0
      pbMessage(_INTL("You have no Pokemon to trade!"))
      return false
    end

    if target_player_id.nil?
      pbMessage(_INTL("Error: Target player ID is nil. Player may be offline."))
      puts "[TRADE ERROR] target_player_id is nil for #{target_username}"
      return false
    end

    puts "[TRADE INIT] Initiating trade with #{target_username} (ID: #{target_player_id})"

    selector = ModernPokemonSelector.new($player.party, "Select a Pokemon to Offer")
    selected_pokemon  =  selector.run

    if selected_pokemon.nil?
      pbMessage(_INTL("Trade cancelled."))
      return false
    end

    @pokemon_locked = selected_pokemon
    @my_offer = selected_pokemon

    @trade_session_id = "trade_#{$multiplayer_client.client_id}_#{Time.now.to_i}_#{rand(10000)}"
    @trade_partner_id = target_player_id
    @trade_partner_name = target_username

    if pbMultiplayerConnected?
      pokemon_data = serialize_pokemon(selected_pokemon)

      puts "[TRADE SEND] Sending trade_offer_v2 to server: target_id=#{target_player_id}, session=#{@trade_session_id}"

      $multiplayer_client.send_json_message({
        type: "trade_offer_v2",
        data: {
          target_id: target_player_id,
          trade_session_id: @trade_session_id,
          pokemon_data: pokemon_data
        }
      })

      @current_trade_state = TradeState::WAITING_FOR_RESPONSE
      pbMessage(_INTL('Trade offer sent to {1}!', target_username))
      pbMessage(_INTL("Waiting for {1} to respond...", target_username))

      @trade_timeout_timer = Time.now.to_i + 120

      return true
    else
      unlock_pokemon
      pbMessage(_INTL("Not connected to server!"))
      return false
    end
  end

  def receive_trade_offer(from_player_id, from_username, trade_session_id, pokemon_data)
    puts "[TRADE V2] Received trade offer from #{from_username}"

    if @current_trade_state
      puts "[TRADE V2] Already in trade, auto-declining"
      send_trade_decline(from_player_id, trade_session_id, "busy")
      return
    end

    @their_offer  =  pokemon_data
    @trade_session_id = trade_session_id
    @trade_partner_id = from_player_id
    @trade_partner_name = from_username

    species = pokemon_data[:species] || pokemon_data['species']
    level = pokemon_data[:level] || pokemon_data['level']
    pbMultiplayerNotify("TRADE REQUEST: #{from_username} offers #{species} Lv.#{level}! Press F8 to respond", 10.0)

    @current_trade_state = TradeState::WAITING_FOR_OFFER
  end

  def accept_trade_offer
    return false unless @current_trade_state == TradeState::WAITING_FOR_OFFER

    if $player.party.length == 0
      pbMessage(_INTL("You have no Pokemon to trade!"))
      send_trade_decline(@trade_partner_id, @trade_session_id, 'no_pokemon')
      reset_trade
      return false
    end

    selector = ModernPokemonSelector.new($player.party, "Select Pokemon to Trade")
    selected_pokemon  =  selector.run

    if selected_pokemon.nil?
      pbMessage(_INTL("Trade cancelled."))
      send_trade_decline(@trade_partner_id, @trade_session_id, "cancelled")
      reset_trade
      return false
    end

    @pokemon_locked  =  selected_pokemon
    @my_offer = selected_pokemon

    pokemon_data = serialize_pokemon(selected_pokemon)

    $multiplayer_client.send_json_message({
      type: "trade_counter_offer_v2",
      data: {
        target_id: @trade_partner_id,
        trade_session_id: @trade_session_id,
        pokemon_data: pokemon_data
      }
    })

    @current_trade_state  =  TradeState::WAITING_FOR_RESPONSE
    pbMessage(_INTL('Trade offer sent to {1}!', @trade_partner_name))
    pbMessage(_INTL("Waiting for {1} to review your offer...", @trade_partner_name))

    return true
  end

  def receive_counter_offer(pokemon_data)
    puts '[TRADE V2] Received counter-offer'

    @their_offer = pokemon_data
    @current_trade_state = TradeState::REVIEWING_TRADE

    species = pokemon_data[:species] || pokemon_data['species']
    level = pokemon_data[:level] || pokemon_data['level']
    pbMessage(_INTL("{1} has selected their Pokemon!", @trade_partner_name))
    pbMessage(_INTL("They are offering: {1} (Lv. {2})", species, level))
    pbMessage(_INTL("Review the trade carefully. Press X to view full summary!"))

    show_trade_confirmation
  end

  def show_trade_confirmation
    my_pkmn = @my_offer
    their_pkmn_data = @their_offer

    their_pkmn  =  deserialize_pokemon(their_pkmn_data)

    confirmation = ModernTradeConfirmation.new(
      my_pkmn,
      their_pkmn,
      $player.name,
      @trade_partner_name
    )

    result = confirmation.run

    if result

      send_trade_confirm
    else

      if pbConfirmMessage(_INTL("Do you want to select a different Pokemon?"))
        reselect_pokemon
      else
        send_trade_decline(@trade_partner_id, @trade_session_id, 'declined')
        reset_trade
        pbMessage(_INTL("Trade cancelled."))
      end
    end
  end

  def reselect_pokemon
    unlock_pokemon

    selector = ModernPokemonSelector.new($player.party, "Select a Different Pokemon")
    selected_pokemon = selector.run

    if selected_pokemon.nil?
      send_trade_decline(@trade_partner_id, @trade_session_id, "cancelled")
      reset_trade
      pbMessage(_INTL("Trade cancelled."))
      return
    end

    @pokemon_locked  =  selected_pokemon
    @my_offer = selected_pokemon
    pokemon_data = serialize_pokemon(selected_pokemon)

    $multiplayer_client.send_json_message({
      type: "trade_change_offer_v2",
      data: {
        target_id: @trade_partner_id,
        trade_session_id: @trade_session_id,
        pokemon_data: pokemon_data
      }
    })

    @current_trade_state = TradeState::WAITING_FOR_RESPONSE
    pbMessage(_INTL("Sent new offer. Waiting for response..."))
  end

  def send_trade_confirm
    @trade_confirmed_by_me = true

    $multiplayer_client.send_json_message({
      type: "trade_confirm_v2",
      data: {
        target_id: @trade_partner_id,
        trade_session_id: @trade_session_id
      }
    })

    @current_trade_state = TradeState::WAITING_FOR_RESPONSE
    pbMessage(_INTL("Waiting for {1} to confirm...", @trade_partner_name))
  end

  def receive_trade_confirm
    @trade_confirmed_by_them = true

    if @trade_confirmed_by_me && @trade_confirmed_by_them

      pbMessage(_INTL("Both players confirmed! Executing trade..."))
      @current_trade_state = TradeState::TRADE_ACCEPTED
    elsif !@trade_confirmed_by_me

      pbMessage(_INTL("{1} confirmed the trade!", @trade_partner_name))
      show_trade_confirmation
    end
  end

  def execute_trade_server_authorized(my_pokemon_id, their_pokemon_data)
    puts "[TRADE V2] Executing server-authorized trade"

    pbMessage(_INTL("Both players confirmed! Executing trade..."))
    pbMessage(_INTL("The trade is being finalized by the server..."))

    my_pokemon  =  nil
    my_pokemon_index = nil

    $player.party.each_with_index do |pkmn, i|
      if pkmn && pkmn.personalID == my_pokemon_id
        my_pokemon  =  pkmn
        my_pokemon_index = i
        break
      end
    end

    unless my_pokemon
      puts "[TRADE V2] ERROR: Could not find Pokemon with ID #{my_pokemon_id}"
      pbMessage(_INTL("ERROR: Trade failed - Pokemon not found!"))
      pbMessage(_INTL('Please report this issue. Your Pokemon is safe.'))
      reset_trade
      return
    end

    their_pokemon = deserialize_pokemon(their_pokemon_data)

    begin
      pbStartMultiplayerTrade(
        my_pokemon,
        their_pokemon,
        $player.name,
        @trade_partner_name
      )
    rescue => e
      puts "[TRADE V2] Animation error: #{e.message}"

    end

    $player.party.delete_at(my_pokemon_index)
    $player.party << their_pokemon

    pbMessage(_INTL("Trade completed successfully!"))
    pbMessage(_INTL("You traded {1} for {2}'s {3}!", my_pokemon.name, @trade_partner_name, their_pokemon.name))

    @current_trade_state = TradeState::TRADE_COMPLETE

    $multiplayer_client.send_json_message({
      type: "trade_complete_ack_v2",
      data: {
        trade_session_id: @trade_session_id
      }
    })

    reset_trade
  end

  def receive_trade_decline(reason)

    reset_trade

    case reason
    when "busy"
      pbMessage(_INTL("Trade partner is already in another trade."))
    when "cancelled"
      pbMessage(_INTL("Trade partner cancelled the trade."))
    when 'declined'
      pbMessage(_INTL("Trade partner declined the trade."))
    when "timeout"
      pbMessage(_INTL("Trade timed out - no response received."))
    when "disconnected"
      pbMessage(_INTL("Trade partner disconnected."))
    when "player_not_found"
      pbMessage(_INTL("Trade partner could not be found."))
    else
      pbMessage(_INTL('Trade was cancelled.'))
    end
  end

  def receive_offer_change(new_pokemon_data)
    @their_offer  =  new_pokemon_data
    @trade_confirmed_by_them = false
    @trade_confirmed_by_me = false

    species  =  new_pokemon_data[:species] || new_pokemon_data['species']
    level  =  new_pokemon_data[:level] || new_pokemon_data['level']

    pbMessage(_INTL("{1} changed their offer!", @trade_partner_name))
    pbMessage(_INTL("They are now offering: {1} (Lv. {2})", species, level))

    @current_trade_state = TradeState::REVIEWING_TRADE
    show_trade_confirmation
  end

  def handle_partner_disconnect
    return unless @current_trade_state

    unlock_pokemon
    pbMessage(_INTL("Trade partner disconnected. Trade cancelled."))
    reset_trade
  end

  def send_trade_decline(target_id, session_id, reason)
    return unless pbMultiplayerConnected?

    $multiplayer_client.send_json_message({
      type: "trade_decline_v2",
      data: {
        target_id: target_id,
        trade_session_id: session_id,
        reason: reason
      }
    })
  end

  def unlock_pokemon
    @pokemon_locked = nil
  end

  def reset_trade
    unlock_pokemon
    @current_trade_state = nil
    @trade_session_id = nil
    @my_offer  =  nil
    @their_offer = nil
    @trade_partner_id = nil
    @trade_partner_name = nil
    @trade_confirmed_by_me = false
    @trade_confirmed_by_them  =  false
    @trade_timeout_timer = 0
  end

  def update
    return unless @current_trade_state

    if @trade_timeout_timer > 0 && Time.now.to_i > @trade_timeout_timer
      puts '[TRADE V2] Trade timed out'
      send_trade_decline(@trade_partner_id, @trade_session_id, "timeout")
      unlock_pokemon
      pbMessage(_INTL("Trade timed out."))
      reset_trade
    end
  end

  def pokemon_locked?(pokemon)
    return @pokemon_locked == pokemon
  end

  def serialize_pokemon(pokemon)
    {
      species: pokemon.species,
      level: pokemon.level,
      name: pokemon.name,
      form: pokemon.form,
      gender: pokemon.gender,
      shiny: pokemon.shiny?,
      personalID: pokemon.personalID,
      exp: pokemon.exp,
      ability: pokemon.ability_id,
      moves: pokemon.moves.map { |m| {id: m.id, pp: m.pp, ppup: m.ppup} },
      ivs: {
        hp: pokemon.iv[:HP],
        atk: pokemon.iv[:ATTACK],
        def: pokemon.iv[:DEFENSE],
        spa: pokemon.iv[:SPECIAL_ATTACK],
        spd: pokemon.iv[:SPECIAL_DEFENSE],
        spe: pokemon.iv[:SPEED]
      },
      evs: {
        hp: pokemon.ev[:HP],
        atk: pokemon.ev[:ATTACK],
        def: pokemon.ev[:DEFENSE],
        spa: pokemon.ev[:SPECIAL_ATTACK],
        spd: pokemon.ev[:SPECIAL_DEFENSE],
        spe: pokemon.ev[:SPEED]
      },
      happiness: pokemon.happiness,
      nature: pokemon.nature_id,
      item: pokemon.item_id,
      hp: pokemon.hp,
      status: pokemon.status,
      ot_name: pokemon.owner.name,
      ot_id: pokemon.owner.id,
      ot_gender: pokemon.owner.gender,
      ot_language: pokemon.owner.language
    }
  end

  def deserialize_pokemon(data)
    species = data[:species] || data['species']
    species = species.to_sym if species.is_a?(String)

    ability = data[:ability] || data['ability']
    ability = ability.to_sym if ability && ability.is_a?(String)

    pokemon = Pokemon.new(species, data[:level] || data['level'])

    personal_id = data[:personalID] || data['personalID']
    pokemon.instance_variable_set(:@personal_id, personal_id) if personal_id

    pokemon.name = data[:name] || data['name'] if data[:name] || data['name']
    pokemon.form = data[:form] || data['form'] if data[:form] || data['form']
    pokemon.gender = data[:gender] || data['gender'] if data[:gender] || data['gender']
    pokemon.exp = data[:exp] || data['exp'] if data[:exp] || data['exp']
    pokemon.ability = ability if ability

    ivs_data = data[:ivs] || data['ivs']
    if ivs_data
      pokemon.iv[:HP] = (ivs_data[:hp] || ivs_data['hp'] || 0).to_i
      pokemon.iv[:ATTACK] = (ivs_data[:atk] || ivs_data['atk'] || 0).to_i
      pokemon.iv[:DEFENSE]  =  (ivs_data[:def] || ivs_data['def'] || 0).to_i
      pokemon.iv[:SPECIAL_ATTACK]  =  (ivs_data[:spa] || ivs_data['spa'] || 0).to_i
      pokemon.iv[:SPECIAL_DEFENSE] = (ivs_data[:spd] || ivs_data['spd'] || 0).to_i
      pokemon.iv[:SPEED] = (ivs_data[:spe] || ivs_data['spe'] || 0).to_i
    end

    evs_data = data[:evs] || data['evs']
    if evs_data
      pokemon.ev[:HP] = (evs_data[:hp] || evs_data['hp'] || 0).to_i
      pokemon.ev[:ATTACK] = (evs_data[:atk] || evs_data['atk'] || 0).to_i
      pokemon.ev[:DEFENSE] = (evs_data[:def] || evs_data['def'] || 0).to_i
      pokemon.ev[:SPECIAL_ATTACK] = (evs_data[:spa] || evs_data['spa'] || 0).to_i
      pokemon.ev[:SPECIAL_DEFENSE] = (evs_data[:spd] || evs_data['spd'] || 0).to_i
      pokemon.ev[:SPEED] = (evs_data[:spe] || evs_data['spe'] || 0).to_i
    end

    moves_data = data[:moves] || data['moves']
    if moves_data
      pokemon.moves.clear
      moves_data.each do |move_data|
        move_id = move_data[:id] || move_data['id']
        move_id = move_id.to_sym if move_id.is_a?(String)

        move = Pokemon::Move.new(move_id)
        move.pp = (move_data[:pp] || move_data['pp']).to_i if move_data[:pp] || move_data['pp']
        move.ppup  =  (move_data[:ppup] || move_data['ppup']).to_i if move_data[:ppup] || move_data['ppup']
        pokemon.moves << move
      end
    end

    pokemon.happiness = data[:happiness] if data[:happiness]

    nature = data[:nature]
    nature = nature.to_sym if nature && nature.is_a?(String)
    pokemon.nature = nature if nature

    item = data[:item]
    item = item.to_sym if item && item.is_a?(String) && !item.empty?
    pokemon.item = item if item && !item.empty?

    pokemon.hp  =  data[:hp] if data[:hp]

    status = data[:status] || data['status']
    if status
      if status.is_a?(Integer)
        status_symbols = [:NONE, :SLEEP, :POISON, :BURN, :PARALYSIS, :FROZEN]
        pokemon.status = status_symbols[status] if status >= 0 && status < status_symbols.length
      elsif status.is_a?(String)
        pokemon.status  =  status.to_sym
      else
        pokemon.status = status
      end
    end

    ot_name = data[:ot_name] || data['ot_name']
    ot_id = data[:ot_id] || data['ot_id']
    ot_gender = data[:ot_gender] || data['ot_gender'] || 0
    ot_language = data[:ot_language] || data['ot_language'] || 0
    if ot_name && ot_id
      pokemon.owner = Pokemon::Owner.new(ot_id, ot_name, ot_gender, ot_language)
    end

    pokemon.calc_stats
    return pokemon
  end
end

$modern_trade_manager = nil

def pbModernTradeManager
  $modern_trade_manager ||= ModernMultiplayerTradeManager.new
  return $modern_trade_manager
end

class Scene_Map
  alias trade_v2_original_update update

  def update
    if pbIsMultiplayerMode? && pbMultiplayerConnected?
      pbModernTradeManager.update
    end

    trade_v2_original_update
  end
end

puts "[MULTIPLAYER] Modern Trade System V2 loaded - AAA Quality UI with secure transactions"
