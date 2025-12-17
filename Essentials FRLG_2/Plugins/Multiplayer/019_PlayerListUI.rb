class MultiplayerPlayerList
  def initialize(viewport)
    @viewport = viewport
    @sprites = {}
    @visible  =  false
    @last_update  =  Time.now
    create_sprites
  end

  def create_sprites
    @sprites[:background]  =  Sprite.new(@viewport)
    @sprites[:background].bitmap = Bitmap.new(400, 300)
    @sprites[:background].x = (Graphics.width - 400) / 2
    @sprites[:background].y = 50
    @sprites[:background].z = 99999
    @sprites[:background].visible = false

    @sprites[:title] = Sprite.new(@viewport)
    @sprites[:title].bitmap = Bitmap.new(400, 40)
    @sprites[:title].x = @sprites[:background].x
    @sprites[:title].y = @sprites[:background].y
    @sprites[:title].z = 100000
    @sprites[:title].visible = false

    @sprites[:players] = Sprite.new(@viewport)
    @sprites[:players].bitmap = Bitmap.new(380, 240)
    @sprites[:players].x  =  @sprites[:background].x + 10
    @sprites[:players].y = @sprites[:background].y + 50
    @sprites[:players].z = 100000
    @sprites[:players].visible = false
  end

  def show
    return unless pbMultiplayerConnected?
    @visible = true
    update_display
    @sprites.each_value { |sprite| sprite.visible = true }
  end

  def hide
    @visible = false
    @sprites.each_value { |sprite| sprite.visible = false }
  end

  def visible?
    @visible
  end

  def update
    return unless @visible

    if Time.now - @last_update > 0.5
      update_display
      @last_update  =  Time.now
    end
  end

  def update_display
    return unless pbMultiplayerConnected?

    bg = @sprites[:background].bitmap
    bg.clear
    bg.fill_rect(0, 0, 400, 300, Color.new(0, 0, 0, 200))
    bg.fill_rect(2, 2, 396, 296, Color.new(40, 40, 40, 255))
    bg.fill_rect(4, 4, 392, 292, Color.new(0, 0, 0, 200))

    title = @sprites[:title].bitmap
    title.clear
    base_color = Color.new(255, 255, 255)
    shadow_color = Color.new(0, 0, 0)

    remote_players = pbMultiplayerClient.remote_players
    total_players = remote_players.size + 1

    title_text = "Online Players (#{total_players})"
    pbDrawTextPositions(title, [
      [title_text, 200, 8, 2, base_color, shadow_color]
    ])

    players_bitmap = @sprites[:players].bitmap
    players_bitmap.clear

    y_offset  =  0
    line_height = 24

    if $player
      local_name = $player.name
      local_map = $game_map ? $game_map.name : "Unknown"

      pbDrawTextPositions(players_bitmap, [
        [local_name + ' (You)', 10, y_offset, 0, Color.new(255, 255, 100), shadow_color],
        [local_map, 250, y_offset, 0, Color.new(150, 150, 150), shadow_color]
      ])
      y_offset += line_height
    end

    remote_players.each do |player_id, player_data|
      break if y_offset >= 240 - line_height

      username = player_data[:username] || 'Unknown'
      map_id = player_data[:map_id]

      map_name = 'Unknown'
      begin
        if map_id && pbLoadMapInfos
          map_info = pbLoadMapInfos[map_id]
          map_name = map_info ? map_info.name : "Map #{map_id}"
        end
      rescue
        map_name = "Map #{map_id}"
      end

      same_map = ($game_map && map_id == $game_map.map_id)
      name_color = same_map ? Color.new(100, 255, 100) : Color.new(255, 255, 255)

      pbDrawTextPositions(players_bitmap, [
        [username, 10, y_offset, 0, name_color, shadow_color],
        [map_name, 250, y_offset, 0, Color.new(150, 150, 150), shadow_color]
      ])

      y_offset += line_height
    end

    if y_offset < 220
      hint_text = "Hold TAB to view • Green = Same Map"
      pbDrawTextPositions(players_bitmap, [
        [hint_text, 190, 220, 2, Color.new(180, 180, 180), shadow_color]
      ])
    end
  end

  def dispose
    @sprites.each_value do |sprite|
      sprite.bitmap.dispose if sprite.bitmap
      sprite.dispose
    end
    @sprites.clear
  end
end

$multiplayer_player_list = nil
$multiplayer_player_list_viewport = nil

def pbMultiplayerPlayerList

  if !$multiplayer_player_list_viewport || $multiplayer_player_list_viewport.disposed?
    $multiplayer_player_list_viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    $multiplayer_player_list_viewport.z = 99999
    $multiplayer_player_list = nil
  end

  $multiplayer_player_list ||= MultiplayerPlayerList.new($multiplayer_player_list_viewport)
  return $multiplayer_player_list
end
