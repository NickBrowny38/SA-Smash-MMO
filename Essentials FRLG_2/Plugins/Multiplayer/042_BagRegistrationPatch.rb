EventHandlers.add(:on_enter_map, :patch_bag_for_mmo, proc {
  next if defined?($mmo_bag_patched) && $mmo_bag_patched
  $mmo_bag_patched = true

  puts '[MMO Bag Registration] Patching bag screen now...'

  PokemonBagScreen.class_eval do    alias mmo_pbStartScreen pbStartScreen unless method_defined?(:mmo_pbStartScreen)

    def pbStartScreen
      @scene.pbStartScene(@bag)
      item = nil
      loop do        item  =  @scene.pbChooseItem
        break if !item

        in_multiplayer = defined?($multiplayer_client) && $multiplayer_client && $multiplayer_client.connected?
        has_mmo_ui = defined?($mmo_key_items_bar) && $mmo_key_items_bar

        itm = GameData::Item.get(item)
        cmdRead     = -1
        cmdUse      = -1
        cmdRegister  =  -1
        cmdGive     = -1
        cmdToss     = -1
        cmdMMORegister = -1
        cmdMMOUnregister = -1
        cmdDebug     =  -1
        commands = []

        commands[cmdRead = commands.length] = _INTL("Read") if itm.is_mail?
        if ItemHandlers.hasOutHandler(item) || (itm.is_machine? && $player.party.length > 0)
          if ItemHandlers.hasUseText(item)
            commands[cmdUse = commands.length] = ItemHandlers.getUseText(item)
          else
            commands[cmdUse = commands.length] = _INTL("Use")
          end
        end
        commands[cmdGive = commands.length] = _INTL("Give") if $player.pokemon_party.length > 0 && itm.can_hold?
        commands[cmdToss = commands.length] = _INTL("Toss") if !itm.is_important? || $DEBUG

        if @bag.registered?(item)
          commands[cmdRegister = commands.length] = _INTL("Deselect")
        elsif pbCanRegisterItem?(item)
          commands[cmdRegister = commands.length] = _INTL("Register")
        end

        if in_multiplayer && has_mmo_ui

          can_mmo_register = itm.is_key_item? || itm.can_hold?

          if can_mmo_register
            if $mmo_key_items_bar.registered_items.include?(item)
              commands[cmdMMOUnregister = commands.length] = _INTL("MMO Unregister")
              puts "[MMO Bag] Showing 'MMO Unregister' for #{itm.name}"
            elsif $mmo_key_items_bar.registered_items.length < MMOKeyItemsBar::MAX_REGISTERED_ITEMS
              commands[cmdMMORegister = commands.length] = _INTL("MMO Register")
              puts "[MMO Bag] Showing 'MMO Register' for #{itm.name}"
            end
          end
        end

        commands[cmdDebug = commands.length] = _INTL("Debug") if $DEBUG
        commands[commands.length] = _INTL("Cancel")

        itemname  =  itm.name
        command = @scene.pbShowCommands(_INTL("{1} is selected.", itemname), commands)

        if cmdRead >= 0 && command == cmdRead
          pbFadeOutIn do            pbDisplayMail(Mail.new(item, "", ""))
          end
        elsif cmdUse >= 0 && command == cmdUse
          ret  =  pbUseItem(@bag, item, @scene)
          break if ret == 2
          @scene.pbRefresh
          next
        elsif cmdGive >= 0 && command == cmdGive
          if $player.pokemon_count == 0
            @scene.pbDisplay(_INTL("There is no Pokémon."))
          elsif itm.is_important?
            @scene.pbDisplay(_INTL("The {1} can't be held.", itm.portion_name))
          else
            pbFadeOutIn do              sscene = PokemonParty_Scene.new
              sscreen = PokemonPartyScreen.new(sscene, $player.party)
              sscreen.pbPokemonGiveScreen(item)
              @scene.pbRefresh
            end
          end
        elsif cmdToss >= 0 && command == cmdToss
          qty = @bag.quantity(item)
          if qty > 1
            helptext = _INTL("Toss out how many {1}?", itm.portion_name_plural)
            qty = @scene.pbChooseNumber(helptext, qty)
          end
          if qty > 0
            itemname = (qty > 1) ? itm.portion_name_plural : itm.portion_name
            if pbConfirm(_INTL("Is it OK to throw away {1} {2}?", qty, itemname))
              pbDisplay(_INTL('Threw away {1} {2}.', qty, itemname))
              qty.times { @bag.remove(item) }
              @scene.pbRefresh
            end
          end
        elsif cmdRegister >= 0 && command == cmdRegister
          if @bag.registered?(item)
            @bag.unregister(item)
          else
            @bag.register(item)
          end
          @scene.pbRefresh
        elsif cmdMMORegister >= 0 && command == cmdMMORegister
          $mmo_key_items_bar.register_item(item)
          pbMultiplayerNotify("Registered #{itm.name}", 2.0) if defined?(pbMultiplayerNotify)
          puts "[MMO Bag] Registered #{itm.name}"
          @scene.pbRefresh
        elsif cmdMMOUnregister >= 0 && command == cmdMMOUnregister
          $mmo_key_items_bar.unregister_item(item)
          pbMultiplayerNotify("Unregistered #{itm.name}", 2.0) if defined?(pbMultiplayerNotify)
          puts "[MMO Bag] Unregistered #{itm.name}"
          @scene.pbRefresh
        elsif cmdDebug >= 0 && command == cmdDebug
          command = 0
          loop do            command = @scene.pbShowCommands(_INTL("Do what with {1}?", itemname),
                                            [_INTL("Change quantity"),
                                             _INTL("Make Mystery Gift"),
                                             _INTL("Cancel")], command)
            case command
            when -1, 2
              break
            when 0
              qty  =  @bag.quantity(item)
              itemplural  =  itm.name_plural
              params = ChooseNumberParams.new
              params.setRange(0, Settings::BAG_MAX_PER_SLOT)
              params.setDefaultValue(qty)
              newqty = pbMessageChooseNumber(
                _INTL("Choose new quantity of {1} (max. {2}).", itemplural, Settings::BAG_MAX_PER_SLOT), params
              ) { @scene.pbUpdate }
              if newqty > qty
                @bag.add(item, newqty - qty)
              elsif newqty < qty
                @bag.remove(item, qty - newqty)
              end
              @scene.pbRefresh
              break if newqty == 0
            when 1
              pbCreateMysteryGift(1, item)
            end
          end
        end
      end
      ($game_temp.fly_destination) ? @scene.dispose : @scene.pbEndScene
      return item
    end
  end

  puts "[MMO Bag Registration] Bag patched for MMO registration (via EventHandler)"
})

puts "[MMO Bag Registration] Patch will be applied when game starts"
