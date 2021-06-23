-- love uses luajit with some extras (unpack) from 5.2
std = "love+luajit+lua52"

ignore = {
    '311', -- Value assigned to a local variable is unused.
}

allow_defined_top  = true  -- Allow defining globals implicitly by setting them in the top level scope.
max_line_length    = false -- Do not limit line length.
unused_args        = false -- Filter out warnings related to unused arguments and loop variables.
unused_secondaries = false -- Filter out warnings related to unused variables set together with used ones.

exclude_files = {
    -- leafo/gh-actions-lua & luarocks put lua files here
    '.install',
    '.lua',
    '.luarocks',
}

files["main.lua"] = {
    ignore = {
        '211',
    }
}

files["windfield/mlib/mlib.lua"] = {
    ignore = {
        '2..', -- Unused variables
        '421', -- Shadowing a local variable
        '422', -- Shadowing an argument
        '43.', -- Shadowing upvalues
    }
}

-- vim:set et sw=4 ts=4 ft=lua:
