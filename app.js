var express   = require('express');
var http      = require('http');
var io        = require('socket.io');
var UUID      = require ('node-uuid');

var app       = express();

var server    = http.createServer(app);
var gameport  = process.env.PORT || 4004;

var verbose   = true;

server.listen(gameport);
console.log('\t :: Express :: Listening on port ' + gameport );

//By default, we forward the / path to index.html automatically.
app.get( '/', function( req, res )
  {
    console.log('trying to load %s', __dirname + '/index.html');
    res.sendfile( '/index.html' , { root:__dirname });
  });

app.get( '/*' , function( req, res, next ) {

  //This is the current file they have requested
  var file = req.params[0];

  //For debugging, we can track what files are requested.
  if(verbose) console.log('\t :: Express :: file requested : ' + file);

  //Send the requesting client the file.
  res.sendFile( __dirname + '/' + file );

}); //app.get *

// =============================================================================
// Socket.IO and Server set up
// =============================================================================
//Create a socket.io instance using our express server
var sio = io.listen(server);

//Configure the socket.io connection settings.
//See http://socket.io/
//sio.configure(function ()
//  {
//    sio.set('log level', 0);
//    sio.set('authorization', function (handshakeData, callback)
//      {
//        callback(null, true); // error first callback style
//      });
//  });

game_server = require('./game_server/game_server.js')

sio.on('connection', function (client) 
{
  //Generate a new UUID, looks something like
  //5b2ca132-64bd-4513-99da-90e838ca47d1
  //and store this on their socket/connection
  client.userid = UUID();
  // publicid is broadcast to all other players so the client's in-game 
  // avatar can be uniquely identified.  By separating userid and publicid
  // we can validate user inputs via userid and publicly name them with 
  // publicid
  client.publicid = UUID();
  
  //tell the player they connected, giving them their id
  client.emit('onconnected', { id: client.userid, publicid: client.publicid } );

  //now we can find them a game to play with someone.
  //if no game exists with someone waiting, they create one and wait.
  game_server.findGame(client);

  console.log('\t socket.io:: client ' + client.userid + ' connected');

  //Now we want to handle some of the messages that clients will send.
  //They send messages here, and we send them to the game_server to handle.
  client.on('message', function(m) {
    game_server.onMessage(client, m);
  }); //client.on message

  //When this client disconnects, we want to tell the game server
  //about that as well, so it can remove them from the game they are
  //in, and make sure the other player knows that they left and so on.
  client.on('disconnect', function () 
  {
    //Useful to know when soomeone disconnects
    console.log('\t socket.io:: client disconnected ' + client.userid);
    //If the client was in a game, set by game_server.findGame,
    //we can tell the game server to update that game state.
    if(client.game && client.game.id) 
    {
      //player leaving a game should destroy that game
      game_server.endGame(client.game.id, client.userid);
    }
  }); //client.on disconnect
}); //sio.sockets.on connection


