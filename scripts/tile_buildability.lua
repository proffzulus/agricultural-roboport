-- Helper module to evaluate `tile_buildability_rules` for plant prototypes.
local serpent = serpent or {}
local M = {}

local function safe_proto_layers(tile)
    local ok, proto = pcall(function() return tile.prototype end)
    if not ok or not proto then return nil end
    local ok2, layers = pcall(function() return proto.collision_mask and proto.collision_mask.layers end)
    if not ok2 then return nil end
    return layers
end

local function any_name_in_area(tiles_area, names)
    for _, tt in ipairs(tiles_area) do
        for _, n in ipairs(names) do
            if tt.name == n then return true end
        end
    end
    return false
end

local function any_layer_in_area(tiles_area, layer_name)
    for _, tt in ipairs(tiles_area) do
        local layers = safe_proto_layers(tt)
        if layers and layers[layer_name] then return true end
    end
    return false
end

-- Evaluate a set of tile_buildability_rules for a position.
-- Returns: allowed(boolean), debug(table)
function M.evaluate_tile_buildability(surface, position, seed_name, info_entry, plant_proto, collision_box)
    local debug = {seed = seed_name, pos = position, center_tile = nil, checked_rules = {}}
    if not info_entry then return true, debug end
    local tbr = info_entry.tile_buildability_rules
    local tile = surface.get_tile(position)
    debug.center_tile = tile and tile.name or nil
    if not tbr then return true, debug end
    
    -- If tile_buildability_rules is an empty table, allow placement (no rules to check)
    local has_rules = false
    for _ in pairs(tbr) do
        has_rules = true
        break
    end
    if not has_rules then return true, debug end

    -- Build tile area based on collision box if provided, otherwise use 3x3 default
    local tiles_area = {}
    if collision_box and type(collision_box) == "table" and collision_box[1] and collision_box[2] then
        -- collision_box format: {{x1, y1}, {x2, y2}}
        local x1 = math.floor(position.x + (collision_box[1][1] or 0))
        local y1 = math.floor(position.y + (collision_box[1][2] or 0))
        local x2 = math.ceil(position.x + (collision_box[2][1] or 0))
        local y2 = math.ceil(position.y + (collision_box[2][2] or 0))
        
        debug.collision_box = collision_box
        debug.tile_area = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
        
        for x = x1, x2 do
            for y = y1, y2 do
                table.insert(tiles_area, surface.get_tile(x, y))
            end
        end
    else
        -- Default 3x3 area
        for dx = -1, 1 do
            for dy = -1, 1 do
                table.insert(tiles_area, surface.get_tile(position.x + dx, position.y + dy))
            end
        end
    end

    for idx, rule in ipairs(tbr) do
        local rule_debug = {index = idx, passed = true, reason = nil}
        local rule_ok = true
        -- required_tiles
        if rule.required_tiles then
            local names = {}
            if rule.required_tiles.tiles then
                for _, t in pairs(rule.required_tiles.tiles) do
                    if type(t) == "table" and t.first then
                        table.insert(names, t.first)
                    elseif type(t) == "string" then
                        table.insert(names, t)
                    end
                end
            end
            if #names > 0 then
                if not any_name_in_area(tiles_area, names) then
                    rule_ok = false
                    rule_debug.passed = false
                    rule_debug.reason = "required_tiles.names_not_found"
                end
            elseif rule.required_tiles.layers then
                local all_layers_ok = true
                for layer_name, needed in pairs(rule.required_tiles.layers) do
                    if needed then
                        if not any_layer_in_area(tiles_area, layer_name) then
                            all_layers_ok = false
                            break
                        end
                    end
                end
                if not all_layers_ok then
                    rule_ok = false
                    rule_debug.passed = false
                    rule_debug.reason = "required_tiles.layers_not_found"
                end
            end
        end

        -- colliding_tiles
        if rule_ok and rule.colliding_tiles then
            local coll_names = {}
            if rule.colliding_tiles.tiles then
                for _, t in pairs(rule.colliding_tiles.tiles) do
                    if type(t) == "table" and t.first then
                        table.insert(coll_names, t.first)
                    elseif type(t) == "string" then
                        table.insert(coll_names, t)
                    end
                end
            end
            local collision = false
            if #coll_names > 0 then
                collision = any_name_in_area(tiles_area, coll_names)
            end
            if not collision and rule.colliding_tiles.layers then
                for layer_name, v in pairs(rule.colliding_tiles.layers) do
                    if v and any_layer_in_area(tiles_area, layer_name) then
                        collision = true
                        break
                    end
                end
            end
            if collision and not rule.remove_on_collision then
                rule_ok = false
                rule_debug.passed = false
                rule_debug.reason = "colliding_tiles_present"
            end
        end

        rule_debug.passed = rule_ok
        table.insert(debug.checked_rules, rule_debug)
        if rule_ok then
            -- rule allows placement
            debug.matched_rule = idx
            return true, debug
        end
    end

    -- No rule explicitly allowed placement
    debug.matched_rule = nil
    return false, debug
end

return M
