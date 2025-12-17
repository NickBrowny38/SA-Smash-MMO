class PokemonEntryScene2
  alias mmo_pbStartScene pbStartScene

  def pbStartScene(helptext, minlength, maxlength, initialText, subject = 0, pokemon = nil)
    in_mmo = defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?

    if in_mmo
      @mmo_bg_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @mmo_bg_viewport.z = 99998

      bg_overlay = Sprite.new(@mmo_bg_viewport)
      bg_overlay.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      bg_overlay.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))
      bg_overlay.z = 0
      @mmo_bg_sprite = bg_overlay
    end

    mmo_pbStartScene(helptext, minlength, maxlength, initialText, subject, pokemon)

    return unless in_mmo

    offset_x = (Graphics.width - 512) / 2
    offset_y = (Graphics.height - 384) / 2

    @viewport.rect.x = offset_x
    @viewport.rect.y = offset_y
    @viewport.rect.width = 512
    @viewport.rect.height = 384
  end

  alias mmo_pbEndScene pbEndScene

  def pbEndScene
    mmo_pbEndScene
    if @mmo_bg_sprite
      @mmo_bg_sprite.dispose
      @mmo_bg_sprite = nil
    end
    if @mmo_bg_viewport
      @mmo_bg_viewport.dispose
      @mmo_bg_viewport = nil
    end
  end
end

class PokemonMart_Scene
  def pbStartBuyOrSellScene(buying, stock, adapter)
    in_mmo = defined?(pbIsMultiplayerMode?) && pbIsMultiplayerMode?

    if in_mmo
      offset_x = (Graphics.width - 512) / 2
      offset_y = (Graphics.height - 384) / 2
      game_width = 512
      game_height = 384
    else
      offset_x = 0
      offset_y = 0
      game_width = Graphics.width
      game_height = Graphics.height
    end

    pbScrollMap(6, 5, 5)
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @stock = stock
    @adapter = adapter
    @sprites = {}

    if in_mmo
      @sprites["bg_overlay"] = Sprite.new(@viewport)
      @sprites["bg_overlay"].bitmap = Bitmap.new(Graphics.width, Graphics.height)
      @sprites["bg_overlay"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))
      @sprites["bg_overlay"].z = 0
    end

    @sprites["background"] = IconSprite.new(offset_x, offset_y, @viewport)
    @sprites["background"].setBitmap("Graphics/UI/Mart/bg")
    @sprites["icon"] = ItemIconSprite.new(36 + offset_x, game_height - 50 + offset_y, nil, @viewport)
    winAdapter = buying ? BuyAdapter.new(adapter) : SellAdapter.new(adapter)
    @sprites["itemwindow"] = Window_PokemonMart.new(
      stock, winAdapter, game_width - 316 - 16 + offset_x, 10 + offset_y, 330 + 16, game_height - 124
    )
    @sprites["itemwindow"].viewport = @viewport
    @sprites["itemwindow"].index = 0
    @sprites["itemwindow"].refresh
    @sprites["itemtextwindow"] = Window_UnformattedTextPokemon.newWithSize(
      "", 64 + offset_x, game_height - 96 - 16 + offset_y, game_width - 64, 128, @viewport
    )
    pbPrepareWindow(@sprites["itemtextwindow"])
    @sprites["itemtextwindow"].baseColor = Color.new(248, 248, 248)
    @sprites["itemtextwindow"].shadowColor = Color.black
    @sprites["itemtextwindow"].windowskin = nil
    @sprites["helpwindow"] = Window_AdvancedTextPokemon.new("")
    pbPrepareWindow(@sprites["helpwindow"])
    @sprites["helpwindow"].visible = false
    @sprites["helpwindow"].viewport = @viewport
    pbBottomLeftLines(@sprites["helpwindow"], 1)
    @sprites["moneywindow"] = Window_AdvancedTextPokemon.new("")
    pbPrepareWindow(@sprites["moneywindow"])
    @sprites["moneywindow"].setSkin("Graphics/Windowskins/goldskin")
    @sprites["moneywindow"].visible = true
    @sprites["moneywindow"].viewport = @viewport
    @sprites["moneywindow"].x = offset_x
    @sprites["moneywindow"].y = offset_y
    @sprites["moneywindow"].width = 190
    @sprites["moneywindow"].height = 96
    @sprites["moneywindow"].baseColor = Color.new(88, 88, 80)
    @sprites["moneywindow"].shadowColor = Color.new(168, 184, 184)
    @sprites["qtywindow"] = Window_AdvancedTextPokemon.new("")
    pbPrepareWindow(@sprites["qtywindow"])
    @sprites["qtywindow"].setSkin("Graphics/Windowskins/goldskin")
    @sprites["qtywindow"].viewport = @viewport
    @sprites["qtywindow"].width = 190
    @sprites["qtywindow"].height = 64
    @sprites["qtywindow"].baseColor = Color.new(88, 88, 80)
    @sprites["qtywindow"].shadowColor = Color.new(168, 184, 184)
    @sprites["qtywindow"].text = _INTL("In Bag:<r>{1}", @adapter.getQuantity(@sprites["itemwindow"].item))
    @sprites["qtywindow"].y = game_height - 102 - @sprites["qtywindow"].height + offset_y
    pbDeactivateWindows(@sprites)
    @buying = buying
    pbRefresh
    Graphics.frame_reset
  end
end

puts "[Text Entry & Mart Fix] Nickname screen and Pokemart UI centered for 800x600"
