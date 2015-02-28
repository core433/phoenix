'''
Entity object

  Represents the physical (not graphical) object in the scene.
  Simulates using simple Euler integration for now.
  Has a box param which acts as its collision body (width & height)


'''
class EntityCore

  constructor: (@shost) ->
    @pos = {x: 0, y: 0}
    @vel = {x: 0, y: 0}
    @force = {x: 0, y: 0}
    @mass = 1               # define base mass as 1.  accel = f / m

    @box = {x: 0, y: 0}
    # by default @pos is the center of the Entity.
    # offset will shift the collision box relative to the center.
    @offset = {x: 0, y: 0}

  initialize: (x, y, width, height, offX, offY) ->
    @pos.x = x
    @pos.y = y
    @box.x = width
    @box.y = height
    @offset.x = offX
    @offset.y = offY

  setForce: (fx, fy) ->
    @force.x = fx
    @force.y = fy

  leftBound: () ->
    return @pos.x + @offset.x - Math.floor(@box.x/2)
  rightBound: () ->
    return @pos.x + @offset.x + Math.floor(@box.x/2)
  topBound: () ->
    return @pos.y + @offset.y - Math.floor(@box.y/2)
  botBound: () ->
    return @pos.y + @offset.y + Math.floor(@box.y/2)

  setPos: (x, y) ->
    @pos.x = x
    @pos.y = y

  getPos: () ->
    return {x: @pos.x, y: @pos.y}

  update: (dt) ->
    '''
    Physics is currently simple Euler integration, which isn't completely
    accurate, but should work fine for simple game physics
    Returns whether position changed
    '''
    old_pos = {x: @pos.x, y: @pos.y}
    @pos = {x: (@pos.x + @vel.x*dt), y: (@pos.y + @vel.y*dt)}
    accel = {x: (@force.x / mass), y: (@force.y / mass)}
    @vel = {x: (@vel.x + accel.x*dt), y: (@vel.y + accel.y*dt) }
    return old_pos.x != @pos.x && old_pos.y != @pos.y

  collidesWithEntity: (entity) ->
    '''
    Don't need to check every point of the rectangles, just need to check
    if the bottoms are outside of each others' reach
    '''
    topLeft1 = [@leftBound(), @topBound()]
    topLeft2 = [entity.leftBound(), entity.topBound()]
    botRight1 = [@rightBound(), @botBound()]
    botRight2 = [entity.rightBound(), entity.botBound()]

    if (topLeft1[0] > botRight2[0] || topLeft2[0] > botRight1[0])
      return false
    if (topLeft1[1] > botRight2[1] || topLeft2[1] > botRight1[1])
      return false

    return true

if typeof module != 'undefined' && typeof module.exports != 'undefined'
  exports.EntityCore = EntityCore
# On client (browser) there is no module, add exports to window
else
  window.EntityCore = EntityCore
