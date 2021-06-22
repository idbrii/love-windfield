**windfield** is a physics module for LÖVE. It wraps LÖVE's physics API so that using box2d becomes as simple as possible.

For detailed documentation of the API see [the code](windfield/init.lua) or the [windfield documentation](https://idbrii.github.io/love-windfield/).

# Contents

* [Quick Start](#quick-start)
   * [Create a world](#create-a-world)
   * [Create colliders](#create-colliders)
   * [Create joints](#create-joints)
   * [Create collision classes](#create-collision-classes)
   * [Capture collision events](#capture-collision-events)
   * [Query the world](#query-the-world)
* [Examples & Tips](#examples-tips)
   * [Checking collisions between game objects](#checking-collisions-between-game-objects)
   * [One-way Platforms](#one-way-platforms)

<br>

# Quick Start

*See main.lua in the root of the repository for a runnable version of these examples.*

Place the `windfield` folder inside your project and require it:

```lua
wf = require 'windfield'
```

<br>

## Create a world

A physics world can be created just like in box2d. The world returned by `wf.newWorld` contains all the functions of a [LÖVE physics World](https://love2d.org/wiki/World) as well as additional ones defined by this library.

```lua
function love.load()
    world = wf.newWorld(0, 0, true)
    world:setGravity(0, 512)
end

function love.update(dt)
    world:update(dt)
end
```

<br>

## Create colliders

A collider is a composition of a single body, fixture, and shape. For most use cases whenever box2d is needed a body will only have one fixture/shape attached to it, so it makes sense to work primarily on that level of abstraction. Colliders contain all the functions of a LÖVE physics [Body](https://love2d.org/wiki/Body), [Fixture](https://love2d.org/wiki/Fixture) and [Shape](https://love2d.org/wiki/Shape) as well as additional ones defined by this library:

```lua
function love.load()
    ...

    box = world:newRectangleCollider(400 - 50/2, 0, 50, 50)
    box:setRestitution(0.8)
    box:applyAngularImpulse(5000)

    ground = world:newRectangleCollider(0, 550, 800, 50)
    wall_left = world:newRectangleCollider(0, 0, 50, 600)
    wall_right = world:newRectangleCollider(750, 0, 50, 600)
    ground:setType('static') -- Types can be 'static', 'dynamic' or 'kinematic'. Defaults to 'dynamic'
    wall_left:setType('static')
    wall_right:setType('static')
end

...

function love.draw()
    world:draw() -- The world can be drawn for debugging purposes
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/ytfhmjc.gif"/>
</p>

<br>

## Create joints

Joints are mostly unchanged from how they work normally in box2d:

```lua
function love.load()
    ...

    box_1 = world:newRectangleCollider(400 - 50/2, 0, 50, 50)
    box_1:setRestitution(0.8)
    box_2 = world:newRectangleCollider(400 - 50/2, 50, 50, 50)
    box_2:setRestitution(0.8)
    box_2:applyAngularImpulse(5000)
    joint = world:addJoint('RevoluteJoint', box_1, box_2, 400, 50, true)

    ...
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/tSqkxJR.gif"/>
</p>

<br>

## Create collision classes

Collision classes are used to make colliders ignore other colliders of certain classes and to capture collision events between colliders. The same concept goes by the name of 'collision layer' or 'collision tag' in other engines. In the example below we add a Solid and Ghost collision class. The Ghost collision class is set to ignore the Solid collision class.

```lua
function love.load()
    ...

    world:addCollisionClass('Solid')
    world:addCollisionClass('Ghost', {ignores = {'Solid'}})

    box_1 = world:newRectangleCollider(400 - 100, 0, 50, 50)
    box_1:setRestitution(0.8)
    box_2 = world:newRectangleCollider(400 + 50, 0, 50, 50)
    box_2:setCollisionClass('Ghost')

    ground = world:newRectangleCollider(0, 550, 800, 50)
    ground:setType('static')
    ground:setCollisionClass('Solid')

    ...
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/j7IhVSe.gif"/>
</p>

The box that was set be of the Ghost collision class ignored the ground and went right through it, since the ground is set to be of the Solid collision class.

<br>

## Capture collision events

Collision events can be captured inside the update function by calling the `enter`, `exit` or `stay` functions of a collider. In the example below, whenever the box collider enters contact with another collider of the Solid collision class it will get pushed to the right:

```lua
function love.update(dt)
    ...
    if box:enter('Solid') then
        box:applyLinearImpulse(1000, 0)
        box:applyAngularImpulse(5000)
    end
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/uF1bqKM.gif"/>
</p>

<br>

## Query the world

The world can be queried with a few area functions and then all colliders inside that area will be returned. In the example below, the world is queried at position 400, 300 with a circle of radius 100, and then all colliders in that area are pushed to the right and down.

```lua
function love.load()
    world = wf.newWorld(0, 0, true)
    world:setQueryDebugDrawing(true) -- Draws the area of a query for 10 frames

    colliders = {}
    for i = 1, 200 do
        table.insert(colliders, world:newRectangleCollider(love.math.random(0, 800), love.math.random(0, 600), 25, 25))
    end
end

function love.update(dt)
    world:update(dt)
end

function love.draw()
    world:draw()
end

function love.keypressed(key)
    if key == 'c' then
        local colliders = world:queryCircleArea(400, 300, 100)
        for _, collider in ipairs(colliders) do
            collider:applyLinearImpulse(1000, 1000)
        end
    elseif key == 'r' then
        local colliders = world:queryRectangleArea(400, 300, 100, 200)
        for _, collider in ipairs(colliders) do
            collider:applyLinearImpulse(1000, 1000)
        end
    elseif key == 'l' then
        local colliders = world:queryLine(40, 30, 400, 300)
        for _, collider in ipairs(colliders) do
            collider:applyLinearImpulse(1000, 1000)
        end
    end
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/YVxAiuu.gif"/>
</p>

<br>

# Examples & Tips

## Checking collisions between game objects

The most common use case for a physics engine is doing things when things collide. For instance, when the Player collides with an enemy you might want to deal damage to the player. Here's the way to achieve that with this library:


```lua
-- in Player.lua
function Player:new()
  self.collider = world:newRectangleCollider(...)
  self.collider:setCollisionClass('Player')
  self.collider:setObject(self)
end

-- in Enemy.lua
function Enemy:new()
  self.collider = world:newRectangleCollider(...)
  self.collider:setCollisionClass('Enemy')
  self.collider:setObject(self)
end
```

First we define in the constructor of both classes the collider that should be attached to them. We set their collision classes (Player and Enemy) and then link the object to the colliders with `setObject`. With this, we can capture collision events between both and then do whatever we wish when a collision happens:

```lua
-- in Player.lua
function Player:update(dt)
  if self.collider:enter('Enemy') then
    local collision_data = self.collider:getEnterCollisionData('Enemy')
    local enemy = collision_data.collider:getObject()
    -- Kills the enemy on hit but also take damage
    enemy:die()
    self:takeDamage(10)
  end
end
```

<br>

## One-way Platforms

A common problem people have with using 2D physics engines seems to be getting one-way platforms to work. Here's one way to achieve this with this library:

```lua
function love.load()
  world = wf.newWorld(0, 512, true)
  world:addCollisionClass('Platform')
  world:addCollisionClass('Player')

  ground = world:newRectangleCollider(100, 500, 600, 50)
  ground:setType('static')
  platform = world:newRectangleCollider(350, 400, 100, 20)
  platform:setType('static')
  platform:setCollisionClass('Platform')
  player = world:newRectangleCollider(390, 450, 20, 40)
  player:setCollisionClass('Player')

  player:setPreSolve(function(collider_1, collider_2, contact)
    if collider_1.collision_class == 'Player' and collider_2.collision_class == 'Platform' then
      local px, py = collider_1:getPosition()
      local pw, ph = 20, 40
      local tx, ty = collider_2:getPosition()
      local tw, th = 100, 20
      if py + ph/2 > ty - th/2 then contact:setEnabled(false) end
    end
  end)
end

function love.keypressed(key)
  if key == 'space' then
    player:applyLinearImpulse(0, -700)
  end
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/ouwxVRH.gif"/>
</p>

The way this works is that by disabling the contact before collision response is applied (so in the preSolve callback) we can make a collider ignore another. And then all we do is check to see if the player is below platform, and if he is then we disable the contact.

<br>

For more details, [see the Documentation](https://idbrii.github.io/love-windfield/).

# LICENSE

MIT.

You can do whatever you want with this. See the license at the top of windfield/init.lua

Contains davisdude/mlib under zlib license.
