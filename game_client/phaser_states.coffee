class PhaserBootState extends Phaser.State
  constructor: ->
    super

  preload: ->
    @assetPrefix = "assets/images/"

  create: ->
    # Put any game/screen configuration logic here
    # switch
    #   when @game.device.desktop;
    #   when @game.device.android;
    #   when @game.device.iOS;
    #   when @game.device.linux;
    #   when @game.device.macOS;

    # Move on to the next state, preloader
    @game.state.start "Preloader", true, false

class PhaserPreloaderState extends Phaser.State
  constructor: ->
    super

  preload: ->
    @assetPrefix = "assets/images/"
    @loadAssets()

  getAssetPath: (asset) ->
    return (@assetPrefix + asset)

  loadAssets: ->
    # advancedTiming allows FPS display
    @game.time.advancedTiming = true

    console.log 'Loading Phaser assets...'

    console.log @getAssetPath("background.png")
    @game.load.image("background", @getAssetPath("background.png"))
    @game.load.image("player", @getAssetPath("player_dev.png"))

  create: ->
    @game.state.start "Play", true, false

class PhaserPlayState extends Phaser.State
  constructor: ->
    super

  init: ->
    console.log 'Setting background'
    # Phaser is now fully loaded, let coreGame know
    window.coreGame.networkHelper.on_phaser_loaded()

  render: ->
    @game.debug.text(@game.time.fps || '--', 2, 14, "#00ff00")


window.PhaserBootState = PhaserBootState
window.PhaserPreloaderState = PhaserPreloaderState
window.PhaserPlayState = PhaserPlayState