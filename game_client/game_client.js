
var game = {};

window.onload = function()
{
  //alert('client load');
  //console.log('WINDOW LOAD CLIENT');
  this.coreGame = new window.GameCoreClient();
  //console.log(coreGame);
  //game.update( new Date().getTime() );
};

window.startPhaser = function()
{
  //alert('starting phaser');
  window.phaserGame = new Phaser.Game(1024, 768, Phaser.CANVAS, "viewport");
  //this.game.client_on_phaser_loaded();
  //window.phaserGame.stage.setBackgroundColor('#FF0000');

  this.coreGame.phaserGame = window.phaserGame;

  // name of state, state object, autostart
  window.phaserGame.state.add('Boot', new PhaserBootState(), false);
  window.phaserGame.state.add('Preloader', new PhaserPreloaderState(), false);
  window.phaserGame.state.add('Play', new PhaserPlayState(), false);
  // name of state, clearWorld, clearCache, additional parameters
  window.phaserGame.state.start('Boot', true, false, null);
};