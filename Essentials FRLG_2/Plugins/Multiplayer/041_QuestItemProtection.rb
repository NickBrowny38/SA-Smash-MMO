module QuestItemProtection
  PROTECTED_ITEMS = [
    :OAKSPARCEL,
    :POKEFLUTE,
    :SECRETKEY,
    :BIKEVOUCHER,
    :GOLDTEETH,
    :CARDKEY,
    :LIFTKEY,
    :HELIXFOSSIL,
    :DOMEFOSSIL,
    :OLDAMBER,
    :TEA,
    :SSTICKET,
    :TRIPASS,
    :RAINBOWPASS
  ]

  def self.can_toss?(item)
    return !PROTECTED_ITEMS.include?(item)
  end
end

MenuHandlers.add(:bag_item_menu, :toss_quest_item_check, {
  "name"      => proc { |item| next _INTL("Toss") },
  'order'     => 90,
  "condition" => proc { |item|

    next QuestItemProtection::PROTECTED_ITEMS.include?(item)
  },
  "effect"    => proc { |item, pkm, chosen_cmd, bag_screen, bag|
    pbMessage(_INTL("That's an important item!\nYou can't toss it."))
    next false
  }
})

puts "[Quest Item Protection] Protected #{QuestItemProtection::PROTECTED_ITEMS.length} quest items from being tossed"
