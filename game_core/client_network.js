// Generated by CoffeeScript 1.9.0
var ClientNetwork;

ClientNetwork = (function() {
  ' a helper class for handling client-server communication in game core';
  function ClientNetwork(_at_game) {
    this.game = _at_game;
    this.last_ping_time = 0.001;
    this.net_latency = 0.001;
    this.net_ping = 0.001;
    this.connect_to_server();
    this.create_ping_timer();
  }

  ClientNetwork.prototype.send = function(packet) {
    return this.socket.send(packet);
  };

  ClientNetwork.prototype.connect_to_server = function() {
    var self;
    this.socket = io.connect();
    self = this;
    this.socket.on('connect', function() {
      console.log('CLIENT CONNECT');
      return self.game.players.myself.state = 'connecting';
    });
    this.socket.on('disconnect', function(data) {
      return self.on_disconnect(data);
    });
    this.socket.on('onserverupdate', function(data) {
      return self.on_server_update_received(data);
    });
    this.socket.on('onconnected', function(data) {
      return self.on_connected(data);
    });
    this.socket.on('error', function(data) {
      return self.on_disconnect(data);
    });
    this.socket.on('message', function(data) {
      return self.on_net_message(data);
    });
    return this.socket.on('gameready', function(data) {
      return self.on_ready_game(data);
    });
  };

  ClientNetwork.prototype.on_net_message = function(data) {
    var command, commanddata, commands, self, subcommand;
    commands = data.split('.');
    command = commands[0];
    subcommand = commands[1] || null;
    commanddata = commands[2] || null;
    self = this;
    switch (command) {
      case 's':
        switch (subcommand) {
          case 'h':
            return self.on_host_game(commanddata);
          case 'j':
            return self.on_join_game(commanddata);
          case 'e':
            return self.on_disconnect(commanddata);
          case 'p':
            return self.on_ping(commanddata);
        }
    }
  };

  ClientNetwork.prototype.on_server_update_received = function(data) {
    this.game.server_time = data.t;
    this.game.client_time = this.game.server_time - this.game.net_offset / 1000;
    this.game.server_updates.push(data);
    if (this.game.server_updates.length >= 60 * this.game.buffer_size) {
      this.game.server_updates.splice(0, 1);
    }
    this.game.oldest_tick = this.game.server_updates[0].t;
    return this.process_net_prediction_correction();
  };

  ClientNetwork.prototype.process_net_prediction_correction = function() {
    var i, last_seq_i, latest_players_data, latest_server_data, my_last_input_on_server, my_server_pos, myid, num_to_clear, _i, _ref;
    if (this.game.server_updates.length === 0) {
      return;
    }
    latest_server_data = this.game.server_updates[this.game.server_updates.length - 1];
    latest_players_data = latest_server_data.players;
    myid = this.game.players.myself.publicid;
    my_server_pos = latest_players_data[myid].pos;
    my_last_input_on_server = Number(latest_players_data[myid].last_input_seq);
    if (my_last_input_on_server) {
      last_seq_i = -1;
      for (i = _i = 0, _ref = this.game.players.myself.inputs.length; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
        if (this.game.players.myself.inputs[i].seq === my_last_input_on_server) {
          last_seq_i = i;
          break;
        }
      }
      if (last_seq_i !== -1) {
        num_to_clear = Math.abs(last_seq_i - (-1));
        this.game.players.myself.inputs.splice(0, num_to_clear);
        this.game.players.myself.cur_state.pos = window.PlayerCore.copyPos(my_server_pos);
        this.game.players.myself.last_input_seq = last_seq_i;
        this.game.client_update_physics();
        return this.game.client_update_local_position();
      }
    }
  };

  ClientNetwork.prototype.on_host_game = function(data) {
    var server_time;
    server_time = parseFloat(data.replace('-', '.'));
    this.game.local_time = server_time + this.net_latency;
    this.game.players.myself.host = true;
    return this.game.players.myself.state = 'hosting.waiting for a player';
  };

  ClientNetwork.prototype.on_join_game = function(data) {
    this.game.players.myself.host = false;
    return this.game.players.myself.state = 'connected.joined.waiting';
  };

  ClientNetwork.prototype.on_ready_game = function(data) {
    var dtime, other_player_ids, pid, player, server_time, _i, _j, _len, _len1, _ref;
    dtime = data.time;
    server_time = parseFloat(dtime.replace('-', '.'));
    other_player_ids = data.ids;
    for (_i = 0, _len = other_player_ids.length; _i < _len; _i++) {
      pid = other_player_ids[_i];
      console.log('Adding player with id: ' + pid);
      this.game.add_player(pid);
    }
    this.game.local_time = server_time + this.net_latency;
    console.log('server time is about ' + this.game.local_time);
    if (this.game.players.myself.host) {
      this.game.players.myself.state = 'local_pos(hosting)';
    } else {
      this.game.players.myself.state = 'local_pos(joined)';
    }
    _ref = this.game.players.others;
    for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
      player = _ref[_j];
      if (player.host) {
        player.state = 'local_pos(hosting)';
      } else {
        player.state = 'local_pos(joined)';
      }
    }
    if (this.game.phaserLoaded) {
      return this.game.reset_player_positions();
    }
  };

  ClientNetwork.prototype.on_disconnect = function(data) {
    var player, _i, _len, _ref, _results;
    this.game.players.myself.state = 'not-connected';
    this.game.players.myself.online = false;
    _ref = this.game.players.others;
    _results = [];
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      player = _ref[_i];
      _results.push(player.state = 'not-connected');
    }
    return _results;
  };

  ClientNetwork.prototype.on_connected = function(data) {
    'The server responded that we are now in a game, this lets us\nstore the information about ourselves and kick off the game';
    this.game.players.myself.id = data.id;
    this.game.players.myself.publicid = data.publicid;
    this.game.players.myself.state = 'connected';
    this.game.players.myself.online = true;
    console.log('XXX CLIENT IS CONNECTED, ID IS ' + data.publicid);
    return window.startPhaser();
  };

  ClientNetwork.prototype.create_ping_timer = function() {
    var self;
    self = this;
    return setInterval(function() {
      this.last_ping_time = new Date().getTime();
      return this.socket.send('p.' + this.last_ping_time);
    }, 1000);
  };

  ClientNetwork.prototype.on_ping = function(data) {
    this.net_ping = new Date().getTime() - parseFloat(data);
    this.net_latency = this.net_ping / 2;
    return console.log('Server lat: ' + this.net_latency);
  };

  ClientNetwork.prototype.on_phaser_loaded = function() {
    var player, _i, _len, _ref;
    console.log('phaser load completed');
    this.game.phaserGame.stage.setBackgroundColor('#dddddd');
    this.game.phaserGame.add.sprite(0, 0, 'background');
    this.game.phaserLoaded = true;
    this.game.players.myself.initSprite();
    _ref = this.game.players.others;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      player = _ref[_i];
      player.initSprite();
    }
    return this.game.reset_player_positions();
  };

  return ClientNetwork;

})();

window.ClientNetwork = ClientNetwork;