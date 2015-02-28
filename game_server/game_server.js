var game_server = module.exports = { games : {}, game_count: 0 };
var UUID        = require('node-uuid');
var verbose     = true;
var max_players = 2;  // currently 2 for proof of concept

// Since we are sharing code with the browser, we are going to include
// some values to handle that.
global.window = global.document = global;

// need to add coffee-script/register to add coffeescript files to js files
require('coffee-script/register');
var mGameCore = require('../game_core/game_core')

game_server.log = function() {
  if (verbose)
  {
    console.log.apply(this, arguments);
  }
};

game_server.local_time = 0;
game_server._dt = new Date().getTime();
game_server._dte = new Date().getTime();

// Sets a constant interval for updating time on server, runs every 4 ms
setInterval(function() {
  game_server._dt = new Date().getTime() - game_server._dte;
  game_server._dte = new Date().getTime();
  game_server.local_time += game_server._dt/1000.0;
}, 4);

// =============================================================================
// MESSAGE AND INPUT HANDLING
// =============================================================================

// if a client just sent us a message, we don't need to return the results
// to him, we want to broadcast to all other clients but him
game_server.sendToAllButUser = function(client, message)
{
  userid = client.userid;
  game = client.game;
  if (userid != game.player_host.userid)
  {
    game.player_host.send(message);
  }
  for ( var i = 0; i < game.player_clients.length; i++ )
  {
    if (userid != game.player_clients[i].userid)
    {
      game.player_clients[i].send(message);
    }
  }
}

game_server.onMessage = function(client,message) 
{
  //console.log('Received message ' + message);
  //console.log(client.publicid);
  //Cut the message up into sub components
  var message_parts = message.split('.');
  //The first is always the type of message
  var message_type = message_parts[0];

  if(message_type == 'i') 
  {
    //Input handler will forward this
    this.onInput(client, message_parts);
  } 
  // if ping, send back ping time
  else if(message_type == 'p') 
  {
    client.send('s.p.' + message_parts[1]);
  }
  else if(message_type == 'c') //Client changed their color!
  {
    game_server.sendToAllButUser(client, 's.c.' + message_parts[1]);
  }
};

game_server.onInput = function(client, parts) {
  // The input commands come in like u-l
  // so we split them up into separate commands,
  // and then update the players
  var input_commands = parts[1].split('-');
  var input_time = parts[2].replace('-', '.');
  var input_seq = parts[3];

  // The client should be in a game, so we can tell that game
  // to handle the input
  if (client && client.game && client.game.gamecore) {
    client.game.gamecore.handle_server_input(
      client, input_commands, input_time, input_seq);
  }
};

// =============================================================================
// GAME HOSTING AND JOINING
// =============================================================================
game_server.createGame = function(player) {
  // create a new game instance
  var thegame = {
    id             : UUID(),
    player_host    : player,
    player_clients : [],
    player_count   : 1
  };

  // store this game in the list of games
  this.games[thegame.id] = thegame;

  this.game_count++;

  // Create a new game core instance, which actually runs the game code like
  // collisions and such.  In the future will probably be playerController,
  // since classes will be broken into individual files.
  thegame.gamecore = new mGameCore.GameCore( thegame );
  // Start updating the game loop on the server
  thegame.gamecore.update( new Date().getTime() );
  //thegame.gamecore.server_load_world();

  // tell the player that they are now the host
  // s = server message
  // h = you are hosting
  player.send('s.h.'+ String(thegame.gamecore.local_time).replace('.','-'));
  console.log('server host at  ' + thegame.gamecore.local_time);
  player.game = thegame;
  player.hosting = true;

  this.log('player ' + player.userid + ' created a game with id ' + player.game.id);

  return thegame;

}; // game_server.createGame

//we are requesting to kill a game in progress.
game_server.endGame = function(gameid, userid) {

  var game = this.games[gameid];
  if(game) 
  {
    //stop the game updates immediately
    // XXX This is crucial to implement
    //game.gamecore.stop_update();

    //if the game has two players, the one is leaving
    if(game.player_count > 1) 
    {
      //send the players the message the game is ending
      if(userid == game.player_host.userid)
      {
        //the host left, oh snap. Lets try join another game
        if(game.player_clients.length > 0)
        {
          //tell them the game is over
          for ( var i = 0; i < game.player_clients.length; i++ )
          {
            // s = server message
            // e = end game?
            game.player_clients[i].send('s.e');
            //now look for/create a new game.
            this.findGame(player);
          }
        }              
      }
      else 
      {
        //the other player left, we were hosting
        if(game.player_host) 
        {
          //tell the client the game is ended
          game.player_host.send('s.e');
          //i am no longer hosting, this game is going down
          game.player_host.hosting = false;
          //now look for/create a new game.
          this.findGame(game.player_host);
        }
      }
    }
    delete this.games[gameid];
    this.game_count--;

    this.log('game removed. there are now ' + this.game_count + ' games' );

  } 
  else
  {
    this.log('that game was not found!');
  }
}; //game_server.endGame

game_server.startGame = function( game ) 
{
  console.log('START GAME');
  // a game has more than 1 player and wants to begin
  // the host already knows they are hosting,
  // tell the other clients they are joining a game
  //s=server message, j=you are joining, send them the host id
  //console.log(game.player_clients);
  for ( var i = 0; i < game.player_clients.length; i++ )
  {
    game.player_clients[i].send('s.j.' + game.player_host.userid);
    game.player_clients[i].game = game;
    // add players to gamecore here
    game.gamecore.add_player(
      game.player_clients[i].userid, game.player_clients[i] );
  }

  allids = [];
  allids.push(game.player_host.publicid);
  for ( var i = 0; i < game.player_clients.length; i++ )
  {
    allids.push(game.player_clients[i].publicid);
  }

  //now we tell everyone that the game is ready to start
  //clients will reset their positions in this case.
  for ( var i = 0; i < game.player_clients.length; i++ )
  {
    // send each player everyone else's publicids
    otherids = []
    for ( var j = 0; j < allids.length; j++ )
    {
      if (allids[j] != game.player_clients[i].publicid)
      {
        otherids.push(allids[j]);
      }
    }
    game.player_clients[i].emit( 'gameready', 
      { ids:otherids, 
        time: String(game.gamecore.local_time).replace('.','-') });

    //game.player_clients[i].send(
    //  's.r.'+ String(game.gamecore.local_time).replace('.','-'));
  }
  //game.player_host.send(
  //  's.r.'+ String(game.gamecore.local_time).replace('.','-'));
  otherids = []
  for ( var i = 0; i < game.player_clients.length; i++ )
  {
    otherids.push(game.player_clients[i].publicid);
  }
  game.player_host.emit( 'gameready', 
    { ids:otherids, time:String(game.gamecore.local_time).replace('.','-') });
 
  //set this flag, so that the update loop can run it.
  game.active = true;

  // now reset player positions to start game
  game.gamecore.reset_player_positions()

}; //game_server.startGame

game_server.findGame = function(player) 
{
  this.log('looking for a game. We have : ' + this.game_count);

  //if there are games active,
  //let's see if one needs another player
  if(this.game_count) 
  {
    var joined_a_game = false;
    //Check the list of games for an open game
    for (var gameid in this.games) 
    {
      //only care about our own properties.
      if(!this.games.hasOwnProperty(gameid)) {
        continue;
      }
      //get the game we are checking against
      var game_instance = this.games[gameid];

      //If the game is a player short
      if( game_instance.player_count < max_players ) 
      {
        //someone wants us to join!
        joined_a_game = true;
        //increase the player count and store
        //the player as the client of this game
        player.game = game_instance;
        game_instance.player_clients.push(player);
        //game_instance.gamecore.players.other.instance = player;
        game_instance.player_count++;

        console.log('Joining game ' + game_instance.id)

        //start running the game on the server,
        //which will tell them to respawn/start
        if ( game_instance.player_count == max_players )
        {
          this.startGame(game_instance);
        }
      } //if less than 2 players
    } //for all games

    //now if we didn't join a game,
    //we must create one
    if(!joined_a_game) 
    {
      this.createGame(player);
    } //if no join already
  }
  else  //no games? create one!
  {
    this.createGame(player);
  }
}; //game_server.findGame



















