-- Demonstration of examples from README.md
-- Press j and k to cycle through examples.

local wf = require 'windfield'
local world
local objs = {}
local example = {
    index = 1,
    title = '',
    on_update = nil,
    created_collision_classes = {},
}

local function create_geo()
    example.title = "Create Geo"
    local ground = world:newRectangleCollider(0, 550, 800, 50)
    local wall_left = world:newRectangleCollider(0, 0, 50, 600)
    local wall_right = world:newRectangleCollider(750, 0, 50, 600)
    ground:setType('static') -- Types can be 'static', 'dynamic' or 'kinematic'. Defaults to 'dynamic'
    wall_left:setType('static')
    wall_right:setType('static')
    table.insert(objs, ground)
    table.insert(objs, wall_left)
    table.insert(objs, wall_right)
end

local function create_colliders()
    create_geo()

    example.title = "Create Colliders"
    local box = world:newRectangleCollider(400 - 50/2, 0, 50, 50)
    box:setRestitution(0.8)
    box:applyAngularImpulse(5000)
    table.insert(objs, box)
end

local function create_joints()
    create_geo()

    example.title = "Create Joints"
    local box_1 = world:newRectangleCollider(400 - 50/2, 0, 50, 50)
    box_1:setRestitution(0.8)
    local box_2 = world:newRectangleCollider(400 - 50/2, 50, 50, 50)
    box_2:setRestitution(0.8)
    box_2:applyAngularImpulse(5000)
    local joint = world:addJoint('RevoluteJoint', box_1, box_2, 400, 50, true)
    table.insert(objs, box_1)
    table.insert(objs, box_2)
    -- Don't need to track joint because it's destroyed when its associated
    -- bodies are destroyed.
end

local function create_collision_classes()
    example.title = "Create Collision Classes"
    if not example.created_collision_classes[example.title] then
        example.created_collision_classes[example.title] = true
        world:addCollisionClass('Solid')
        world:addCollisionClass('Ghost', {ignores = {'Solid'}})
    end

    local box_1 = world:newRectangleCollider(400 - 100, 0, 50, 50)
    box_1:setRestitution(0.8)
    local box_2 = world:newRectangleCollider(400 + 50, 0, 50, 50)
    box_2:setCollisionClass('Ghost')

    local ground = world:newRectangleCollider(0, 550, 800, 50)
    ground:setType('static')
    ground:setCollisionClass('Solid')

    table.insert(objs, box_1)
    table.insert(objs, box_2)
    table.insert(objs, ground)
end

local function capture_collision_events()
    create_collision_classes()
    example.title = "Capture Collision Events"
    example.on_update = function(args)
        for i,box in ipairs(objs) do
            if box:enter('Solid') then
                box:applyLinearImpulse(1000, 0)
                box:applyAngularImpulse(5000)
            end
        end
    end
end

local function respond_to_collision_events()
    example.title = "Respond to Collision Events"
    if not example.created_collision_classes[example.title] then
        example.created_collision_classes[example.title] = true
        world:addCollisionClass('Ball')
        world:addCollisionClass('Geo')
        world:addCollisionClass('IgnoreAll', {ignores = {'Ball', 'Geo'}})
    end
    world:setGravity(0, 0.5)

    local radius = 200
    local tau = math.pi * 2
    for i=0,0.9,0.05 do
        local angle = tau * i
        local x = math.cos(angle) * radius
        local y = math.sin(angle) * radius
        local ball = world:newCircleCollider(400 + x, 300 + y, 20)
        ball:setRestitution(0.8)
        ball:setCollisionClass('Ball')
        local impulse = -0.1 - i
        ball:applyLinearImpulse(x * impulse, y * impulse)
        table.insert(objs, ball)
    end

    local ground = world:newRectangleCollider(0, 550, 800, 50)
    ground:setType('static')
    ground:setCollisionClass('Geo')
    table.insert(objs, ground)

    local directions = {1, -1}
    example.on_update = function(args)
        local debris = {}
        for _,ball in ipairs(objs) do
            if ball:enter('Ball') then
                -- On collision, create some balls that fly off orthogonal to
                -- the normal. Not particularly useful, but a simple
                -- demonstration of using collision data.
                local collision_data = ball:getEnterCollisionData('Ball')
                local px,py = collision_data.contact:getPositions()
                if px and py then
                    local nx,ny = collision_data.contact:getNormal()
                    local fx,fy = ny,-nx -- normal rotated 90 degrees
                    local force = 100
                    local debris_radius = 5
                    for i,direction in ipairs(directions) do
                        local chunk = world:newCircleCollider(px + fx * debris_radius * direction, py + fy * debris_radius * direction, debris_radius)
                        chunk:setCollisionClass('IgnoreAll')
                        chunk:applyLinearImpulse(fx * direction * force, fy * direction * force)
                        table.insert(debris, chunk)
                    end
                end
            end
        end
        for _,d in ipairs(debris) do
            table.insert(objs, d)
        end
    end
end

local function query_the_world()
    create_geo()

    example.title = "Query The World - press C, R, L, or P"
    world:setQueryDebugDrawing(true) -- Draws the area of a query for 10 frames
    world:setGravity(0, 0)

    example.on_keypressed = function(key)
        if key == 'c' then
            local colliders = world:queryCircleArea(400, 300, 100)
            for _, collider in ipairs(colliders) do
                collider:applyLinearImpulse(-1000, 1000)
            end
        elseif key == 'r' then
            local colliders = world:queryRectangleArea(400, 300, 100, 200)
            for _, collider in ipairs(colliders) do
                collider:applyLinearImpulse(1000, -1000)
            end
        elseif key == 'l' then
            local colliders = world:queryLine(40, 30, 400, 300)
            for _, collider in ipairs(colliders) do
                collider:applyLinearImpulse(1000, 1000)
            end
        elseif key == 'p' then
            local colliders = world:queryPolygonArea({100,200, 400,200, 500,400, 0,400})
            for _, collider in ipairs(colliders) do
                collider:applyLinearImpulse(0, 1000)
            end
        end
    end

    for i = 1, 200 do
        table.insert(objs, world:newRectangleCollider(love.math.random(40, 760), love.math.random(40, 560), 25, 25))
    end
end

local function one_way_platforms()
    example.title = "One Way Platforms - press space"
    if not example.created_collision_classes[example.title] then
        example.created_collision_classes[example.title] = true
        world:addCollisionClass('Platform')
        world:addCollisionClass('Player')
    end

    local ground = world:newRectangleCollider(100, 500, 600, 50)
    ground:setType('static')
    local platform = world:newRectangleCollider(350, 400, 100, 20)
    platform:setType('static')
    platform:setCollisionClass('Platform')
    local player = world:newRectangleCollider(390, 450, 20, 40)
    player:setCollisionClass('Player')
    table.insert(objs, ground)
    table.insert(objs, platform)
    table.insert(objs, player)

    player:setPreSolve(function(collider_1, collider_2, contact)
        if collider_1.collision_class == 'Player' and collider_2.collision_class == 'Platform' then
            local px, py = collider_1:getPosition()
            local pw, ph = 20, 40
            local tx, ty = collider_2:getPosition()
            local tw, th = 100, 20
            if py + ph/2 > ty - th/2 then contact:setEnabled(false) end
        end
    end)

    example.on_keypressed = function(key)
        if key == 'space' then
            player:applyLinearImpulse(0, -700)
        end
    end
end


local example_list = {
    create_colliders,
    create_joints,
    create_collision_classes,
    capture_collision_events,
    query_the_world,
    one_way_platforms,
    -- More elaborate examples not included in README.
    respond_to_collision_events,
}

-- Loops input value i within range [1, n]. Useful for circular lists.
local function loop(i, n)
    local z = i - 1
    return (z % n) + 1
end

local function noop(...) end
local function switch_example(direction)
    example.index = loop(example.index + direction, #example_list)
    -- Reset state.
    for i,collider in ipairs(objs) do
        collider:destroy()
    end
    objs = {}
    world:setGravity(0, 512)
    world:setQueryDebugDrawing(false)
    example.on_update = noop
    example.on_keypressed = noop

    example_list[example.index]()
end

function love.load()
    world = wf.newWorld(0, 0, true)
    world:setGravity(0, 512)
    switch_example(0)
end

function love.draw()
    love.graphics.print(example.title, 80,20)
    world:draw() -- The world can be drawn for debugging purposes
end

function love.update(dt)
    world:update(dt)
    example.on_update()
end

function love.keypressed(key)
    -- Query the world with p
    if key == 'j' then
        switch_example(1)
    elseif key == 'k' then
        switch_example(-1)
    elseif key == 'escape' then
        love.event.quit()
    end
    example.on_keypressed(key)
end
