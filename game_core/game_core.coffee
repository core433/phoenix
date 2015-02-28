if typeof module != 'undefined' && typeof module.exports != 'undefined'
  libPlayer = require './player'
  PlayerCore = libPlayer.PlayerCore
  PlayerClient = libPlayer.PlayerClient
# On client (browser) there is no module, add exports to window
#else
#  mPlayerCore = window.PlayerCore
#  mPlayerClient = window.PlayerClient

class GameCore

  constructor: (@server_game_instance, @client=false) ->

    # create players here.
    if @client
      # On the client, when we create the game, only create myself,
      # wait for server to tell us to create other players
      @players = {myself: new window.PlayerClient(this), others: []}
    else
      # On the server, when we create the game, @server_game_instance
      # should only have the host
      @players = {myself: new PlayerCore(
        this,
        @server_game_instance.player_host), others: []}

    # ==========================================================================
    # UPDATE LOOPS
    # ==========================================================================
    # A note on update loops:
    #     - On server and client, the physics loop is always 66.6 Hz / 15 ms
    #     - On client, the update loop is 60 Hz / 16 ms
    #     - On server, the broadcast loop is 22.2 Hz / 45 ms
    #
    # Set up physics integration values
    @pdt = 0.015                   # physics update interval (sec)
    @pcur = 0.0001                 # physics update cur time
    @plast = new Date().getTime()  # physics update last time
    #console.log '@plast is ' + @plast
    @paccum = @pcur                # physics update accumulator

    # Set up update integration values
    if @client
      @udt = 0.016                 # client draw update interval
    else
      @udt = 0.045                 # server broadcast update interval
    @ucur = 0.0001                 # update cur time
    @ulast = new Date().getTime()  # update last time
    @uaccum = @ucur                # update accumulator

    # local timer for precision on server and client
    @local_time = 0.016           # the local timer
    @dt = new Date().getTime()    # the local timer delta
    @dte = new Date().getTime()   # the local timer last frame time

    @create_physics_loop()

    @create_update_loop()

    # Start a fast paced timer for measuring time easier
    @create_timer()

    # Server-specific
    if !@client
      @server_time = 0
      @laststate = {}

  add_player: (userid, server_player_instance=null) ->
    '''
    Adds a non-host player to the game.  Note that the host
    was already added as the first player when they started the game.
    '''
    if @client
      new_player = new window.PlayerClient(this)
      new_player.publicid = userid
    else
      new_player = new PlayerCore(this,
        server_player_instance)
      # PlayerCore constructor will assign id from server_player_instance

    @players.others.push(new_player)

  reset_player_positions: () ->
    '''
    When the game starts will want to move all players to their spawn positions.
    Since the player's publicid is available on both server and client, we
    sort using publicid to determine the order of spawn position for players.
    '''
    spawn_positions = [[200, 200], [600, 200], [200, 600], [600, 600]]

    # Sort player pos by publicid, since these are available on both the
    # server and the client
    all_pids = []
    all_pids.push(@players.myself.publicid)
    for player in @players.others
      all_pids.push(player.publicid)

    all_pids.sort()

    # Make a dictionary of pid : spawn position
    pid_pos = {}
    posi = 0
    for pid in all_pids
      pid_pos[pid] = spawn_positions[posi]
      posi++

    # Now assign positions for all players.  Start with myself
    pid = @players.myself.publicid
    pos = pid_pos[pid]
    @players.myself.setPos(pos[0], pos[1])
    # And now do the other players
    for player in @players.others
      pid = player.publicid
      pos = pid_pos[pid]
      player.setPos(pos[0], pos[1])

  create_physics_loop: () ->
    console.log 'CREATE PHYSICS LOOP'
    self = this
    setInterval ->
      self.update_physics()
    , (@pdt * 1000)

  update_physics: () ->
    curTime = new Date().getTime()
    @pcur = (curTime - @plast) / 1000.0
    @plast = curTime
    @paccum += @pcur
    while @paccum >= @pdt
      @paccum -= @pdt
      @do_update_physics()

  do_update_physics: () ->
    #console.log 'update physics'
    if @client
      @client_update_physics()
    else
      @server_update_physics()

  server_update_physics: () ->
    # Update location of host
    @players.myself.old_state.pos = PlayerCore.copyPos(@players.myself.pos)
    new_dir = @process_input(@players.myself)
    @players.myself.pos = PlayerCore.addPos(
      @players.myself.old_state.pos, new_dir)

    # Update location of all other players
    for player in @players.others
      player.old_state.pos = PlayerCore.copyPos(player.pos)
      new_dir = @process_input(player)
      player.pos = PlayerCore.addPos(player.old_state.pos, new_dir)

    # We've cleared the input buffer, so remove them
    @players.myself.inputs = []
    for player in @players.others
      player.inputs = []

  create_update_loop: () ->
    '''
    On the server, creates the 45 ms broadcast loop to update all the players.
    On the client, creates the 16 ms refresh loop to redraw the world state.
    '''
    console.log 'CREATE UPDATE LOOP'
    self = this
    setInterval ->
      self.update()
    , (@udt * 1000)

  update: () ->
    curTime = new Date().getTime()
    @ucur = (curTime - @ulast) / 1000.0
    @ulast = curTime
    @uaccum += @ucur
    while @uaccum >= @udt
      @uaccum -= @udt
      if @client
        @do_client_update()
      else
        @do_server_update()

  do_server_update: () ->
    '''Broadcast loop, send last state to all players'''
    #console.log 'update server'

    # Update the state of our local clock to match the timer
    @server_time = @local_time

    # Build up a dict of publicid : state for players and send it to
    # all the players.
    player_states = {}
    pid = @players.myself.publicid
    player_states[pid] = {
      pos: @players.myself.pos,
      last_input_seq: @players.myself.last_input_seq
    }
    for player in @players.others
      pid = player.publicid
      player_states[pid] = {
        pos: player.pos,
        last_input_seq: player.last_input_seq
      }

    @laststate = {
      players: player_states,
      t: @server_time
    }

    # Now emit on socket the update to all players
    if @players.myself.server_player_instance
      @players.myself.server_player_instance.emit( 
        'onserverupdate', @laststate)
    for player in @players.others
      if player.server_player_instance
        player.server_player_instance.emit(
          'onserverupdate', @laststate)

  process_input: (player) ->
    '''
    For a player, process any stored inputs in their player.inputs queue,
    and return the vector of updated position based on inputs
    '''
    # It's possible to have received multiple inputs by now, process each one
    x_dir = 0
    n_inputs = player.inputs.length
    if n_inputs > 0
      for j in [0...n_inputs] # 3 dots means exclude end of range
        # Don't process ones we have already simulated locally
        if Number(player.inputs[j].seq) <= Number(player.last_input_seq)
          continue

        input = player.inputs[j].inputs
        c = input.length
        for i in [0...c]
          key = input[i]
          if key == 'l'
            x_dir -= 1
          if key == 'r'
            x_dir += 1

    resulting_vector = { x: x_dir, y:0 }
    # update the time information of last input
    if player.inputs.length
      player.last_input_time = player.inputs[n_inputs-1].time
      player.last_input_seq = player.inputs[n_inputs-1].seq

    return resulting_vector

  handle_server_input: (client, input, input_time, input_seq) ->
    '''
    After receiving input from the client, store the inputs in the player's
    inputs queue for later processing.
    '''
    #console.log 'handle server input ' + client.userid

    # Handle host
    if client.userid == @players.myself.server_player_instance.userid
      server_input = {inputs:input, time:input_time, seq:input_seq}
      #console.log 'received server input ' + server_input
      @players.myself.inputs.push(server_input)
    # Handle non-host
    else
      for player in @players.others
        if client.userid == player.server_player_instance.userid
          server_input = {inputs:input, time:input_time, seq:input_seq}
          #console.log 'received server input ' + server_input
          player.inputs.push(server_input)

  create_timer: () ->
    '''
    Creates a timer which refreshes every 4ms for purposes of updating
    @local_time relatively accurately.
    '''
    self = this
    setInterval ->
      self.update_timer()
    , 4

  update_timer: () ->
    @dt = new Date().getTime() - @dte
    @dte = new Date().getTime()
    @local_time += @dt/1000.0

  server_load_world: () ->
    '''
    Since the server does not run a game engine, it needs to manually load
    the terrain image
    '''
    worldImg = new Image()
    worldImg.src = 'assets/images/test_load.png'
    worldImg.onLoad = this.server_world_loaded()

  server_world_loaded: () ->
    console.log 'XXX world is loaded'

class GameCoreClient extends GameCore

  # GameCoreClient constructor has no game instance, unlike GameCore
  constructor: () ->
    super null, true

    @networkHelper = new window.ClientNetwork(this)

    # Client network configuration
    @input_seq = 0          # When predicting client inputs, store last input 
                            # as sequence num
    @client_smooth = 25     # amount of smoothing to apply to client update dest

    @net_offset = 100       # 100 ms latency b/w server and client interpolation
                            # for other clients
    @buffer_size = 2        # size of server history to keep for rewind / interp
    @target_time = 0.01     # time where we want to be in the server timeline
    @oldest_tick = 0.01     # last time tick we have available in buffer

    @client_time = 0.01     # our local 'clock' = server time - client interp (net_offset)
    @server_time = 0.01     # the time server reported it was at, last we heard

    # Points to the Phaser game instance for drawing
    @phaserGame = null
    @phaserLoaded = false

    # Set up keyboard
    @keyboard = new THREEx.KeyboardState()

    # Client maintains a queue of server updates
    @server_updates = []

  # This applies local prediction for client physics, actual input needs to
  # come from server
  client_update_physics: () ->
    # Make a copy of current position
    cur_pos = @players.myself.cur_state.pos
    copy_pos = window.PlayerCore.copyPos(cur_pos)
    @players.myself.old_state.pos = copy_pos
    nd = @process_input(@players.myself)
    @players.myself.cur_state.pos = window.PlayerCore.addPos(copy_pos, nd)
    #console.log @players.myself.cur_state.pos
    @players.myself.state_time = @local_time

    # XXX In future also run physics updates on entity for gravity, etc

  do_client_update: () ->
    #console.log @local_time
    # Capture inputs from player
    @handle_client_input()

    # Network players just gets drawn normally, with interpolation from the
    # server updates, smoothing out the positions from the past.
    @client_process_net_updates()

    # When we are doing client side prediction, we smooth out our position
    # across frames using local input states we have stored
    @client_update_local_position()

  handle_client_input: () ->
    '''
    captures input from active player via keyboard, stores them in active
    player's input queue and posts them to server.
    '''
    # direction of movement
    x_dir = 0
    input = []
    @client_has_input = false

    if @keyboard.pressed('left')
      xdir = -1
      input.push('l')
      #console.log 'left'

    if @keyboard.pressed('right')
      xdir = 1
      input.push('r')
      #console.log 'right'

    # Handle input queue for this update frame
    if input.length
      # Update sequence number we are on now
      @input_seq += 1
      @players.myself.inputs.push({
        inputs: input,
        time: @local_time.toFixed(3),
        seq: @input_seq
        })

      # Create a server packet and send to server
      # input packets are labeled with an 'i' in front
      server_packet = 'i.'
      server_packet += input.join('-') + '.'
      server_packet += @local_time.toFixed(3).replace('.','-') + '.'
      server_packet += @input_seq

      #console.log server_packet

      @networkHelper.send( server_packet )

  client_process_net_updates: () ->
    '''
    This handles positions of other players, as told by the server
    '''
    #console.log 'client process net updates'
    # No updates...
    if !@server_updates.length
      return

    #console.log @server_updates.length

    # First, find the position in the updates, on the timeline
    # We call this current_time, then we find the past_pos and target_pos
    # using this, searching through the server_updates array for current_time
    # in between 2 other times.
    # Then, other player positions = lerp (past_pos, target_pos, current_time)

    # Find the position in the timeline of updates we stored
    current_time = @client_time
    count = @server_updates.length-1
    target = null
    previous = null

    # We look from the oldest updates, since the newest ones are at the
    # end (list.length-1 for example).  This will be expensive only when our
    # time is not found on the timeline, since it will run all samples.
    for i in [0...count]
      point = @server_updates[i]
      next_point = @server_updates[i+1]
      # compare our point in time with the server times we have
      if current_time > point.t && current_time < next_point.t
        target = next_point
        previous = point
        #console.log 'found update point'
        #console.log current_time
        break

    # If no target was found we store the last known server position and move
    # to that instead
    if target == null
      target = @server_updates[0]
      previous = @server_updates[0]

    # Now that we have a target and previous destination, we can interpolate 
    # between them based on where we are proportionally in time.  
    if target && previous
      @target_time = target.t

      difference = @target_time - current_time
      max_difference = (target.t - previous.t).toFixed(3)
      time_point = (difference / max_difference).toFixed(3)

      # Because target == previous in extreme cases, do some NaN safe checks
      if isNaN(time_point) || time_point == -Infinity || time_point == Infinity
        time_point = 0

      latest_server_data = @server_updates[@server_updates.length-1]
      for player in @players.others
        # These are exact server positions from this tick
        other_server_pos = latest_server_data.players[player.publicid].pos
        # The other player positions in this timeline, behind and in front of us
        other_target_pos = target.players[player.publicid].pos
        other_past_pos = previous.players[player.publicid].pos

        # client smoothing has additional smooth step
        pre_smooth_pos = window.PlayerCore.lerpPos(
          other_past_pos, other_target_pos, time_point)

        player_pos = window.PlayerCore.lerpPos(
          player.pos, pre_smooth_pos, @pdt*@client_smooth)
        player.setPos(player_pos.x, player_pos.y)

  client_update_local_position: () ->
    '''Does client prediction'''
    # Work out the time we have since we updated the state
    t = (@local_time - @players.myself.state_time) / @pdt

    # Store the states for clarity
    old_state = @players.myself.old_state.pos
    cur_state = @players.myself.cur_state.pos

    # Make sure the visual position matches the states we have stored
    @players.myself.pos = cur_state
    #console.log cur_state
    @players.myself.setPos(cur_state.x, cur_state.y)

# From here:
# http://www.matteoagosti.com/blog/2013/02/24/
#     writing-javascript-modules-for-both-browser-and-node/
# On server (node), module is defined and can add exports
if typeof module != 'undefined' && typeof module.exports != 'undefined'
  exports.GameCore = GameCore
  exports.GameCoreClient = GameCoreClient
# On client (browser) there is no module, add exports to window
else
  window.GameCore = GameCore
  window.GameCoreClient = GameCoreClient