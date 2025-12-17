class MultiplayerClient
  def auction_list_item(item_id, quantity, price)
    data = {
      type: :auction_list_item,
      data: {
        item_id: item_id,
        quantity: quantity,
        price: price
      }
    }
    send_message(data)
  end

  def auction_list_pokemon(pokemon_data, party_index, price)
    data = {
      type: :auction_list_pokemon,
      data: {
        pokemon_data: pokemon_data,
        party_index: party_index,
        price: price
      }
    }
    send_message(data)
  end

  def auction_browse(filter_type = 'ALL', search_query = '', offset = 0, limit = 50)
    data = {
      type: :auction_browse,
      data: {
        filter_type: filter_type,
        search: search_query,
        offset: offset,
        limit: limit
      }
    }
    send_message(data)
  end

  def auction_buy(listing_id)
    data = {
      type: :auction_buy,
      data: {
        listing_id: listing_id
      }
    }
    send_message(data)
  end

  def auction_cancel(listing_id)
    data = {
      type: :auction_cancel,
      data: {
        listing_id: listing_id
      }
    }
    send_message(data)
  end

  def auction_my_listings
    data = {
      type: :auction_my_listings,
      data: {}
    }
    send_message(data)
  end

  def handle_auction_list_success(data)
    puts "[AUCTION] Listing created successfully! ID: #{data[:listing_id]}"
    $auction_last_result = {success: true, type: :list, listing_id: data[:listing_id]}
  end

  def handle_auction_browse_result(data)
    listings = data[:listings] || []

    listings.each do |listing|
      if listing['pokemon_data'].is_a?(String) && !listing['pokemon_data'].empty?
        begin
          listing['pokemon_data'] = JSON.parse(listing['pokemon_data'], symbolize_names: true)
        rescue StandardError
          listing['pokemon_data'] = nil
        end
      end
    end

    puts "[AUCTION] Received #{listings.length} listings"
    $auction_browse_results = listings
    $auction_browse_ready = true
  end

  def handle_auction_buy_success(data)
    puts "[AUCTION] Purchase successful! Listing ID: #{data[:listing_id]}, Price: #{data[:price]}"

    if data[:money] && $player
      $player.money = (data[:money] || data['money']).to_i
      puts "[AUCTION] Money updated: $#{$player.money}"
    end

    if data[:bag] && $bag
      $bag.clear
      data[:bag].each do |item|
        item_id = item[:item_id] || item['item_id']
        quantity = item[:quantity] || item['quantity'] || 1
        $bag.add(item_id, quantity) if item_id
      end
      puts "[AUCTION] Bag updated: #{data[:bag].size} items"
    end

    if data[:pokemon] && $player
      $player.party.clear
      data[:pokemon].each do |pkmn_data|
        species = pkmn_data[:species] || pkmn_data['species']
        if species
          pokemon  =  pbModernTradeManager.deserialize_pokemon(pkmn_data)
          $player.party << pokemon
        end
      end
      puts "[AUCTION] Party updated: #{$player.party.size} Pokemon"
    end

    $auction_last_result  =  {success: true, type: :buy, listing_id: data[:listing_id], price: data[:price]}
  end

  def handle_auction_cancel_success(data)
    puts "[AUCTION] Listing cancelled successfully! ID: #{data[:listing_id]}"

    if data[:bag] && $bag
      $bag.clear
      data[:bag].each do |item|
        item_id = item[:item_id] || item['item_id']
        quantity = item[:quantity] || item['quantity'] || 1
        $bag.add(item_id, quantity) if item_id
      end
      puts "[AUCTION] Bag updated: #{data[:bag].size} items"
    end

    if data[:pokemon] && $player
      $player.party.clear
      data[:pokemon].each do |pkmn_data|
        species = pkmn_data[:species] || pkmn_data['species']
        if species
          pokemon = pbModernTradeManager.deserialize_pokemon(pkmn_data)
          $player.party << pokemon
        end
      end
      puts "[AUCTION] Party updated: #{$player.party.size} Pokemon"
    end

    $auction_last_result = {success: true, type: :cancel, listing_id: data[:listing_id]}
  end

  def handle_auction_my_listings_result(data)
    listings = data[:listings] || []

    listings.each do |listing|
      if listing['pokemon_data'].is_a?(String) && !listing['pokemon_data'].empty?
        begin
          listing['pokemon_data'] = JSON.parse(listing['pokemon_data'], symbolize_names: true)
        rescue StandardError
          listing['pokemon_data'] = nil
        end
      end
    end

    puts "[AUCTION] Your active listings: #{listings.length}"
    $auction_my_listings = listings
    $auction_my_listings_ready = true
  end

  def handle_auction_sold(data)
    puts "[AUCTION] Your listing sold! Listing ID: #{data[:listing_id]}, Price: #{data[:price]}, Buyer: #{data[:buyer]}"

    if data[:money] && $player
      $player.money = (data[:money] || data['money']).to_i
      puts "[AUCTION] Money updated: $#{$player.money}"
    end

    pbMultiplayerNotify("Your listing sold for #{data[:price]}! Buyer: #{data[:buyer]}", 5.0)
  end

  def handle_auction_error(data)
    error = data[:error] || data['error'] || "Unknown error"
    puts "[AUCTION ERROR] #{error}"
    $auction_last_result = {success: false, error: error}
  end
end

$auction_browse_results = []
$auction_browse_ready = false
$auction_my_listings  =  []
$auction_my_listings_ready = false
$auction_last_result  =  nil
