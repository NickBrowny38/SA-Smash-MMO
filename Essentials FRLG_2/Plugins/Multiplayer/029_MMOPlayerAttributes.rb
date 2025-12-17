class Player
  attr_accessor :registered_key_items

  alias mmo_attrs_original_initialize initialize

  def initialize(*args)
    mmo_attrs_original_initialize(*args)

    @registered_key_items = []
  end

  # Fix badge_count to work with integer badges from server (1/0) not just booleans (true/false)
  # Server sends [1,1,1,0,0,...] but original badge_count uses == true which fails for integers
  # IMPORTANT: In Ruby, 0 is truthy! So we must explicitly check for non-zero values
  def badge_count
    return @badges.count { |badge| badge == 1 || badge == true }
  end
end

puts "[MMO Player Attributes] Added registered_key_items attribute and fixed badge_count for integer badges"
