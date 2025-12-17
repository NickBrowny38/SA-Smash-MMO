class MMOTitleScreen_Scene
  def initialize
    @sprites = {}
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
  end

  def pbStartScene(commands, show_continue, trainer, frame_count, map_id)
    @commands = commands
    @show_continue = show_continue

    create_background
    create_title_logo
    create_menu_panel
    create_version_info

    15.times do |i|
      @sprites.each_value { |sprite| sprite.opacity = (i + 1) * 17 if sprite.respond_to?(:opacity) }
      Graphics.update
    end

    pbSEPlay("GUI menu open") if commands && commands.length > 0
  end

  def create_background

    @sprites['bg'] = Sprite.new(@viewport)
    @sprites["bg"].bitmap = Bitmap.new(Graphics.width, Graphics.height)

    bitmap = @sprites["bg"].bitmap
    (0...Graphics.height).each do |y|
      progress  =  y.to_f / Graphics.height
      color = Color.new(
        (10 + progress * 5).to_i,
        (15 + progress * 10).to_i,
        (35 + progress * 15).to_i,
        255
      )
      bitmap.fill_rect(0, y, Graphics.width, 1, color)
    end

    grid_color = Color.new(255, 255, 255, 15)
    (0...Graphics.width).step(40) do |x|
      bitmap.fill_rect(x, 0, 1, Graphics.height, grid_color)
    end
    (0...Graphics.height).step(40) do |y|
      bitmap.fill_rect(0, y, Graphics.width, 1, grid_color)
    end
  end

  def create_title_logo

    @sprites["title"] = Sprite.new(@viewport)
    @sprites["title"].bitmap = Bitmap.new(600, 150)
    @sprites["title"].x = (Graphics.width - 600) / 2
    @sprites["title"].y = 80
    @sprites["title"].z = 1

    bitmap = @sprites["title"].bitmap

    title_text = "POKEMON ESSENTIALS"
    subtitle_text = 'MULTIPLAYER EDITION'

    [4, 3, 2, 1].each do |offset|
      opacity  =  60 - (offset * 10)
      pbDrawTextPositions(bitmap, [
        [title_text, bitmap.width / 2 + offset, 25 + offset, 2,
         Color.new(100, 150, 255, opacity), Color.new(0, 0, 0, 0), true]
      ])
    end

    pbDrawTextPositions(bitmap, [
      [title_text, bitmap.width / 2, 25, 2,
       Color.new(255, 255, 255), Color.new(50, 100, 200, 200), true]
    ])

    pbDrawTextPositions(bitmap, [
      [subtitle_text, bitmap.width / 2, 85, 2,
       Color.new(150, 200, 255), Color.new(0, 0, 0, 120), true]
    ])
  end

  def create_menu_panel

    panel_width = 350
    panel_height = 320
    panel_x = (Graphics.width - panel_width) / 2
    panel_y = 280

    @sprites["menu_panel"] = Sprite.new(@viewport)
    @sprites["menu_panel"].bitmap = Bitmap.new(panel_width, panel_height)
    @sprites["menu_panel"].x = panel_x
    @sprites['menu_panel'].y = panel_y
    @sprites["menu_panel"].z = 2

    bitmap  =  @sprites["menu_panel"].bitmap

    (0...panel_height).each do |y|
      progress = y.to_f / panel_height
      color = Color.new(
        (15 * (1 - progress) + 10 * progress).to_i,
        (25 * (1 - progress) + 15 * progress).to_i,
        (50 * (1 - progress) + 30 * progress).to_i,
        210
      )
      bitmap.fill_rect(0, y, panel_width, 1, color)
    end

    border_color = Color.new(120, 180, 255, 200)
    bitmap.fill_rect(0, 0, panel_width, 3, border_color)
    bitmap.fill_rect(0, panel_height - 3, panel_width, 3, border_color)
    bitmap.fill_rect(0, 0, 3, panel_height, border_color)
    bitmap.fill_rect(panel_width - 3, 0, 3, panel_height, border_color)

    @menu_panel_x = panel_x
    @menu_panel_y = panel_y
    @menu_panel_width = panel_width
  end

  def create_version_info

    @sprites["version"] = Sprite.new(@viewport)
    @sprites["version"].bitmap = Bitmap.new(Graphics.width, 40)
    @sprites["version"].y = Graphics.height - 50
    @sprites["version"].z = 1

    bitmap = @sprites['version'].bitmap
    version_text = "v21.1 FRLG | Multiplayer Enhanced"
    copyright_text = '© Pokemon Essentials'

    pbDrawTextPositions(bitmap, [
      [version_text, Graphics.width / 2, 0, 2,
       Color.new(180, 180, 200), Color.new(0, 0, 0, 100), true],
      [copyright_text, Graphics.width / 2, 20, 2,
       Color.new(150, 150, 170), Color.new(0, 0, 0, 80), true]
    ])
  end

  def pbStartScene2

    @current_index  =  0
    @menu_items = []

    return unless @commands && @commands.length > 0

    item_height = 55
    start_y = 30

    @commands.each_with_index do |command, i|
      sprite = Sprite.new(@viewport)
      sprite.bitmap  =  Bitmap.new(@menu_panel_width - 40, item_height - 10)
      sprite.x = @menu_panel_x + 20
      sprite.y  =  @menu_panel_y + start_y + (i * item_height)
      sprite.z = 3

      @menu_items << {
        sprite: sprite,
        text: command,
        index: i
      }
    end

    update_menu_visuals
  end

  def pbChoose(commands)
    @current_index = 0 if @current_index >= commands.length

    loop do      Graphics.update
      Input.update

      old_index = @current_index

      if Input.repeat?(Input::DOWN)
        @current_index = (@current_index + 1) % commands.length
        pbPlayCursorSE if old_index != @current_index
      elsif Input.repeat?(Input::UP)
        @current_index = (@current_index - 1) % commands.length
        pbPlayCursorSE if old_index != @current_index
      end

      update_menu_visuals if old_index != @current_index

      if Input.trigger?(Input::USE)
        pbPlayDecisionSE
        return @current_index
      elsif Input.trigger?(Input::BACK)
        pbPlayCloseMenuSE
        return -1
      end
    end
  end

  def update_menu_visuals
    @menu_items.each do |item|
      bitmap = item[:sprite].bitmap
      bitmap.clear

      is_selected  =  (item[:index] == @current_index)

      if is_selected

        (0...bitmap.height).each do |y|
          progress = y.to_f / bitmap.height
          color = Color.new(
            (70 + progress * 20).to_i,
            (110 + progress * 30).to_i,
            (230 - progress * 20).to_i,
            230
          )
          bitmap.fill_rect(0, y, bitmap.width, 1, color)
        end

        glow  =  Color.new(180, 220, 255, 255)
        bitmap.fill_rect(0, 0, bitmap.width, 2, glow)
        bitmap.fill_rect(0, bitmap.height - 2, bitmap.width, 2, glow)
      else

        bitmap.fill_rect(0, 0, bitmap.width, bitmap.height, Color.new(30, 40, 60, 120))
      end

      text_color = is_selected ? Color.new(255, 255, 255) : Color.new(190, 190, 210)
      shadow_color = Color.new(0, 0, 0, 180)
      text_y = (bitmap.height - 24) / 2

      pbDrawTextPositions(bitmap, [
        [item[:text], bitmap.width / 2, text_y, 2, text_color, shadow_color, true]
      ])

      if is_selected
        draw_selection_indicator(bitmap, 10, bitmap.height / 2)
      end
    end
  end

  def draw_selection_indicator(bitmap, x, y)

    color  =  Color.new(255, 255, 100)

    bitmap.fill_rect(x, y - 1, 8, 3, color)
    bitmap.fill_rect(x + 6, y - 3, 3, 7, color)

    right_x = bitmap.width - x - 8
    bitmap.fill_rect(right_x, y - 1, 8, 3, color)
    bitmap.fill_rect(right_x - 1, y - 3, 3, 7, color)
  end

  def pbEndScene

    10.times do |i|
      @sprites.each_value do |sprite|
        sprite.opacity = (10 - i - 1) * 25.5 if sprite.respond_to?(:opacity)
      end
      Graphics.update
    end

    pbDisposeSpriteHash(@sprites)
    @menu_items.each { |item| item[:sprite].dispose } if @menu_items
    @viewport.dispose
  end

  def pbRefresh

  end
end

class PokemonLoad_Scene
  alias mmo_pbStartScene pbStartScene unless method_defined?(:mmo_pbStartScene)
  alias mmo_pbStartScene2 pbStartScene2 unless method_defined?(:mmo_pbStartScene2)
  alias mmo_pbChoose pbChoose unless method_defined?(:mmo_pbChoose)

  def pbStartScene(commands, show_continue, trainer, frame_count, map_id)

    @mmo_scene  =  MMOTitleScreen_Scene.new
    @mmo_scene.pbStartScene(commands, show_continue, trainer, frame_count, map_id)
  end

  def pbStartScene2
    @mmo_scene.pbStartScene2 if @mmo_scene
  end

  def pbChoose(commands)
    return @mmo_scene.pbChoose(commands) if @mmo_scene
    return 0
  end

  def pbEndScene
    @mmo_scene.pbEndScene if @mmo_scene
  end

  def pbRefresh
    @mmo_scene.pbRefresh if @mmo_scene
  end
end

puts '[MMO Title Screen] AAA-quality 800x600 title screen loaded'
