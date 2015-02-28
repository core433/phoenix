

class ClientNetwork
  ''' a helper class for handling client-server communication in game core'''
  constructor: (@game) ->

    @last_ping_time = 0.001   # last time we sent a ping
    @net_latency = 0.001      # latency b/w the client and the server (ping/2)
    @net_ping = 0.001         # round trip time from here to server and back

    @connect_to_server()

    @create_ping_timer()

  send: (packet) ->
    @socket.send(packet)

  connect_to_server: () ->
    #console.log 'CLIENT CONNECT TO SERVER'
    @socket = io.connect()

    self = this

    @socket.on('connect', ->
      console.log 'CLIENT CONNECT'
      self.game.players.myself.state = 'connecting'
      )

    # Sent when we are disconnected (network, server down, etc)
    @socket.on('disconnect', (data)->
      self.on_disconnect(data)
      )
    # Sent each tick of the server update loop, authoritative update
    @socket.on('onserverupdate', (data)->
      self.on_server_update_received(data)
      )
    # When the client is successfully connected to the server
    @socket.on('onconnected', (data)->
      self.on_connected(data)
      )
    # On error we just show that we are not connected for now.  Can print data
    @socket.on('error', (data)->
      self.on_disconnect(data)
      )
    # Server sent us a message
    @socket.on('message', (data)->
      self.on_net_message(data)
      )
    # Server sent us game ready, and all other player public ids
    @socket.on('gameready', (data) ->
      self.on_ready_game(data)
      )

  on_net_message: (data) ->
    #console.log 'RECEIVED MESSAGE ' + data

    commands = data.split('.')
    command = commands[0]
    subcommand = commands[1] || null
    commanddata = commands[2] || null

    self = this

    switch command
      when 's' then switch subcommand     # server message

        # host a game requested
        when 'h' then self.on_host_game( commanddata )

        # join a game requested
        when 'j' then self.on_join_game( commanddata )

        # ready a game requested
        # XXX This is no longer used, using on_ready_game emit
        #when 'r' then self.on_ready_game( commanddata )

        # end game requested
        when 'e' then self.on_disconnect( commanddata )

        # server ping
        when 'p' then self.on_ping( commanddata )

  on_server_update_received: (data) ->

    # Store the server time (this is offset by latency in the network by the
    # time we get it)
    @game.server_time = data.t
    # Update our local offset time from the last server update
    @game.client_time = @game.server_time - @game.net_offset/1000

    # The naive approach is to set the position directly as the server tells you
    # This is a common mistake and causes somewhat playable results on a local
    # LAN, for example, but causes terrible lag when any ping/latency is
    # introduced.  The player can not deduce any information to interpolate
    # with so it misses positions, and packet loss destroys this approach even
    # more.  See 'bouncing ball problem' on Wikipedia.

    # So...
    # Cache the data from the server, and then play the timeline back to
    # the player with a small delay (net offset), allowing interpolation
    # between the points
    @game.server_updates.push(data)

    # We limit the buffer in seconds worth of updates
    # 60 fps * buffer seconds = number of samples
    if @game.server_updates.length >= 60 * @game.buffer_size
      @game.server_updates.splice(0,1)

    # We can see when the last tick we know of happened.
    # If client_time gets behind this due to latency, a snap occurs to the last
    # tick.  Unavoidable, and a really bad connection here.
    # If that happens it might be best to drop the game after a period of time
    @game.oldest_tick = @game.server_updates[0].t

    # Handle the latest position from the server and make sure to correct out
    # local predictions, making the server have final say.
    @process_net_prediction_correction()

  process_net_prediction_correction: () ->
    # No updates...
    if @game.server_updates.length == 0
      return

    # The most recent server update
    latest_server_data = @game.server_updates[@game.server_updates.length-1]
    latest_players_data = latest_server_data.players

    # Our latest server position
    myid = @game.players.myself.publicid
    my_server_pos = latest_players_data[myid].pos
    #console.log my_server_pos

    # Here we handle our local input prediction, by correcting it with
    # the server and reconciling its differences
    my_last_input_on_server = Number(latest_players_data[myid].last_input_seq)
    if my_last_input_on_server
      # The last input sequence index in my local input list
      last_seq_i = -1
      for i in [0...@game.players.myself.inputs.length]
        #console.log @game.players.myself.inputs[i].seq
        if @game.players.myself.inputs[i].seq == my_last_input_on_server
          last_seq_i = i
          break
      #console.log last_seq_i
      # Now we can crop the list of any updates we have already processed
      if last_seq_i != -1
        # So, now we've gotten an acknowledgement from the server that our
        # inputs here have been accepted and that we can predict from this
        # known position instead

        # remove the rest of the inputs we have confirmed on the server
        num_to_clear = Math.abs(last_seq_i - (-1))
        @game.players.myself.inputs.splice(0, num_to_clear)
        # The player is now located at the new server position, authoritative
        @game.players.myself.cur_state.pos = window.PlayerCore.copyPos(
          my_server_pos)
        @game.players.myself.last_input_seq = last_seq_i
        # Now we reapply all the inputs that we have stored locally that
        # the server hasn't yet confirmed.  This will 'keep' our position
        # the same but also confirm the server position at the same time
        #console.log 'Applying net prediction correction'
        @game.client_update_physics()
        @game.client_update_local_position()


  on_host_game: (data) ->
    # The server sends the time when asking us to host
    server_time = parseFloat(data.replace('-','.'))
    # We get an estimate of the current time on the server
    @game.local_time = server_time + @net_latency

    @game.players.myself.host = true
    @game.players.myself.state = 'hosting.waiting for a player'

  on_join_game: (data) ->
    @game.players.myself.host = false
    @game.players.myself.state = 'connected.joined.waiting'

  on_ready_game: (data) ->
    dtime = data.time
    server_time = parseFloat(dtime.replace('-', '.'))

    other_player_ids = data.ids
    for pid in other_player_ids
      console.log 'Adding player with id: ' + pid
      @game.add_player(pid)

    @game.local_time = server_time + @net_latency
    console.log 'server time is about ' + @game.local_time

    if @game.players.myself.host
      @game.players.myself.state = 'local_pos(hosting)'
    else
      @game.players.myself.state = 'local_pos(joined)'

    for player in @game.players.others
      if player.host
        player.state = 'local_pos(hosting)'
      else
        player.state = 'local_pos(joined)'

    # Now that we have all the other players added, can call
    # reset_player_positions
    if @game.phaserLoaded
      @game.reset_player_positions()

  on_disconnect: (data) ->
    @game.players.myself.state = 'not-connected'
    @game.players.myself.online = false

    for player in @game.players.others
      player.state = 'not-connected'

  on_connected: (data) ->
    '''
    The server responded that we are now in a game, this lets us
    store the information about ourselves and kick off the game
    '''
    @game.players.myself.id = data.id
    @game.players.myself.publicid = data.publicid
    @game.players.myself.state = 'connected'
    @game.players.myself.online = true
    #
    # XXX This is probably where we should load phaser
    console.log 'XXX CLIENT IS CONNECTED, ID IS ' + data.publicid
    window.startPhaser()

  create_ping_timer: () ->
    self = this
    setInterval ->
      this.last_ping_time = new Date().getTime()
      @socket.send('p.' + this.last_ping_time)
      #console.log 'ping server'
    , 1000

  # The server sends our own ping time back to us, so that gives us
  # the round trip latency
  on_ping: (data) ->
    @net_ping = new Date().getTime() - parseFloat( data )
    @net_latency = @net_ping/2
    console.log 'Server lat: ' + @net_latency

  on_phaser_loaded: () ->
    # XXX Call this once phaser is done loading and playable, and notify
    # game server to kick off game start countdown
    console.log 'phaser load completed'
    @game.phaserGame.stage.setBackgroundColor('#dddddd')
    #background = new Phaser.Sprite(@phaserGame, 0, 0, 'background')
    @game.phaserGame.add.sprite(0,0,'background')
    @game.phaserLoaded = true

    # Some sprites might have been deferred until now because the game core
    # can load before phaser finishes loading, in which case process
    # any missing phaser inits here
    @game.players.myself.initSprite()
    for player in @game.players.others
      player.initSprite()

    @game.reset_player_positions()

# This class only exists on the client, so just export to window
window.ClientNetwork = ClientNetwork