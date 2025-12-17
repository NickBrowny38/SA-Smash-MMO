module MultiplayerCompatibility
  def self.essentials_version
    return @version if @version

    if defined?(Essentials)
      @version = Essentials::VERSION
    elsif defined?(ESSENTIALS_VERSION)
      @version = ESSENTIALS_VERSION
    elsif defined?(ESSENTIALSVERSION)
      @version = ESSENTIALSVERSION
    else
      @version = 'Unknown'
    end

    puts "Detected Pokemon Essentials version: #{@version}"
    @version
  end

  def self.has_game_data?
    defined?(GameData)
  end

  def self.modern_essentials?
    has_game_data?
  end
end

unless defined?(ChooseNumberParams)

  if defined?(NumberInputParams)
    ChooseNumberParams = NumberInputParams
    puts "[Multiplayer] Using NumberInputParams as ChooseNumberParams"
  else

    class ChooseNumberParams
      attr_accessor :minNumber, :maxNumber, :initialNumber, :cancelNumber

      def initialize
        @minNumber = 1
        @maxNumber = 99
        @initialNumber  =  1
        @cancelNumber = 0
      end
    end
    puts "[Multiplayer] Created ChooseNumberParams compatibility class"
  end
end

unless defined?(pbChooseNumber)
  def pbChooseNumber(msgwindow, params)

    return params.cancelNumber
  end
end

unless MultiplayerCompatibility.has_game_data?
  puts "[Multiplayer] GameData not detected - creating compatibility layer"

  module GameData
    class Item
      def self.try_get(item_id)
        return nil unless item_id
        item_id = item_id.to_sym if item_id.is_a?(String)

        if defined?(PBItems) && PBItems.const_defined?(item_id)
          return Item.new(item_id)
        elsif defined?(pbGetItemName)
          return Item.new(item_id)
        end

        nil
      end

      def self.get(item_id)
        try_get(item_id) || Item.new(:POTION)
      end

      def initialize(item_id)
        @id = item_id
      end

      attr_reader :id

      def name
        if defined?(pbGetItemName)
          pbGetItemName(@id)
        elsif defined?(PBItems)
          begin
            PBItems.getName(@id)
          rescue
            @id.to_s
          end
        else
          @id.to_s
        end
      end
    end

    class Species
      def self.try_get(species_id)
        return nil unless species_id
        species_id = species_id.to_sym if species_id.is_a?(String)

        if defined?(PBSpecies) && PBSpecies.const_defined?(species_id)
          return Species.new(species_id)
        elsif defined?(pbGetSpeciesName)
          return Species.new(species_id)
        end

        nil
      end

      def self.get(species_id)
        try_get(species_id) || Species.new(:BULBASAUR)
      end

      def initialize(species_id)
        @species  =  species_id
      end

      attr_reader :species

      def name
        if defined?(pbGetSpeciesName)
          pbGetSpeciesName(@species)
        elsif defined?(PBSpecies)
          begin
            PBSpecies.getName(@species)
          rescue
            @species.to_s
          end
        else
          @species.to_s
        end
      end

      def self.icon_bitmap(species, form = 0, gender = nil, shiny = false, shadow = false)

        begin
          if defined?(pbLoadPokemonBitmap)

            return pbLoadPokemonBitmap(species, false)
          elsif defined?(pbPokemonIconFile)
            filename = pbPokemonIconFile(species)
            return AnimatedBitmap.new(filename).bitmap if filename
          end
        rescue

        end
        nil
      end

      def self.sprite_bitmap(species, form = 0, gender = nil, shiny = false, shadow = false, back = false, egg = false)
        begin
          if defined?(pbLoadPokemonBitmap)
            return pbLoadPokemonBitmap(species, back)
          elsif defined?(pbPokemonBitmapFile)
            filename = pbPokemonBitmapFile(species)
            return AnimatedBitmap.new(filename).bitmap if filename
          end
        rescue

        end
        nil
      end

      def self.icon_bitmap_from_pokemon(pkmn)
        form = 0
        begin
          form = pkmn.form if pkmn.respond_to?(:form)
        rescue
          form  =  0
        end
        return icon_bitmap(pkmn.species, form, pkmn.gender, pkmn.shiny?)
      end

      def self.cry_filename_from_pokemon(pkmn)
        if defined?(pbCryFile)
          return pbCryFile(pkmn.species)
        end
        nil
      end

      def self.cry_length(species)
        return 1.0
      end
    end

    class PlayerMetadata
      def self.get(character_id)

        stub = Object.new
        def stub.walk_charset; nil; end
        return stub
      end
    end
  end

  puts "[Multiplayer] GameData compatibility layer loaded"
end

unless Graphics.respond_to?(:width)
  class << Graphics
    def width
      return 512
    end

    def height
      return 384
    end
  end
end

unless defined?(pbConfirmMessage)
  def pbConfirmMessage(msg)
    return Kernel.pbConfirmMessage(msg) if Kernel.respond_to?(:pbConfirmMessage)
    return false
  end
end

unless defined?(pbMessage)
  def pbMessage(msg)
    return Kernel.pbMessage(msg) if Kernel.respond_to?(:pbMessage)
    puts msg
  end
end

puts "[Multiplayer] Compatibility layer initialized successfully"
