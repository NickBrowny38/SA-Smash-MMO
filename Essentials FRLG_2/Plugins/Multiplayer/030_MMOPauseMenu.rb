class MMOPauseMenu_Scene < PokemonPauseMenu_Scene
  def pbStartScene
    hide_mmo_ui_temporarily

    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 96000
    @sprites = {}

    @sprites['overlay'] = Sprite.new(@viewport)
    @sprites['overlay'].bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @sprites["overlay"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 140))
    @sprites["overlay"].z = 96000

    create_menu_panel

    create_player_info_panel

    animate_menu_in

    pbSEPlay("GUI menu open")
  end

  def hide_mmo_ui_temporarily

    @mmo_ui_was_visible = false

    if $scene.is_a?(Scene_Map)
      if $scene.respond_to?(:mmo_ui_overlay) && $scene.mmo_ui_overlay
        @mmo_ui_was_visible = true
        $scene.mmo_ui_overlay.visible  =  false if $scene.mmo_ui_overlay.respond_to?(:visible=)
      end
      if $scene.respond_to?(:mmo_party_ui) && $scene.mmo_party_ui
        $scene.mmo_party_ui.visible = false if $scene.mmo_party_ui.respond_to?(:visible=)
      end
      if $scene.respond_to?(:mmo_key_items_bar) && $scene.mmo_key_items_bar
        $scene.mmo_key_items_bar.visible = false if $scene.mmo_key_items_bar.respond_to?(:visible=)
      end
    end
  end

  def restore_mmo_ui

    return unless @mmo_ui_was_visible

    if $scene.is_a?(Scene_Map)
      if $scene.respond_to?(:mmo_ui_overlay) && $scene.mmo_ui_overlay
        $scene.mmo_ui_overlay.visible  =  true if $scene.mmo_ui_overlay.respond_to?(:visible=)
      end
      if $scene.respond_to?(:mmo_party_ui) && $scene.mmo_party_ui
        $scene.mmo_party_ui.visible = true if $scene.mmo_party_ui.respond_to?(:visible=)
      end
      if $scene.respond_to?(:mmo_key_items_bar) && $scene.mmo_key_items_bar
        $scene.mmo_key_items_bar.visible = true if $scene.mmo_key_items_bar.respond_to?(:visible=)
      end
    end
  end

  def create_menu_panel

    @menu_width  =  280
    @menu_x = 60
    @menu_y  =  (Graphics.height - 400) / 2

    @sprites["menu_bg"]  =  Sprite.new(@viewport)
    @sprites["menu_bg"].bitmap = Bitmap.new(@menu_width, 450)
    @sprites["menu_bg"].x  =  @menu_x
    @sprites["menu_bg"].y  =  @menu_y
    @sprites["menu_bg"].z  =  96001

    bitmap  =  @sprites["menu_bg"].bitmap
    (0...bitmap.height).each do |i|
      progress = i.to_f / bitmap.height
      color = Color.new(
        (20 * (1 - progress) + 10 * progress).to_i,
        (30 * (1 - progress) + 20 * progress).to_i,
        (60 * (1 - progress) + 40 * progress).to_i,
        200
      )
      bitmap.fill_rect(0, i, bitmap.width, 1, color)
    end

    border_color = Color.new(100, 150, 255, 180)
    bitmap.fill_rect(0, 0, bitmap.width, 2, border_color)
    bitmap.fill_rect(0, bitmap.height - 2, bitmap.width, 2, border_color)
    bitmap.fill_rect(0, 0, 2, bitmap.height, border_color)
    bitmap.fill_rect(bitmap.width - 2, 0, 2, bitmap.height, border_color)

    @sprites["cmdwindow"] = Window_CommandPokemon.new([])
    @sprites["cmdwindow"].visible = false
    @sprites["cmdwindow"].viewport = @viewport

    @sprites["infowindow"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, 32, 32, @viewport)
    @sprites["infowindow"].visible = false
    @sprites["helpwindow"] = Window_UnformattedTextPokemon.newWithSize("", 0, 0, 32, 32, @viewport)
    @sprites["helpwindow"].visible = false

    @infostate = false
    @helpstate  =  false
  end

  def create_player_info_panel

    info_width = 240
    info_height  =  120

    @sprites["player_info"] = Sprite.new(@viewport)
    @sprites["player_info"].bitmap = Bitmap.new(info_width, info_height)
    @sprites["player_info"].x = 20
    @sprites["player_info"].y = 20
    @sprites["player_info"].z = 96002

    bitmap = @sprites['player_info'].bitmap

    (0...info_height).each do |i|
      progress = i.to_f / info_height
      color = Color.new(
        (10 * (1 - progress) + 5 * progress).to_i,
        (20 * (1 - progress) + 10 * progress).to_i,
        (40 * (1 - progress) + 25 * progress).to_i,
        180
      )
      bitmap.fill_rect(0, i, info_width, 1, color)
    end

    border_color = Color.new(80, 120, 200, 160)
    bitmap.fill_rect(0, 0, info_width, 2, border_color)
    bitmap.fill_rect(0, info_height - 2, info_width, 2, border_color)
    bitmap.fill_rect(0, 0, 2, info_height, border_color)
    bitmap.fill_rect(info_width - 2, 0, 2, info_height, border_color)

    text_color  =  Color.new(255, 255, 255)
    shadow_color  =  Color.new(0, 0, 0, 120)

    pbDrawTextPositions(bitmap, [
      ["#{$player.name}", 12, 12, 0, Color.new(255, 220, 100), shadow_color, true],
      ["Badges: #{$player.badge_count}", 12, 42, 0, text_color, shadow_color, true],
      ["Money: $#{$player.money.to_s_formatted}", 12, 72, 0, text_color, shadow_color, true]
    ])
  end

  def animate_menu_in

    10.times do |i|
      @sprites["overlay"].opacity = (i + 1) * 25.5
      @sprites["menu_bg"].opacity = (i + 1) * 25.5 if @sprites["menu_bg"]
      @sprites["player_info"].opacity = (i + 1) * 25.5 if @sprites["player_info"]

      offset = (10 - i) * 15
      @sprites["menu_bg"].x = @menu_x - offset if @sprites["menu_bg"]

      Graphics.update
    end
  end

  def animate_menu_out

    10.times do |i|
      @sprites['overlay'].opacity = (10 - i - 1) * 25.5
      @sprites["menu_bg"].opacity = (10 - i - 1) * 25.5 if @sprites["menu_bg"]
      @sprites["player_info"].opacity  =  (10 - i - 1) * 25.5 if @sprites["player_info"]
      @sprites.each do |key, sprite|
        next if ["overlay", "menu_bg", "player_info"].include?(key)
        sprite.opacity = (10 - i - 1) * 25.5 if sprite && sprite.respond_to?(:opacity)
      end

      Graphics.update
    end
  end

  def pbShowCommands(commands)
    ret = -1

    create_menu_items(commands)

    @current_index = $game_temp.menu_last_choice || 0
    @current_index  =  0 if @current_index >= commands.length

    loop do      Graphics.update
      Input.update
      pbUpdateSceneMap

      update_menu_selection(commands.length)

      if Input.trigger?(Input::BACK) || Input.trigger?(Input::ACTION)
        pbPlayCloseMenuSE
        ret = -1
        break
      elsif Input.trigger?(Input::USE)
        pbPlayDecisionSE
        ret = @current_index
        $game_temp.menu_last_choice = ret
        break
      end
    end

    dispose_menu_items
    return ret
  end

  def create_menu_items(commands)
    @menu_item_sprites = []
    @menu_item_texts = []

    item_height = 50
    start_y = @menu_y + 40

    commands.each_with_index do |command, i|

      item_sprite = Sprite.new(@viewport)
      item_sprite.bitmap = Bitmap.new(@menu_width - 20, item_height - 4)
      item_sprite.x = @menu_x + 10
      item_sprite.y = start_y + (i * item_height)
      item_sprite.z  =  96003

      @menu_item_sprites << item_sprite
      @menu_item_texts << command
    end

    update_menu_visuals
  end

  def update_menu_selection(max_items)
    old_index  =  @current_index

    if Input.repeat?(Input::DOWN)
      @current_index  =  (@current_index + 1) % max_items
      pbPlayCursorSE if old_index != @current_index
    elsif Input.repeat?(Input::UP)
      @current_index = (@current_index - 1) % max_items
      pbPlayCursorSE if old_index != @current_index
    end

    update_menu_visuals if old_index != @current_index
  end

  def update_menu_visuals
    @menu_item_sprites.each_with_index do |sprite, i|
      bitmap = sprite.bitmap
      bitmap.clear

      is_selected  =  (i == @current_index)

      if is_selected

        (0...bitmap.height).each do |y|
          progress = y.to_f / bitmap.height
          color = Color.new(
            (60 + progress * 20).to_i,
            (100 + progress * 30).to_i,
            (220 - progress * 20).to_i,
            220
          )
          bitmap.fill_rect(0, y, bitmap.width, 1, color)
        end

        glow = Color.new(150, 200, 255, 255)
        bitmap.fill_rect(0, 0, bitmap.width, 2, glow)
        bitmap.fill_rect(0, bitmap.height - 2, bitmap.width, 2, glow)
      else

        bitmap.fill_rect(0, 0, bitmap.width, bitmap.height, Color.new(20, 30, 50, 100))
      end

      text = @menu_item_texts[i]
      text_color = is_selected ? Color.new(255, 255, 255) : Color.new(180, 180, 200)
      shadow_color = Color.new(0, 0, 0, 160)

      text_y = (bitmap.height - 24) / 2
      pbDrawTextPositions(bitmap, [
        [text, 20, text_y, 0, text_color, shadow_color, true]
      ])

      if is_selected
        arrow_x = 8
        arrow_y = bitmap.height / 2
        draw_arrow(bitmap, arrow_x, arrow_y, Color.new(255, 255, 100))
      end
    end
  end

  def draw_arrow(bitmap, x, y, color)

    bitmap.fill_rect(x, y - 1, 6, 3, color)
    bitmap.fill_rect(x + 4, y - 3, 3, 7, color)
  end

  def dispose_menu_items
    return unless @menu_item_sprites
    @menu_item_sprites.each { |sprite| sprite.dispose if sprite }
    @menu_item_sprites = []
    @menu_item_texts = []
  end

  def pbEndScene
    animate_menu_out
    dispose_menu_items
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose

    restore_mmo_ui
  end

  def pbShowMenu

    return unless @sprites
    @sprites.each_value do |sprite|
      sprite.visible = true if sprite && !sprite.disposed?
    end
    @menu_item_sprites.each { |sprite| sprite.visible = true if sprite && !sprite.disposed? } if @menu_item_sprites
  end

  def pbHideMenu

    return unless @sprites
    @sprites.each_value do |sprite|
      sprite.visible = false if sprite && !sprite.disposed?
    end
    @menu_item_sprites.each { |sprite| sprite.visible = false if sprite && !sprite.disposed? } if @menu_item_sprites
  end

  def pbRefresh

    pbShowMenu
  end
end

class PokemonPauseMenu
  alias mmo_pbStartPokemonMenu pbStartPokemonMenu unless method_defined?(:mmo_pbStartPokemonMenu)

  def pbStartPokemonMenu

    if defined?($multiplayer_client) && $multiplayer_client && $multiplayer_client.connected?

      @scene = MMOPauseMenu_Scene.new
      mmo_pbStartPokemonMenu
    else

      mmo_pbStartPokemonMenu
    end
  end
end

puts '[MMO Pause Menu] AAA-quality overlay menu loaded for multiplayer mode'
