class PlayerCore

  # Static helper functions
  @copyPos: (pos) ->
    return { x: pos.x, y: pos.y }

  @addPos: (pos, vec) ->
    return { x: (pos.x + vec.x), y: (pos.y + vec.y) }

  @lerp: (n1, n2, t) ->
    n1 = Number(n1)
    n2 = Number(n2)
    _t = Number(t)
    _t = Number(Math.max(0, Math.min(1,_t))).toFixed(3)
    return parseFloat(n1 + _t * (n2-n1)).toFixed(3)

  @lerpPos: (pos1, pos2, time) ->
    #console.log @lerp(pos1.x, pos2.x, time)
    return { x: @lerp(pos1.x, pos2.x, time), y: @lerp(pos1.y, pos2.y, time) }

  constructor: (@game, @server_player_instance, @client=false) ->

    # Set up initial values for our state information
    @state = 'not-connected'
    @pos = { x:0, y:0 }
    @id = ''  # On client, only player-controlled instance knows own id
    @publicid = '' # On client, every player instance has public id from server
    # On the server all players store their unique userid
    if !@client
      @id = @server_player_instance.userid
      @publicid = @server_player_instance.publicid

    # These are used in moving us around later
    @old_state = {pos:{x:0, y:0}}
    @cur_state = {pos:{x:0, y:0}}
    @state_time = new Date().getTime()

    # Our local history of inputs
    @inputs = []
    @last_input_seq = 0
    @last_input_time = null

  setPos: (x, y) ->
    @pos.x = x
    @pos.y = y


class PlayerClient extends PlayerCore
  constructor: (@game) ->
    super @game, null, true

    @sprite = null
    @name = null

    @initSprite()

  initSprite: ()->
    if @sprite != null
      return
    if !@game.phaserLoaded
      return
    @sprite = @game.phaserGame.add.sprite(0,0,'player')
    @name = @game.phaserGame.add.text(0,0,@publicid)

  setPos: (x, y) ->
    super x, y
    if @sprite != null
      @sprite.x = x
      @sprite.y = y
      @name.x = x
      @name.y = y

if typeof module != 'undefined' && typeof module.exports != 'undefined'
  exports.PlayerCore = PlayerCore
  exports.PlayerClient = PlayerClient
# On client (browser) there is no module, add exports to window
else
  window.PlayerCore = PlayerCore
  window.PlayerClient = PlayerClient