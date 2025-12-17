class MultiplayerStarterSelection
  STARTERS = [
    {
      species: :BULBASAUR,
      name: "Bulbasaur",
      type: "Grass/Poison",
      description: 'A balanced starter with good defensive stats. Great for beginners!'
    },
    {
      species: :CHARMANDER,
      name: 'Charmander',
      type: "Fire",
      description: "An offensive powerhouse that evolves into a mighty dragon. High risk, high reward!"
    },
    {
      species: :SQUIRTLE,
      name: "Squirtle",
      type: 'Water',
      description: "A defensive tank with great survivability. Reliable and sturdy!"
    }
  ]

  def initialize
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @sprites = {}
    @selection = 0
    create_ui
  end

  def create_ui

    total_ui_height = 365
    vertical_offset = (Graphics.height - total_ui_height) / 2

    @sprites[:bg]  =  Sprite.new(@viewport)
    @sprites[:bg].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites[:bg].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(30, 30, 50, 255))

    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(Graphics.width, 50)
    @sprites[:title].y = vertical_offset
    pbSetSystemFont(@sprites[:title].bitmap)
    @sprites[:title].bitmap.font.size = 28
    @sprites[:title].bitmap.font.color = Color.new(255, 255, 255, 255)
    @sprites[:title].bitmap.draw_text(0, 0, Graphics.width, 50, "Choose Your Starter!", 1)

    @sprites[:pokemon_display]  =  Sprite.new(@viewport)
    @sprites[:pokemon_display].bitmap = Bitmap.new(Graphics.width, 200)
    @sprites[:pokemon_display].y = vertical_offset + 50

    @sprites[:info] = Sprite.new(@viewport)
    @sprites[:info].bitmap = Bitmap.new(Graphics.width - 40, 80)
    @sprites[:info].x = 20
    @sprites[:info].y = vertical_offset + 50 + 200 + 10

    @sprites[:instructions] = Sprite.new(@viewport)
    @sprites[:instructions].bitmap = Bitmap.new(Graphics.width, 25)
    @sprites[:instructions].y = vertical_offset + 50 + 200 + 10 + 80 + 10
    pbSetSystemFont(@sprites[:instructions].bitmap)
    @sprites[:instructions].bitmap.font.size  =  16
    @sprites[:instructions].bitmap.font.color = Color.new(200, 200, 200, 255)
    @sprites[:instructions].bitmap.draw_text(0, 0, Graphics.width, 25, "Arrow Keys to navigate, ENTER to select", 1)

    update_display
  end

  def update_display

    @sprites[:pokemon_display].bitmap.clear

    STARTERS.each_with_index do |starter, index|
      x = 20 + (index * ((Graphics.width - 40) / 3))
      y = 10
      width = (Graphics.width - 80) / 3
      height = 180

      if index == @selection
        border_color = Color.new(255, 220, 100, 255)
        bg_color = Color.new(100, 100, 120, 255)
      else
        border_color = Color.new(150, 150, 150, 255)
        bg_color = Color.new(60, 60, 80, 255)
      end

      @sprites[:pokemon_display].bitmap.fill_rect(x, y, width, height, border_color)
      @sprites[:pokemon_display].bitmap.fill_rect(x + 3, y + 3, width - 6, height - 6, bg_color)

      pbSetSystemFont(@sprites[:pokemon_display].bitmap)
      @sprites[:pokemon_display].bitmap.font.size = 20
      @sprites[:pokemon_display].bitmap.font.color  =  Color.new(255, 255, 255, 255)
      @sprites[:pokemon_display].bitmap.draw_text(x + 10, y + 8, width - 20, 28, starter[:name], 1)

      @sprites[:pokemon_display].bitmap.font.size = 14
      @sprites[:pokemon_display].bitmap.font.color  =  Color.new(200, 200, 200, 255)
      @sprites[:pokemon_display].bitmap.draw_text(x + 10, y + 32, width - 20, 20, starter[:type], 1)

      begin

        anim_bitmap = GameData::Species.sprite_bitmap(starter[:species], 0, 0, false, false, false, false)

        if anim_bitmap && anim_bitmap.bitmap
          pkmn_bitmap = anim_bitmap.bitmap

          sprite_x = x + (width - pkmn_bitmap.width) / 2
          sprite_y  =  y + 55

          src_rect = Rect.new(0, 0, pkmn_bitmap.width, pkmn_bitmap.height)
          @sprites[:pokemon_display].bitmap.blt(sprite_x, sprite_y, pkmn_bitmap, src_rect)

          anim_bitmap.dispose
        end
      rescue => e

        icon_size = 80
        icon_x = x + (width - icon_size) / 2
        icon_y = y + 60
        @sprites[:pokemon_display].bitmap.font.size  =  48
        @sprites[:pokemon_display].bitmap.font.color = Color.new(150, 150, 170, 255)
        @sprites[:pokemon_display].bitmap.draw_text(icon_x, icon_y, icon_size, 60, "?", 1)
        puts "Failed to load sprite for #{starter[:species]}: #{e.message}"
      end
    end

    @sprites[:info].bitmap.clear
    starter = STARTERS[@selection]

    @sprites[:info].bitmap.fill_rect(0, 0, @sprites[:info].bitmap.width, @sprites[:info].bitmap.height, Color.new(80, 80, 100, 255))
    @sprites[:info].bitmap.fill_rect(3, 3, @sprites[:info].bitmap.width - 6, @sprites[:info].bitmap.height - 6, Color.new(40, 40, 60, 255))

    pbSetSystemFont(@sprites[:info].bitmap)
    @sprites[:info].bitmap.font.size = 18
    @sprites[:info].bitmap.font.color = Color.new(255, 255, 255, 255)

    words = starter[:description].split(' ')
    line = ""
    y  =  12
    line_height  =  24

    words.each do |word|
      test_line  =  line.empty? ? word : "#{line} #{word}"

      if test_line.length * 11 < @sprites[:info].bitmap.width - 30
        line = test_line
      else
        @sprites[:info].bitmap.draw_text(15, y, @sprites[:info].bitmap.width - 30, line_height, line)
        line  =  word
        y += line_height
      end
    end
    @sprites[:info].bitmap.draw_text(15, y, @sprites[:info].bitmap.width - 30, line_height, line)
  end

  def run

    if $GetKeyState
      loop do        all_released = true
        (0x25..0x28).each do |key|
          if ($GetKeyState.call(key) & 0x8000) != 0
            all_released = false
            break
          end
        end
        break if all_released
        Graphics.update
      end
    end

    keys_pressed = {}

    loop do
      if pbIsMultiplayerMode? && !pbMultiplayerConnected?
        puts "Lost connection during starter selection - returning nil"
        dispose
        return nil
      end

      Graphics.update
      Input.update

      if $GetKeyState && ($GetKeyState.call(0x25) & 0x8000) != 0
        unless keys_pressed[0x25]
          @selection  =  (@selection - 1) % STARTERS.size
          update_display
          keys_pressed[0x25] = true
        end
      else
        keys_pressed[0x25] = false if $GetKeyState
      end

      if $GetKeyState && ($GetKeyState.call(0x27) & 0x8000) != 0
        unless keys_pressed[0x27]
          @selection = (@selection + 1) % STARTERS.size
          update_display
          keys_pressed[0x27] = true
        end
      else
        keys_pressed[0x27] = false if $GetKeyState
      end

      if $GetKeyState && ($GetKeyState.call(0x0D) & 0x8000) != 0
        unless keys_pressed[0x0D]
          keys_pressed[0x0D] = true

          starter = STARTERS[@selection]
          if pbConfirmMessage(_INTL("Choose {1}?", starter[:name]))
            dispose
            return starter[:species]
          end
        end
      else
        keys_pressed[0x0D]  =  false if $GetKeyState
      end

      if $GetKeyState && ($GetKeyState.call(0x1B) & 0x8000) != 0
        unless keys_pressed[0x1B]
          keys_pressed[0x1B] = true
          dispose
          return nil
        end
      else
        keys_pressed[0x1B] = false if $GetKeyState
      end
    end
  end

  def dispose
    @sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite.bitmap
      sprite.dispose
    end
    @viewport.dispose
  end
end

def pbMultiplayerChooseStarter
  selection = MultiplayerStarterSelection.new
  chosen_species = selection.run
  return chosen_species
end
