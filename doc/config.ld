project='windfield'
package='windfield'
title='windfield documentation'

format='markdown'
-- Plain renders our arguments all on one line.
--~ format='plain'

-- Doesn't seem to do anything
--~ backtick_references=true
file='../windfield'
dir='./out'
readme='../README.md'

-- Our license notice doesn't seem to cause a problem, so maybe we don't need boilerplate.
--~ boilerplate=true

-- I prefer colon, but released ldoc doesn't properly support. github ldoc
-- requires `type: name description`. Instead, don't try to process args and
-- just show the text I wrote.
colon=true
--~ no_return_or_parms=true

-- ldoc uses 'bool' instead of lua's 'boolean'
tparam_alias('boolean','bool')
-- ldoc uses 'func' instead of lua's 'function'
tparam_alias('function','func')
-- ldoc uses 'tab' instead of lua's 'table'
tparam_alias('table','tab')
tparam_alias('{}','tab')
-- ldoc doesn't seem to define an "unknown" type
tparam_alias('any')

local love_physics_types = {
    'Body',
    'ChainShape',
    'CircleShape',
    'Contact',
    'DistanceJoint',
    'EdgeShape',
    'Fixture',
    'FrictionJoint',
    'GearJoint',
    'Joint',
    'MotorJoint',
    'MouseJoint',
    'PolygonShape',
    'PrismaticJoint',
    'PulleyJoint',
    'RevoluteJoint',
    'RopeJoint',
    'Shape',
    'WeldJoint',
    'WheelJoint',
    'World',
}
for i=1,#love_physics_types do -- no ipairs in config files
    local kind = love_physics_types[i]
    tparam_alias(kind)
end

-- Put basic types in {} tables
local basic_types = {
    'string',
    'number',
    'bool',
    'any',
}
for i=1,#basic_types do -- no ipairs in config files
    local kind = basic_types[i]
    -- Map tables
    for j=1,#basic_types do
        -- ldoc implies it would work with {[string]=Bonzo,...}, but it
        -- doesn't. Create aliases for an abbreviated version of that.
        local key_kind = ('{[%s]=%s}'):format(kind, basic_types[j])
        local table_kind = ('{[%s]={[%s]={}}}'):format(kind, basic_types[j])
        -- Value in some table keyed by strings
        tparam_alias(table_kind)
        -- Key to some kind of table.
        tparam_alias(key_kind)
        tparam_alias(('{[%s]=%s}'):format(kind, key_kind))
        tparam_alias(('{[string]=%s}'):format(key_kind))
        tparam_alias(('{[string]={string=%s}}'):format(table_kind))
    end
    tparam_alias(('{[%s]={}}'):format(kind))
    -- List tables
    kind = ('{%s}'):format(kind)
    tparam_alias(kind)
    -- Nested lists
    kind = ('{%s}'):format(kind)
    tparam_alias(kind)
end

-- These links for string are distracting.
no_lua_ref=true

-- New style requires ldoc newer than 1.4.6 -- straight from github.
style='!new'
kind_names={topic='Manual',script='Programs'}
examples = {
    '../main.lua',
}

-- vim:set et sw=4 ts=4 ft=lua:
