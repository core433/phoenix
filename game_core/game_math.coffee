class GameMath
  floatToFixed: (num, dec=3) ->
    return parseFloat(num.toFixed(dec))

if typeof module != 'undefined' && typeof module.exports != 'undefined'
  exports.GameMath = GameMath
# On client (browser) there is no module, add exports to window
else
  window.GameMath = GameMath
