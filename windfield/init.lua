--[[
The MIT License (MIT)

Copyright (c) 2018 SSYGEN

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]--

local path = ... .. '.'

--- windfield is a physics module for LÖVE. It wraps LÖVE's physics API so that
-- using box2d becomes as simple as possible.
local wf = {}
wf.Math = require(path .. 'mlib.mlib')


local function wf_class()
    local c = {}
    c.__index = c
    function c.new(...)
        local instance = setmetatable({}, c)
        instance:init(...)
        return instance
    end
    return c
end

local function replace_list_with(dst, ...)
    for i,val in ipairs(dst) do
        dst[i] = nil
    end
    for i=1,select('#', ...) do
        local val = select(i, ...)
        table.insert(dst, val)
    end
end


-- A readonly version of love's Contact to allow us to cache their contacts but
-- provide the same API.
local Contact = wf_class()

function Contact:init(original)
    self.fixtures  = {}
    self.normal    = {}
    self.positions = {}
    self:assign(original)
end

function Contact:assign(original)
    replace_list_with(self.fixtures,  original:getFixtures())
    replace_list_with(self.normal,    original:getNormal())
    replace_list_with(self.positions, original:getPositions())
    self.friction    = original:getFriction()
    self.restitution = original:getRestitution()
    self.enabled     = original:isEnabled()
    self.touching    = original:isTouching()
end

function Contact:clone()
    return Contact.new(self)
end

function Contact:getFixtures()
    return unpack(self.fixtures)
end
function Contact:getNormal()
    return unpack(self.normal)
end
function Contact:getPositions()
    return unpack(self.positions)
end
function Contact:getFriction()
    return self.friction
end
function Contact:getRestitution()
    return self.restitution
end
function Contact:isEnabled()
    return self.enabled
end
function Contact:isTouching()
    return self.touching
end


local World = wf_class()

--- Creates a new World.
--
-- newWorld(number, number, boolean) -> table
--
-- number: xg The world's x gravity component
-- number: yg The world's y gravity component
-- boolean: sleep=true Whether the world's bodies are allowed to sleep
--
-- return: table: World the World object, containing all attributes and methods defined below as well as all of a [box2d World](https://love2d.org/wiki/World)
--
-- usage:
--     world = wf.newWorld(0, 0, true)
function wf.newWorld(xg, yg, sleep)
    local world = wf.World.new(xg, yg, sleep)

    world.box2d_world:setCallbacks(world.collisionOnEnter, world.collisionOnExit, world.collisionPre, world.collisionPost)
    world:collisionClear()
    world:addCollisionClass('Default')

    -- Points all box2d_world functions to this wf.World object
    -- This means that the user can call world:setGravity for instance without having to say world.box2d_world:setGravity
    for k, v in pairs(world.box2d_world.__index) do
        if k ~= '__gc' and k ~= '__eq' and k ~= '__index' and k ~= '__tostring' and k ~= 'update' and k ~= 'destroy' and k ~= 'type' and k ~= 'typeOf' then
            world[k] = function(self, ...)
                return v(self.box2d_world, ...)
            end
        end
    end

    return world
end

function World:init(xg, yg, sleep)
    self.draw_query_for_n_frames = 10
    self.query_debug_drawing_enabled = false
    self.explicit_collision_events = false
    self.collision_classes = {}
    self.masks = {}
    self.is_sensor_memo = {}
    self.query_debug_draw = {}
    self.contact_pool = {}
    self.next_contact = 1

    love.physics.setMeter(32)
    self.box2d_world = love.physics.newWorld(xg, yg, sleep)
end

--- Updates the world to allow bodies to continue their motion and starts a new frame for collision events.
--
-- update(number) -> nil
--
-- number: dt The time step delta
--
-- usage:
--     world:update(dt)
function World:update(dt)
    self.next_contact = 1 -- release all
    self:collisionEventsClear()
    self.box2d_world:update(dt)
end

--- Draws the world visualizing colliders, joints, and world queries (for debugging purposes).
--
-- draw(number) -> nil
--
-- number: alpha=1 The optional alpha value to use when drawing, defaults to 1.
--
-- usage:
--     world:draw() -- default drawing
--     world:draw(128) -- semi transparent drawing
function World:draw(alpha)
    -- get the current color values to reapply
    local r, g, b, a = love.graphics.getColor()
    local linewidth = love.graphics.getLineWidth()
    -- alpha value is optional
    alpha = alpha or 1
    -- Colliders debug
    love.graphics.setColor(0.87, 0.87, 0.87, alpha)
    love.graphics.setLineWidth(1)
    local bodies = self.box2d_world:getBodies()
    for _, body in ipairs(bodies) do
        local fixtures = body:getFixtures()
        for _, fixture in ipairs(fixtures) do
            if fixture:getShape():type() == 'PolygonShape' then
                love.graphics.polygon('line', body:getWorldPoints(fixture:getShape():getPoints()))
            elseif fixture:getShape():type() == 'EdgeShape' or fixture:getShape():type() == 'ChainShape' then
                local points = {body:getWorldPoints(fixture:getShape():getPoints())}
                for i = 1, #points, 2 do
                    if i < #points-2 then love.graphics.line(points[i], points[i+1], points[i+2], points[i+3]) end
                end
            elseif fixture:getShape():type() == 'CircleShape' then
                local body_x, body_y = body:getPosition()
                local shape_x, shape_y = fixture:getShape():getPoint()
                local radius = fixture:getShape():getRadius()
                love.graphics.circle('line', body_x + shape_x, body_y + shape_y, radius, 360)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, alpha)

    -- Joint debug
    love.graphics.setColor(0.87, 0.50, 0.25, alpha)
    local joints = self.box2d_world:getJoints()
    for _, joint in ipairs(joints) do
        local x1, y1, x2, y2 = joint:getAnchors()
        if x1 and y1 then love.graphics.circle('line', x1, y1, 4) end
        if x2 and y2 then love.graphics.circle('line', x2, y2, 4) end
        if x1 and y1 and x2 and y2 then love.graphics.line(x1, y1, x2, y2) end
    end
    love.graphics.setColor(1, 1, 1, alpha)

    -- Query debug
    love.graphics.setColor(0.25, 0.25, 0.87, alpha)
    for _, query_draw in ipairs(self.query_debug_draw) do
        query_draw.frames = query_draw.frames - 1
        if query_draw.type == 'circle' then
            love.graphics.circle('line', query_draw.x, query_draw.y, query_draw.r)
        elseif query_draw.type == 'rectangle' then
            love.graphics.rectangle('line', query_draw.x, query_draw.y, query_draw.w, query_draw.h)
        elseif query_draw.type == 'line' then
            love.graphics.line(query_draw.x1, query_draw.y1, query_draw.x2, query_draw.y2)
        elseif query_draw.type == 'polygon' then
            local triangles = love.math.triangulate(query_draw.vertices)
            for _, triangle in ipairs(triangles) do love.graphics.polygon('line', triangle) end
        end
    end
    for i = #self.query_debug_draw, 1, -1 do
        if self.query_debug_draw[i].frames <= 0 then
            table.remove(self.query_debug_draw, i)
        end
    end
    love.graphics.setColor(r, g, b, a)
    love.graphics.setLineWidth(linewidth)
end

--- Sets query debug drawing to be active or not.
-- If active, then collider queries will be drawn to the screen for 10 frames. This is used for debugging purposes and incurs a performance penalty. Don't forget to turn it off!
--
-- setQueryDebugDrawing(boolean) -> nil
--
-- boolean: value Whether query debug drawing is active
--
-- usage:
--     world:setQueryDebugDrawing(true)
function World:setQueryDebugDrawing(value)
    self.query_debug_drawing_enabled = value
end

--- Sets collision events to be explicit or not.
-- If explicit, then collision events will only be generated between collision classes when they are specified in `addCollisionClasses`. By default this is set to false, meaning that collision events are generated between all collision classes. The main reason why you might want to set this to true is for performance, since not generating collision events between every collision class will require less computation. This function must be called before any collision class is added to the world.
--
-- setExplicitCollisionEvents(boolean) -> nil
--
-- boolean: value Whether collision events are explicit
--
-- usage:
--     world:setExplicitCollisionEvents(true)
function World:setExplicitCollisionEvents(value)
    self.explicit_collision_events = value
end

--- Adds a new collision class to the World.
-- Collision classes are attached to Colliders and defined their behaviors in terms of which ones will physically ignore each other and which ones will generate collision events between each other. All collision classes must be added before any Collider is created. If `world:setExplicitCollisionEvents` is set to false (the default setting) then *enter*, *exit*, *pre*, and *post* settings don't need to be specified, otherwise they do.
--
-- addCollisionClass(string, table) -> nil
--
-- string: collision_class_name The unique name of the collision class
--
-- {[string]={}}: collision_class The collision class definition. Mostly specifying collision class names that should generate collision events with the collider of this collision class at different points in time.
--     collision_class = {
--          ignores = {}, -- physically ignore
--          enter = {}, -- collision events when they *enter* contact with each other
--          exit = {}, -- collision events when they *exit* contact with each other
--          pre = {}, -- collision events *just before* collision response is applied
--          post = {}, -- collision events *right after* collision response is applied
--     }
--
-- usage:
--     world:addCollisionClass('Player', {ignores = {'NPC', 'Enemy'}})
function World:addCollisionClass(collision_class_name, collision_class)
    self:_addCollisionClassWithoutRebuild(collision_class_name, collision_class)
    self:collisionClassesSet()
end

--- Adds multiple new collision classes to the World.
--
-- Allows you to add multiple collision classes that ignore each other without
-- worrying about specifying them in a specific order.
--
-- @see `World:addCollisionClass`
--
-- addCollisionClassTable(table) -> nil
--
-- {[string]={[string]={}}}: definition_map A map of collision class names to their definitions. Definitions are the same as collision_class in `World:addCollisionClass`.
--
-- usage:
--     world:addCollisionClassTable({
--         Player = {ignores = {'NPC', 'Enemy'}},
--         NPC = {},
--         Enemy = {ignores = {'NPC'}},
--     })
function World:addCollisionClassTable(definition_map)
    for collision_class_name, collision_class in pairs(definition_map) do
        self:_addCollisionClassWithoutRebuild(collision_class_name, collision_class)
    end
    self:collisionClassesSet()
end

function World:_addCollisionClassWithoutRebuild(collision_class_name, collision_class)
    if self.collision_classes[collision_class_name] then error('Collision class ' .. collision_class_name .. ' already exists.') end

    if self.explicit_collision_events then
        self.collision_classes[collision_class_name] = collision_class or {}
    else
        self.collision_classes[collision_class_name] = collision_class or {}
        self.collision_classes[collision_class_name].enter = {}
        self.collision_classes[collision_class_name].exit = {}
        self.collision_classes[collision_class_name].pre = {}
        self.collision_classes[collision_class_name].post = {}
        for c_class_name, _ in pairs(self.collision_classes) do
            table.insert(self.collision_classes[collision_class_name].enter, c_class_name)
            table.insert(self.collision_classes[collision_class_name].exit, c_class_name)
            table.insert(self.collision_classes[collision_class_name].pre, c_class_name)
            table.insert(self.collision_classes[collision_class_name].post, c_class_name)
        end
        for c_class_name, _ in pairs(self.collision_classes) do
            table.insert(self.collision_classes[c_class_name].enter, collision_class_name)
            table.insert(self.collision_classes[c_class_name].exit, collision_class_name)
            table.insert(self.collision_classes[c_class_name].pre, collision_class_name)
            table.insert(self.collision_classes[c_class_name].post, collision_class_name)
        end
    end
end

function World:collisionClassesSet()
    self:generateCategoriesMasks()

    self:collisionClear()
    local collision_table = self:getCollisionCallbacksTable()
    for collision_class_name, collision_list in pairs(collision_table) do
        for _, collision_info in ipairs(collision_list) do
            if collision_info.type == 'enter' then self:addCollisionEnter(collision_class_name, collision_info.other) end
            if collision_info.type == 'exit' then self:addCollisionExit(collision_class_name, collision_info.other) end
            if collision_info.type == 'pre' then self:addCollisionPre(collision_class_name, collision_info.other) end
            if collision_info.type == 'post' then self:addCollisionPost(collision_class_name, collision_info.other) end
        end
    end

    self:collisionEventsClear()
end

function World:collisionClear()
    -- Clear lists of collision reactions. These lists indicate which collision
    -- classes generate collision events when interacting with other collision
    -- classes.
    self.collisions = {}
    self.collisions.on_enter = {}
    self.collisions.on_enter.sensor = {}
    self.collisions.on_enter.non_sensor = {}
    self.collisions.on_exit = {}
    self.collisions.on_exit.sensor = {}
    self.collisions.on_exit.non_sensor = {}
    self.collisions.pre = {}
    self.collisions.pre.sensor = {}
    self.collisions.pre.non_sensor = {}
    self.collisions.post = {}
    self.collisions.post.sensor = {}
    self.collisions.post.non_sensor = {}
end

function World:collisionEventsClear()
    local bodies = self.box2d_world:getBodies()
    for _, body in ipairs(bodies) do
        local collider = body:getFixtures()[1]:getUserData()
        collider:collisionEventsClear()
    end
end

function World:_addCollisionReaction(target, type1, type2)
    if not self:isCollisionBetweenSensors(type1, type2) then
        table.insert(target.non_sensor, {type1 = type1, type2 = type2})
    else table.insert(target.sensor, {type1 = type1, type2 = type2}) end
end

function World:addCollisionEnter(type1, type2)
    self:_addCollisionReaction(self.collisions.on_enter, type1, type2)
end

function World:addCollisionExit(type1, type2)
    self:_addCollisionReaction(self.collisions.on_exit, type1, type2)
end

function World:addCollisionPre(type1, type2)
    self:_addCollisionReaction(self.collisions.pre, type1, type2)
end

function World:addCollisionPost(type1, type2)
    self:_addCollisionReaction(self.collisions.post, type1, type2)
end

function World:doesType1IgnoreType2(type1, type2)
    local collision_ignores = {}
    for collision_class_name, collision_class in pairs(self.collision_classes) do
        collision_ignores[collision_class_name] = collision_class.ignores or {}
    end
    local all = {}
    for collision_class_name, _ in pairs(collision_ignores) do
        table.insert(all, collision_class_name)
    end
    local ignored_types = {}
    for _, collision_class_type in ipairs(collision_ignores[type1]) do
        if collision_class_type == 'All' then
            for _, collision_class_name in ipairs(all) do
                table.insert(ignored_types, collision_class_name)
            end
        else table.insert(ignored_types, collision_class_type) end
    end
    for key, _ in pairs(collision_ignores[type1]) do
        if key == 'except' then
            for _, except_type in ipairs(collision_ignores[type1].except) do
                for i = #ignored_types, 1, -1 do
                    if ignored_types[i] == except_type then table.remove(ignored_types, i) end
                end
            end
        end
    end
    for _, ignored_type in ipairs(ignored_types) do
        if ignored_type == type2 then return true end
    end
end

function World:isCollisionBetweenSensors(type1, type2)
    if not self.is_sensor_memo[type1] then self.is_sensor_memo[type1] = {} end
    if not self.is_sensor_memo[type1][type2] then self.is_sensor_memo[type1][type2] = (self:doesType1IgnoreType2(type1, type2) or self:doesType1IgnoreType2(type2, type1)) end
    if self.is_sensor_memo[type1][type2] then return true
    else return false end
end

-- https://love2d.org/forums/viewtopic.php?f=4&t=75441
function World:generateCategoriesMasks()
    local collision_ignores = {}
    for collision_class_name, collision_class in pairs(self.collision_classes) do
        collision_ignores[collision_class_name] = collision_class.ignores or {}
    end
    local incoming = {}
    local expanded = {}
    local all = {}
    for object_type, _ in pairs(collision_ignores) do
        incoming[object_type] = {}
        expanded[object_type] = {}
        table.insert(all, object_type)
    end
    for object_type, ignore_list in pairs(collision_ignores) do
        for key, ignored_type in pairs(ignore_list) do
            if ignored_type == 'All' then
                for _, all_object_type in ipairs(all) do
                    table.insert(incoming[all_object_type], object_type)
                    table.insert(expanded[object_type], all_object_type)
                end
            elseif type(ignored_type) == 'string' then
                if ignored_type ~= 'All' then
                    table.insert(incoming[ignored_type], object_type)
                    table.insert(expanded[object_type], ignored_type)
                end
            end
            if key == 'except' then
                for _, except_ignored_type in ipairs(ignored_type) do
                    for i, v in ipairs(incoming[except_ignored_type]) do
                        if v == object_type then
                            table.remove(incoming[except_ignored_type], i)
                            break
                        end
                    end
                end
                for _, except_ignored_type in ipairs(ignored_type) do
                    for i, v in ipairs(expanded[object_type]) do
                        if v == except_ignored_type then
                            table.remove(expanded[object_type], i)
                            break
                        end
                    end
                end
            end
        end
    end
    local edge_groups = {}
    for k, v in pairs(incoming) do
        table.sort(v, function(a, b) return string.lower(a) < string.lower(b) end)
    end
    local i = 0
    for k, v in pairs(incoming) do
        local str = ""
        for _, c in ipairs(v) do
            str = str .. c
        end
        if not edge_groups[str] then i = i + 1; edge_groups[str] = {n = i} end
        table.insert(edge_groups[str], k)
    end
    local categories = {}
    for k, _ in pairs(collision_ignores) do
        categories[k] = {}
    end
    for k, v in pairs(edge_groups) do
        for j, c in ipairs(v) do
            categories[c] = v.n
        end
    end
    for k, v in pairs(expanded) do
        local category = {categories[k]}
        local current_masks = {}
        for _, c in ipairs(v) do
            table.insert(current_masks, categories[c])
        end
        self.masks[k] = {categories = category, masks = current_masks}
    end
end

function World:getCollisionCallbacksTable()
    local collision_table = {}
    for collision_class_name, collision_class in pairs(self.collision_classes) do
        collision_table[collision_class_name] = {}
        for i,transition in ipairs({'enter', 'exit', 'pre', 'post'}) do
            for _, v in ipairs(collision_class[transition] or {}) do
                table.insert(collision_table[collision_class_name], {type = transition, other = v})
            end
        end
    end
    return collision_table
end

local function collEnsure(collision_class_name1, a, collision_class_name2, b)
    if a.collision_class == collision_class_name2 and b.collision_class == collision_class_name1 then return b, a
    else return a, b end
end

local function collIf(collision_class_name1, collision_class_name2, a, b)
    if (a.collision_class == collision_class_name1 and b.collision_class == collision_class_name2) or
       (a.collision_class == collision_class_name2 and b.collision_class == collision_class_name1) then
       return true
    else return false end
end


local function getCollisionReactionList(on_transition, a, b, fixture_a, fixture_b)
    if not a or not b then
        return nil
    elseif fixture_a:isSensor() and fixture_b:isSensor() then
        return a.world.collisions[on_transition].sensor
    elseif not (fixture_a:isSensor() or fixture_b:isSensor()) then
        return a.world.collisions[on_transition].non_sensor
    end
end

local function collisionTransition(transition, on_transition, fixture_a, fixture_b, contact)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    local target_list = getCollisionReactionList(on_transition, a, b, fixture_a, fixture_b)
    if target_list then
        -- love doesn't guarantee Contacts survive beyond this callback (they
        -- may be destroyed in the same frame as creation). Make a copy so
        -- users can access later in the frame. Prevents "Attempt to use
        -- destroyed contact."
        contact = a.world:_acquireContact(contact)
        for _, collision in ipairs(target_list) do
            if collIf(collision.type1, collision.type2, a, b) then
                a, b = collEnsure(collision.type1, a, collision.type2, b)
                table.insert(a.collision_events[collision.type2], {collision_type = transition, collider_1 = a, collider_2 = b, contact = contact})
                if collision.type1 == collision.type2 then
                    table.insert(b.collision_events[collision.type1], {collision_type = transition, collider_1 = b, collider_2 = a, contact = contact})
                end
            end
        end
    end
end

function World:_acquireContact(contact)
    -- Pool contacts since we create them on every collision even if the user
    -- isn't querying them.
    local copy = self.contact_pool[self.next_contact]
    if copy then
        copy:assign(contact)
        self.next_contact = self.next_contact + 1
    else
        self.next_contact = nil
        copy = Contact.new(contact)
        table.insert(self.contact_pool, copy)
    end
    return copy
end

function World.collisionOnEnter(fixture_a, fixture_b, contact)
    collisionTransition('enter', 'on_enter', fixture_a, fixture_b, contact)
end

function World.collisionOnExit(fixture_a, fixture_b, contact)
    collisionTransition('exit', 'on_exit', fixture_a, fixture_b, contact)
end

local function collisionSolve(solver, transition, fixture_a, fixture_b, ...)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    local target_list = getCollisionReactionList(transition, a, b, fixture_a, fixture_b)
    if target_list then
        for _, collision in ipairs(target_list) do
            if collIf(collision.type1, collision.type2, a, b) then
                a, b = collEnsure(collision.type1, a, collision.type2, b)
                a[solver](a, b, ...)
                if collision.type1 == collision.type2 then
                    b[solver](b, a, ...)
                end
            end
        end
    end
end

function World.collisionPre(fixture_a, fixture_b, contact)
    collisionSolve('preSolve', 'pre', fixture_a, fixture_b, contact)
end

function World.collisionPost(fixture_a, fixture_b, contact, ni1, ti1, ni2, ti2)
    collisionSolve('postSolve', 'post', fixture_a, fixture_b, contact, ni1, ti1, ni2, ti2)
end

--- Creates a new CircleCollider.
--
-- newCircleCollider(number, number, number) -> table
--
-- number: x The x position of the circle's center
-- number: y The y position of the circle's center
-- number: r The radius of the circle
--
-- return: table: Collider The created CircleCollider
--
-- usage:
--     circle = world:newCircleCollider(100, 100, 30)
function World:newCircleCollider(x, y, r, settings)
    return wf.Collider.new(self, 'Circle', x, y, r, settings)
end

--- Creates a new RectangleCollider.
--
-- newRectangleCollider(number, number, number, number) -> table
--
-- number: x The x position of the rectangle's top-left corner
-- number: y The y position of the rectangle's top-left corner
-- number: w The width of the rectangle
-- number: h The height of the rectangle
--
-- return: table: Collider The created RectangleCollider
--
-- usage:
--     rectangle = world:newRectangleCollider(100, 100, 50, 50)
function World:newRectangleCollider(x, y, w, h, settings)
    return wf.Collider.new(self, 'Rectangle', x, y, w, h, settings)
end

--- Creates a new BSGRectangleCollider, which is a rectangle with its corners cut (an octagon).
--
-- newBSGRectangleCollider(number, number, number, number, number) -> table
--
-- number: x The x position of the rectangle's top-left corner
-- number: y The y position of the rectangle's top-left corner
-- number: w The width of the rectangle
-- number: h The height of the rectangle
-- number: corner_cut_size The corner cut size
--
-- return: table: Collider The created BSGRectangleCollider
--
-- usage:
--     bsg_rectangle = world:newBSGRectangleCollider(100, 100, 50, 50, 5)
function World:newBSGRectangleCollider(x, y, w, h, corner_cut_size, settings)
    return wf.Collider.new(self, 'BSGRectangle', x, y, w, h, corner_cut_size, settings)
end

--- Creates a new PolygonCollider.
--
-- newPolygonCollider({number}) -> table
--
-- {number}: vertices The polygon vertices as a table of numbers
--
-- return: table: Collider The created PolygonCollider
--
-- usage:
--     polygon = world:newPolygonCollider({10, 10, 10, 20, 20, 20, 20, 10})
function World:newPolygonCollider(vertices, settings)
    return wf.Collider.new(self, 'Polygon', vertices, settings)
end

--- Creates a new LineCollider.
--
-- newLineCollider(number, number, number, number) -> table
--
-- number: x1 The x position of the first point of the line
-- number: y1 The y position of the first point of the line
-- number: x2 The x position of the second point of the line
-- number: y2 The y position of the second point of the line
--
-- return: table: Collider The created LineCollider
--
-- usage:
--     line = world:newLineCollider(100, 100, 200, 200)
function World:newLineCollider(x1, y1, x2, y2, settings)
    return wf.Collider.new(self, 'Line', x1, y1, x2, y2, settings)
end

--- Creates a new ChainCollider.
--
-- newChainCollider({number}, boolean) -> table
--
-- {number}: vertices The chain vertices as a table of numbers
-- boolean: loop If the chain should loop back from the last to the first point
--
-- return: table: Collider The created ChainCollider
--
-- usage:
--     chain = world:newChainCollider({10, 10, 10, 20, 20, 20}, true)
function World:newChainCollider(vertices, loop, settings)
    return wf.Collider.new(self, 'Chain', vertices, loop, settings)
end

-- Internal AABB box2d query used before going for more specific and precise computations.
function World:_queryBoundingBox(x1, y1, x2, y2)
    local colliders = {}
    local callback = function(fixture)
        if not fixture:isSensor() then table.insert(colliders, fixture:getUserData()) end
        return true
    end
    self.box2d_world:queryBoundingBox(x1, y1, x2, y2, callback)
    return colliders
end

function World:collisionClassInCollisionClassesList(collision_class, collision_classes)
    if collision_classes[1] == 'All' then
        local all_collision_classes = {}
        for class, _ in pairs(self.collision_classes) do
            table.insert(all_collision_classes, class)
        end
        if collision_classes.except then
            for _, except in ipairs(collision_classes.except) do
                for i, class in ipairs(all_collision_classes) do
                    if class == except then
                        table.remove(all_collision_classes, i)
                        break
                    end
                end
            end
        end
        for _, class in ipairs(all_collision_classes) do
            if class == collision_class then return true end
        end
    else
        for _, class in ipairs(collision_classes) do
            if class == collision_class then return true end
        end
    end
end

--- Queries a circular area around a point for colliders.
--
-- queryCircleArea(number, number, number, {string}) -> {Collider}
--
-- number: x The x position of the circle's center
-- number: y The y position of the circle's center
-- number: radius The radius of the circle
-- {string}: [collision_class_names='All'] A table of strings with collision class names to be queried. The special value `'All'` (default) can be used to query for all existing collision classes. Another special value `except` can be used to exclude some collision classes when `'All'` is used.
--
-- return: {Collider}: The table of colliders with the specified collision classes inside the area
--
-- usage:
--     colliders_1 = world:queryCircleArea(100, 100, 50, {'Enemy', 'NPC'})
--     colliders_2 = world:queryCircleArea(100, 100, 50, {'All', except = {'Player'}})
function World:queryCircleArea(x, y, radius, collision_class_names)
    if not collision_class_names then collision_class_names = {'All'} end
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, {type = 'circle', x = x, y = y, r = radius, frames = self.draw_query_for_n_frames}) end

    local colliders = self:_queryBoundingBox(x-radius, y-radius, x+radius, y+radius)
    local outs = {}
    for _, collider in ipairs(colliders) do
        if self:collisionClassInCollisionClassesList(collider.collision_class, collision_class_names) then
            for _, fixture in ipairs(collider.body:getFixtures()) do
                if fixture:getShape():getType() == 'circle' then
                    local x2, y2 = collider.body:getWorldPoint(fixture:getShape():getPoint())
                    if wf.Math.circle.getCircleIntersection(x, y, radius, x2 , y2 , fixture:getShape():getRadius()) then
                        table.insert(outs, collider)
                        break
                    end
                else
                    if wf.Math.polygon.getCircleIntersection(x, y, radius, {collider.body:getWorldPoints(fixture:getShape():getPoints())}) then
                        table.insert(outs, collider)
                        break
                    end
                end
            end
        end
    end
    return outs
end

--- Queries a rectangular area for colliders.
--
-- queryRectangleArea(number, number, number, number, {string}) -> {Collider}
--
-- number: x The x position of the rectangle's top-left corner
-- number: y The y position of the rectangle's top-left corner
-- number: w The width of the rectangle
-- number: h The height of the rectangle
-- {string}: [collision_class_names='All'] A table of strings with collision class names to be queried. The special value `'All'` (default) can be used to query for all existing collision classes. Another special value `except` can be used to exclude some collision classes when `'All'` is used.
--
-- return: {Collider}: The table of colliders with the specified collision classes inside the area
--
-- usage:
--     colliders_1 = world:queryRectangleArea(100, 100, 50, 50, {'Enemy', 'NPC'})
--     colliders_2 = world:queryRectangleArea(100, 100, 50, 50, {'All', except = {'Player'}})
function World:queryRectangleArea(x, y, w, h, collision_class_names)
    if not collision_class_names then collision_class_names = {'All'} end
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, {type = 'rectangle', x = x, y = y, w = w, h = h, frames = self.draw_query_for_n_frames}) end

    local colliders = self:_queryBoundingBox(x, y, x+w, y+h)
    local outs = {}
    for _, collider in ipairs(colliders) do
        if self:collisionClassInCollisionClassesList(collider.collision_class, collision_class_names) then
            for _, fixture in ipairs(collider.body:getFixtures()) do
                if fixture:getShape():getType() == 'circle' then
                    local x2, y2 = collider.body:getWorldPoint(fixture:getShape():getPoint())
                    if wf.Math.polygon.isCircleInside(x2, y2, fixture:getShape():getRadius(), {x, y, x+w, y, x+w, y+h, x, y+h}) or
                        wf.Math.polygon.getCircleIntersection(x2, y2, fixture:getShape():getRadius(), {x, y, x+w, y, x+w, y+h, x, y+h}) then
                        table.insert(outs, collider)
                        break
                    end
                else
                    if wf.Math.polygon.isPolygonInside({x, y, x+w, y, x+w, y+h, x, y+h}, {collider.body:getWorldPoints(fixture:getShape():getPoints())}) then
                        table.insert(outs, collider)
                        break
                    end
                end
            end
        end
    end
    return outs
end

--- Queries a polygon area for colliders.
--
-- queryPolygonArea({number}, {string}) -> {Collider}
--
-- {number}: vertices The polygon vertices as a table of numbers
-- {string}: [collision_class_names='All'] A table of strings with collision class names to be queried. The special value `'All'` (default) can be used to query for all existing collision classes. Another special value `except` can be used to exclude some collision classes when `'All'` is used.
--
-- return: {Collider}: The table of colliders with the specified collision classes inside the area
--
-- usage:
--     colliders_1 = world:queryPolygonArea({10, 10, 20, 10, 20, 20, 10, 20}, {'Enemy'})
--     colliders_2 = world:queryPolygonArea({10, 10, 20, 10, 20, 20, 10, 20}, {'All', except = {'Player'}})
function World:queryPolygonArea(vertices, collision_class_names)
    if not collision_class_names then collision_class_names = {'All'} end
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, {type = 'polygon', vertices = vertices, frames = self.draw_query_for_n_frames}) end

    local cx, cy = wf.Math.polygon.getCentroid(vertices)
    local d_max = 0
    for i = 1, #vertices, 2 do
        local d = wf.Math.line.getLength(cx, cy, vertices[i], vertices[i+1])
        if d > d_max then d_max = d end
    end
    local colliders = self:_queryBoundingBox(cx-d_max, cy-d_max, cx+d_max, cy+d_max)
    local outs = {}
    for _, collider in ipairs(colliders) do
        if self:collisionClassInCollisionClassesList(collider.collision_class, collision_class_names) then
            for _, fixture in ipairs(collider.body:getFixtures()) do
                if fixture:getShape():getType() == 'circle' then

                    local x2, y2 = collider.body:getWorldPoint(fixture:getShape():getPoint())
                    if wf.Math.polygon.isCircleInside(x2, y2, fixture:getShape():getRadius(), vertices) or
                        wf.Math.polygon.getCircleIntersection(x2, y2, fixture:getShape():getRadius(), vertices) then
                        table.insert(outs, collider)
                        break
                    end
                else
                    if wf.Math.polygon.isPolygonInside(vertices, {collider.body:getWorldPoints(fixture:getShape():getPoints())}) then
                        table.insert(outs, collider)
                        break
                    end
                end
            end
        end
    end
    return outs
end

--- Queries for colliders that intersect with a line.
--
-- queryLine(number, number, number, number, {string}) -> {Collider}
--
-- number: x1 The x position of the first point of the line
-- number: y1 The y position of the first point of the line
-- number: x2 The x position of the second point of the line
-- number: y2 The y position of the second point of the line
-- {string}: [collision_class_names='All'] A table of strings with collision class names to be queried. The special value `'All'` (default) can be used to query for all existing collision classes. Another special value `except` can be used to exclude some collision classes when `'All'` is used.
--
-- return: {Collider}: The table of colliders with the specified collision classes inside the area
--
-- usage:
--     colliders_1 = world:queryLine(100, 100, 200, 200, {'Enemy', 'NPC', 'Projectile'})
--     colliders_2 = world:queryLine(100, 100, 200, 200, {'All', except = {'Player'}})
function World:queryLine(x1, y1, x2, y2, collision_class_names)
    if not collision_class_names then collision_class_names = {'All'} end
    if self.query_debug_drawing_enabled then
        table.insert(self.query_debug_draw, {type = 'line', x1 = x1, y1 = y1, x2 = x2, y2 = y2, frames = self.draw_query_for_n_frames})
    end

    local colliders = {}
    local callback = function(fixture, ...)
        if not fixture:isSensor() then table.insert(colliders, fixture:getUserData()) end
        return 1
    end
    self.box2d_world:rayCast(x1, y1, x2, y2, callback)

    local outs = {}
    for _, collider in ipairs(colliders) do
        if self:collisionClassInCollisionClassesList(collider.collision_class, collision_class_names) then
            table.insert(outs, collider)
        end
    end
    return outs
end

--- Adds a joint to the world.
--
-- addJoint(string, any) -> Joint
--
-- string: joint_type The joint type, it can be `'DistanceJoint'`, `'FrictionJoint'`, `'GearJoint'`, `'MouseJoint'`, `'PrismaticJoint'`, `'PulleyJoint'`, `'RevoluteJoint'`, `'RopeJoint'`, `'WeldJoint'` or `'WheelJoint'`
-- any: ... The joint creation arguments that are different for each joint type, check [Joint](https://love2d.org/wiki/Joint) for more details
--
-- return: Joint: joint The created Joint
--
-- usage:
--     joint = world:addJoint('RevoluteJoint', collider_1, collider_2, 50, 50, true)
function World:addJoint(joint_type, ...)
    local args = {...}
    if args[1].body then args[1] = args[1].body end
    if type(args[2]) == "table" and args[2].body then args[2] = args[2].body end
    local joint = love.physics['new' .. joint_type](unpack(args))
    return joint
end

--- Removes a joint from the world.
--
-- removeJoint(Joint) -> nil
--
-- Joint: joint The joint to be removed
--
-- usage:
--     joint = world:addJoint('RevoluteJoint', collider_1, collider_2, 50, 50, true)
--     world:removeJoint(joint)
function World:removeJoint(joint)
    joint:destroy()
end

--- Destroys the collider and removes it from the world.
-- This must be called whenever the Collider is to discarded otherwise it will result in it not getting collected (and so memory will leak).
--
-- destroy() -> nil
--
-- usage:
--     collider:destroy()
function World:destroy()
    local bodies = self.box2d_world:getBodies()
    for _, body in ipairs(bodies) do
        local collider = body:getFixtures()[1]:getUserData()
        collider:destroy()
    end
    local joints = self.box2d_world:getJoints()
    for _, joint in ipairs(joints) do joint:destroy() end
    self.box2d_world:destroy()
    self.box2d_world = nil
end



local Collider = wf_class()

local generator = love.math.newRandomGenerator(os.time())
local function UUID()
    local fn = function(x)
        local r = generator:random(16) - 1
        r = (x == "x") and (r + 1) or (r % 4) + 9
        return ("0123456789abcdef"):sub(r, r)
    end
    return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", fn))
end

function Collider:init(world, collider_type, ...)
    self.id = UUID()
    self.world = world
    self.type = collider_type
    self.object = nil

    self.shapes = {}
    self.fixtures = {}
    self.sensors = {}

    self.collision_events = {}
    self.collision_stay = {}
    self.enter_collision_data = {}
    self.exit_collision_data = {}
    self.stay_collision_data = {}

    local args = {...}
    local shape, fixture
    if self.type == 'Circle' then
        self.collision_class = (args[4] and args[4].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, args[1], args[2], (args[4] and args[4].body_type) or 'dynamic')
        shape = love.physics.newCircleShape(args[3])

    elseif self.type == 'Rectangle' then
        self.collision_class = (args[5] and args[5].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, args[1] + args[3]/2, args[2] + args[4]/2, (args[5] and args[5].body_type) or 'dynamic')
        shape = love.physics.newRectangleShape(args[3], args[4])

    elseif self.type == 'BSGRectangle' then
        self.collision_class = (args[6] and args[6].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, args[1] + args[3]/2, args[2] + args[4]/2, (args[6] and args[6].body_type) or 'dynamic')
        local w, h, s = args[3], args[4], args[5]
        shape = love.physics.newPolygonShape({
            -w/2, -h/2 + s, -w/2 + s, -h/2,
             w/2 - s, -h/2, w/2, -h/2 + s,
             w/2, h/2 - s, w/2 - s, h/2,
            -w/2 + s, h/2, -w/2, h/2 - s
        })

    elseif self.type == 'Polygon' then
        self.collision_class = (args[2] and args[2].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, 0, 0, (args[2] and args[2].body_type) or 'dynamic')
        shape = love.physics.newPolygonShape(unpack(args[1]))

    elseif self.type == 'Line' then
        self.collision_class = (args[5] and args[5].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, 0, 0, (args[5] and args[5].body_type) or 'dynamic')
        shape = love.physics.newEdgeShape(args[1], args[2], args[3], args[4])

    elseif self.type == 'Chain' then
        self.collision_class = (args[3] and args[3].collision_class) or 'Default'
        self.body = love.physics.newBody(self.world.box2d_world, 0, 0, (args[3] and args[3].body_type) or 'dynamic')
        shape = love.physics.newChainShape(args[1], unpack(args[2]))
    end

    -- Define collision classes and attach them to fixture and sensor
    fixture = love.physics.newFixture(self.body, shape)
    if self.world.masks[self.collision_class] then
        fixture:setCategory(unpack(self.world.masks[self.collision_class].categories))
        fixture:setMask(unpack(self.world.masks[self.collision_class].masks))
    end
    fixture:setUserData(self)
    local sensor = love.physics.newFixture(self.body, shape)
    sensor:setSensor(true)
    sensor:setUserData(self)

    self.shapes['main'] = shape
    self.fixtures['main'] = fixture
    self.sensors['main'] = sensor
    self.shape = shape
    self.fixture = fixture

    self.preSolve = function() end
    self.postSolve = function() end

    -- Points all body, fixture and shape functions to this wf.Collider object
    -- This means that the user can call collider:setLinearVelocity for instance without having to say collider.body:setLinearVelocity
    for k, v in pairs(self.body.__index) do
        if k ~= '__gc' and k ~= '__eq' and k ~= '__index' and k ~= '__tostring' and k ~= 'destroy' and k ~= 'type' and k ~= 'typeOf' then
            self[k] = function(this, ...)
                return v(this.body, ...)
            end
        end
    end
    for k, v in pairs(self.fixture.__index) do
        if k ~= '__gc' and k ~= '__eq' and k ~= '__index' and k ~= '__tostring' and k ~= 'destroy' and k ~= 'type' and k ~= 'typeOf' then
            self[k] = function(this, ...)
                return v(this.fixture, ...)
            end
        end
    end
    for k, v in pairs(self.shape.__index) do
        if k ~= '__gc' and k ~= '__eq' and k ~= '__index' and k ~= '__tostring' and k ~= 'destroy' and k ~= 'type' and k ~= 'typeOf' then
            self[k] = function(this, ...)
                return v(this.shape, ...)
            end
        end
    end
end

function Collider:collisionEventsClear()
    self.collision_events = {}
    for other, _ in pairs(self.world.collision_classes) do
        self.collision_events[other] = {}
    end
end

--- Sets this collider's collision class.
-- The collision class must be a valid one previously added with `world:addCollisionClass`.
--
-- setCollisionClass(string) -> nil
--
-- string: collision_class_name The name of the collision class
--
-- usage:
--     world:addCollisionClass('Player')
--     collider = world:newRectangleCollider(100, 100, 50, 50)
--     collider:setCollisionClass('Player')
function Collider:setCollisionClass(collision_class_name)
    if not self.world.collision_classes[collision_class_name] then error("Collision class " .. collision_class_name .. " doesn't exist.") end
    self.collision_class = collision_class_name
    for _, fixture in pairs(self.fixtures) do
        if self.world.masks[collision_class_name] then
            fixture:setCategory(unpack(self.world.masks[collision_class_name].categories))
            fixture:setMask(unpack(self.world.masks[collision_class_name].masks))
        end
    end
end

--- Checks for collision enter events from this collider with another.
-- Enter events are generated on the frame when one collider enters contact with another.
--
-- enter(string) -> boolean
--
-- string: other_collision_class_name The name of the target collision class
--
-- return: boolean: If the enter collision event between both colliders happened on this frame or not
--
-- usage:
--     -- in some update function
--     if collider:enter('Enemy') then
--         print('Collision entered!')
--     end
function Collider:enter(other_collision_class_name)
    local events = self.collision_events[other_collision_class_name]
    if events and #events >= 1  then
        for _, e in ipairs(events) do
            if e.collision_type == 'enter' then
                if not self.collision_stay[other_collision_class_name] then self.collision_stay[other_collision_class_name] = {} end
                table.insert(self.collision_stay[other_collision_class_name], {collider = e.collider_2, contact = e.contact})
                self.enter_collision_data[other_collision_class_name] = {collider = e.collider_2, contact = e.contact}
                return true
            end
        end
    end
end

--- Gets the collision data generated from the last collision enter event.
-- Only valid after calling Collider:enter.
--
-- getEnterCollisionData(string) -> {Collider, Contact}
--
-- string: other_collision_class_name The name of the target collision class
--
-- return: {Collider, Contact}: collision_data A table containing the Collider and the [Contact](https://love2d.org/wiki/Contact) generated from the last enter collision event. The Contact is read-only (only get* and is* methods exist) and will become invalid on the next call to World:update, but you can use contact:clone() to create a permanent copy.
--
-- usage:
--     -- in some update function
--     if collider:enter('Enemy') then
--         local collision_data = collider:getEnterCollisionData('Enemy')
--         print(collision_data.collider, collision_data.contact)
--     end
function Collider:getEnterCollisionData(other_collision_class_name)
    return self.enter_collision_data[other_collision_class_name]
end

--- Checks for collision exit events from this collider with another.
-- Exit events are generated on the frame when one collider exits contact with another.
--
-- exit(string) -> boolean
--
-- string: other_collision_class_name The name of the target collision class
--
-- return: boolean: If the exit collision event between both colliders happened on this frame or not
--
-- usage:
--     -- in some update function
--     if collider:exit('Enemy') then
--         print('Collision exited!')
--     end
function Collider:exit(other_collision_class_name)
    local events = self.collision_events[other_collision_class_name]
    if events and #events >= 1  then
        for _, e in ipairs(events) do
            if e.collision_type == 'exit' then
                if self.collision_stay[other_collision_class_name] then
                    for i = #self.collision_stay[other_collision_class_name], 1, -1 do
                        local collision_stay = self.collision_stay[other_collision_class_name][i]
                        if collision_stay.collider.id == e.collider_2.id then table.remove(self.collision_stay[other_collision_class_name], i) end
                    end
                end
                self.exit_collision_data[other_collision_class_name] = {collider = e.collider_2, contact = e.contact}
                return true
            end
        end
    end
end

--- Gets the collision data generated from the last collision exit event.
-- Only valid after calling Collider:exit.
--
-- getExitCollisionData(string) -> {Collider, Contact}
--
-- string: other_collision_class_name The name of the target collision class
--
-- return: {Collider, Contact}: collision_data A table containing the Collider and the [Contact](https://love2d.org/wiki/Contact) generated from the last exit collision event. The Contact is read-only (only get* and is* methods exist) and will become invalid on the next call to World:update, but you can use contact:clone() to create a permanent copy.
--
-- usage:
--     -- in some update function
--     if collider:exit('Enemy') then
--         local collision_data = collider:getExitCollisionData('Enemy')
--         print(collision_data.collider, collision_data.contact)
--     end
function Collider:getExitCollisionData(other_collision_class_name)
    return self.exit_collision_data[other_collision_class_name]
end

--- Checks for collision stay events from this collider with another.
-- Stay events are generated on every frame when one collider is in contact with another.
--
-- stay(string) -> boolean
--
-- string: other_collision_class_name The name of the target collision class
--
-- return: boolean: Whether the stay collision event between both colliders is happening on this frame
--
-- usage:
--     -- in some update function
--     if collider:stay('Enemy') then
--         print('Collision staying!')
--     end
function Collider:stay(other_collision_class_name)
    if self.collision_stay[other_collision_class_name] then
        if #self.collision_stay[other_collision_class_name] >= 1 then
            return true
        end
    end
end

--- Gets the collision data generated from the last collision stay event
-- Only valid after calling Collider:stay.
--
-- getStayCollisionData(string) -> {{Collider, Contact}}
--
-- string: other_collision_class_name The name of the target collision class
--
-- return: {{Collider, Contact}}: collision_data_list A table containing multiple Colliders and [Contacts](https://love2d.org/wiki/Contact) generated from the last stay collision event. Usually this list will be of size 1, but sometimes this collider will be staying in contact with multiple other colliders on the same frame, and so those multiple stay events (with multiple colliders) are returned. The Contact is read-only (only get* and is* methods exist) and will become invalid on the next call to World:update, but you can use contact:clone() to create a permanent copy.
--
-- usage:
--     -- in some update function
--     if collider:stay('Enemy') then
--         local collision_data_list = collider:getStayCollisionData('Enemy')
--         for _, collision_data in ipairs(collision_data_list) do
--             print(collision_data.collider, collision_data.contact)
--         end
--     end
function Collider:getStayCollisionData(other_collision_class_name)
    return self.collision_stay[other_collision_class_name]
end

--- Sets the preSolve callback.
-- Unlike `:enter` or `:exit`, which can be delayed and checked after the physics simulation is done for this frame, both preSolve and postSolve must be callbacks that are resolved immediately, since they may change how the rest of the simulation plays out on this frame.
--
-- You cannot modify the World inside of the preSolve callback because the
-- underlying Box2D world will be locked. See also
-- [World:setCallbacks](https://love2d.org/wiki/World:setCallbacks).
--
-- setPreSolve(function) -> nil
--
-- function: callback The preSolve callback. Receives `collider_1`, `collider_2`, and `contact` as arguments
--
-- usage:
--     collider:setPreSolve(function(collider_1, collider_2, contact)
--         contact:setEnabled(false)
--     end
function Collider:setPreSolve(callback)
    self.preSolve = callback
end

--- Sets the postSolve callback.
-- Unlike `:enter` or `:exit`, which can be delayed and checked after the physics simulation is done for this frame, both preSolve and postSolve must be callbacks that are resolved immediately, since they may change how the rest of the simulation plays out on this frame.
--
-- You cannot modify the World inside of the postSolve callback because the
-- underlying Box2D world will be locked. See also
-- [World:setCallbacks](https://love2d.org/wiki/World:setCallbacks).
--
-- setPostSolve(function) -> nil
--
-- function: callback The postSolve callback. Receives `collider_1`, `collider_2`, `contact`, `normal_impulse1`, `tangent_impulse1`, `normal_impulse2`, and `tangent_impulse2` as arguments
--
-- usage:
--     collider:setPostSolve(function(collider_1, collider_2, contact, ni1, ti1, ni2, ti2)
--         contact:setEnabled(false)
--     end
function Collider:setPostSolve(callback)
    self.postSolve = callback
end

--- Sets the collider's object.
-- This is useful to set the object that the collider belongs to, so that when a query call is made and colliders are returned you can immediately get the pertinent object.
--
-- setObject(any) -> nil
--
-- any: object The object that this collider belongs to
--
-- usage:
--     -- in the constructor of some object
--     self.collider = world:newRectangleCollider(...)
--     self.collider:setObject(self)
function Collider:setObject(object)
    self.object = object
end

--- Gets the object that a collider belongs to.
--
-- getObject() -> any
--
-- return: any: object The object that is attached to this collider
--
-- usage:
--     -- in an update function
--     if self.collider:enter('Enemy') then
--         local collision_data = self.collider:getEnterCollisionData('SomeTag')
--         -- gets the reference to the enemy object, the enemy object must have used :setObject(self) to attach itself to the collider otherwise this wouldn't work
--         local enemy = collision_data.collider:getObject()
--     end
function Collider:getObject()
    return self.object
end

--- Adds a shape to the collider.
-- A shape can be accessed via collider.shapes[shape_name]. A fixture of the same name is also added to attach the shape to the collider body. A fixture can be accessed via collider.fixtures[fixture_name].
--
-- addShape(string, string, any) -> nil
--
-- string: shape_name The unique name of the shape
-- string: shape_type The shape type, can be `'ChainShape'`, `'CircleShape'`, `'EdgeShape'`, `'PolygonShape'` or `'RectangleShape'`
-- any: ... The shape creation arguments that are different for each shape. Check [Shape](https://love2d.org/wiki/Shape) for more details
--
function Collider:addShape(shape_name, shape_type, ...)
    if self.shapes[shape_name] or self.fixtures[shape_name] then error("Shape/fixture " .. shape_name .. " already exists.") end
    local args = {...}
    local shape = love.physics['new' .. shape_type](unpack(args))
    local fixture = love.physics.newFixture(self.body, shape)
    if self.world.masks[self.collision_class] then
        fixture:setCategory(unpack(self.world.masks[self.collision_class].categories))
        fixture:setMask(unpack(self.world.masks[self.collision_class].masks))
    end
    fixture:setUserData(self)
    local sensor = love.physics.newFixture(self.body, shape)
    sensor:setSensor(true)
    sensor:setUserData(self)

    self.shapes[shape_name] = shape
    self.fixtures[shape_name] = fixture
    self.sensors[shape_name] = sensor
end

--- Removes a shape from the collider (also removes the accompanying fixture).
--
-- removeShape(string) -> nil
--
-- string: shape_name The unique name of the shape to be removed. Must be a name previously added with `:addShape`
--
function Collider:removeShape(shape_name)
    if not self.shapes[shape_name] then return end
    self.shapes[shape_name] = nil
    self.fixtures[shape_name]:setUserData(nil)
    self.fixtures[shape_name]:destroy()
    self.fixtures[shape_name] = nil
    self.sensors[shape_name]:setUserData(nil)
    self.sensors[shape_name]:destroy()
    self.sensors[shape_name] = nil
end

--- Destroys the collider and removes it from the world.
-- This must be called whenever the Collider is to discarded otherwise it will result in it not getting collected (and so memory will leak).
--
-- destroy() -> nil
--
-- usage:
--     collider:destroy()
function Collider:destroy()
    self.collision_stay = nil
    self.enter_collision_data = nil
    self.exit_collision_data = nil
    self:collisionEventsClear()

    self:setObject(nil)
    for name, _ in pairs(self.fixtures) do
        self.shapes[name] = nil
        self.fixtures[name]:setUserData(nil)
        self.fixtures[name] = nil
        self.sensors[name]:setUserData(nil)
        self.sensors[name] = nil
    end
    self.body:destroy()
    self.body = nil
end

wf.World = World
wf.Collider = Collider

return wf

