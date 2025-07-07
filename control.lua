-- this part is used to surpress lint errors. These objects do exist in the game environment, but they are not defined in the script.
storage = storage or {}
defines = defines or {}
game = game or {}
script = script or {}
prototypes = prototypes or {}
helpers = helpers or {}
serpent = serpent or {}
-- 

require("scripts.agricultural-roboport")
require("scripts.UI")

-- Metatable for default roboport settings (unified table)
local roboport_modes_mt = {
    __index = function()
        return {
            mode = 0, -- default to harvest and seed
            seed_logistic_only = false,
            use_filter = false,
            filter_invert = false,
            filters = nil,
            surface = nil, -- new: surface name
            position = nil -- new: position table {x=..., y=...}
        }
    end
}

local function build_virtual_seed_info()
    local info = {}
    for seed_name, seed_item in pairs(prototypes.item) do
        if seed_name:match("%-seed$") then
            local plant_result = seed_item.place_result or seed_item.plant_result
            local plant_name = (type(plant_result) == "table" or type(plant_result) == "userdata") and plant_result.name or plant_result
            local plant_proto = plant_name and prototypes.entity[plant_name]
            local restrictions = plant_proto and plant_proto.autoplace_specification and plant_proto.autoplace_specification.tile_restriction
            if not restrictions and plant_proto then
                restrictions = plant_proto.autoplace and plant_proto.autoplace.tile_restriction
            end
            info[seed_name] = {
                tile_restriction = restrictions,
                plant_proto = plant_proto
            }
        end
    end
    return info
end

script.on_init(function()
    storage.agricultural_roboports = setmetatable({}, roboport_modes_mt)
    storage.virtual_seed_info = build_virtual_seed_info()
end)

script.on_load(function()
    if storage.agricultural_roboports then
        setmetatable(storage.agricultural_roboports, roboport_modes_mt)
    end
    -- Do NOT modify storage.virtual_seed_info here; on_load must not mutate storage
end)

-- =====================
-- Handler functions region
-- =====================

local function on_built_agricultural_roboport(entity)
    local ghost_key = string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
    local ghost_settings = storage.agricultural_roboports[ghost_key]
    if ghost_settings ~= nil then
        ghost_settings.surface = entity.surface.name
        ghost_settings.position = {x = entity.position.x, y = entity.position.y}
        storage.agricultural_roboports[entity.unit_number] = ghost_settings
        storage.agricultural_roboports[ghost_key] = nil
    else
        storage.agricultural_roboports[entity.unit_number] = {
            mode = 0,
            seed_logistic_only = false,
            use_filter = false,
            filter_invert = false,
            filters = nil,
            surface = entity.surface.name,
            position = {x = entity.position.x, y = entity.position.y},
        }
    end
end

local function on_robot_built_virtual_seed(event)
    local entity = event.entity
    if entity.name:match("^virtual%-.+%-seed$") then
        local surface = entity.surface
        local position = entity.position
        local seed_name = entity.name:match("^virtual%-(.+%-seed)$")
        local plant_result = nil
        if seed_name and prototypes.item[seed_name] then
            plant_result = prototypes.item[seed_name].place_result or prototypes.item[seed_name].plant_result
        end
        local plant_result_name = plant_result
        if (type(plant_result) == "table" or type(plant_result) == "userdata") and plant_result.name then
            plant_result_name = plant_result.name
        end
        if plant_result_name and prototypes.entity[plant_result_name] then
            surface.create_entity{
                name = plant_result_name,
                position = position,
                force = entity.force
            }
            entity.destroy()
        end
    end
end

-- Helper: Check if surface matches plant's surface_conditions
local function surface_matches_conditions(surface, surface_conditions)
    if not surface_conditions then return true end
    if type(surface_conditions) == "table" then
        -- If array: check if surface.name matches any entry
        if #surface_conditions > 0 then
            for _, v in ipairs(surface_conditions) do
                if surface.name == v then
                    return true
                end
            end
            return false
        else
            -- Dictionary: check key-value pairs
            for k, v in pairs(surface_conditions) do
                if surface[k] ~= v then
                    return false
                end
            end
            return true
        end
    end
    return false
end

local function on_built_virtual_seed_ghost(entity, event)
    if entity.name == "entity-ghost" and entity.ghost_name and entity.ghost_name:match("^virtual%-.+%-seed$") then
        local surface = entity.surface
        local position = entity.position
        -- Instead of using the virtual seed's autoplace, use the underlying plant's autoplace_specification
        local seed_name = entity.ghost_name:match("^virtual%-(.+%-seed)$")
        local seed_item = seed_name and prototypes.item[seed_name]
        local plant_result = seed_item and (seed_item.place_result or seed_item.plant_result)
        local plant_name = (type(plant_result) == "table" or type(plant_result) == "userdata") and plant_result.name or plant_result
        local plant_proto = plant_name and prototypes.entity[plant_name]
        local restrictions = plant_proto and plant_proto.autoplace_specification and plant_proto.autoplace_specification.tile_restriction
        if not restrictions and plant_proto then
            restrictions = plant_proto.autoplace and plant_proto.autoplace.tile_restriction
        end
        local tile = surface.get_tile(position)
        local allowed = false
        if restrictions then
            for _, allowed_tile in pairs(restrictions) do
                if tile.name == allowed_tile.first or tile.name == allowed_tile then
                    allowed = true
                    break
                end
            end
        else
            allowed = true -- No restrictions, allow by default
        end
        if allowed and plant_proto and type(plant_proto.surface_conditions) == "table" then
            allowed = surface_matches_conditions(surface, plant_proto.surface_conditions)
        end
        if not allowed then
            entity.destroy()
            local player = game.get_player(event.player_index)
            if player then
                player.create_local_flying_text({
                    text = {"cant-build-reason.cant-build-on-tile", tile.name},
                    create_at_cursor = true,
                })
            end
        end
    end
end

local function copy_roboport_settings(source_key, dest_key)
    local src = storage.agricultural_roboports[source_key] or {}
    local dest = {}
    dest.mode = src.mode or 0
    dest.seed_logistic_only = src.seed_logistic_only or false
    dest.use_filter = src.use_filter or false
    dest.filter_invert = src.filter_invert or false
    if type(src.filters) == "table" then
        local new_filters = {}
        for i = 1, 5 do new_filters[i] = src.filters[i] end
        dest.filters = new_filters
    else
        dest.filters = nil
    end
    storage.agricultural_roboports[dest_key] = dest
end

function on_built_event_handler(event)
    local entity = event.created_entity or event.entity
    if not entity then return end
    if entity.name == "entity-ghost" and entity.ghost_name == "agricultural-roboport" then
        local ghost_key = string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
        if entity.tags then
            storage.agricultural_roboports[ghost_key] = {
                mode = entity.tags.mode or 0,
                seed_logistic_only = entity.tags.seed_logistic_only or false,
                use_filter = entity.tags.use_filter or false,
                filter_invert = entity.tags.filter_invert or false,
                filters = (type(entity.tags.filters) == "table" and (function() local f = {}; for i=1,5 do f[i]=entity.tags.filters[i] end; return f end)()) or nil,
                surface = entity.surface.name,
                position = {x = entity.position.x, y = entity.position.y}
            }
        else
            -- Always create a default settings table for manually placed ghosts
            storage.agricultural_roboports[ghost_key] = {
                mode = 0,
                seed_logistic_only = false,
                use_filter = false,
                filter_invert = false,
                filters = nil,
                surface = entity.surface.name,
                position = {x = entity.position.x, y = entity.position.y}
            }
        end
        return
    end
    if entity.name == "agricultural-roboport" then
        if event.tags then
            storage.agricultural_roboports[entity.unit_number] = {
                mode = event.tags.mode or 0,
                seed_logistic_only = event.tags.seed_logistic_only or false,
                use_filter = event.tags.use_filter or false,
                filter_invert = event.tags.filter_invert or false,
                filters = (type(event.tags.filters) == "table" and (function() local f = {}; for i=1,5 do f[i]=event.tags.filters[i] end; return f end)()) or nil,
                surface = entity.surface.name,
                position = {x = entity.position.x, y = entity.position.y},
            }
        else
            local ghost_key = string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
            local ghost_settings = storage.agricultural_roboports[ghost_key]
            if ghost_settings ~= nil then
                ghost_settings.surface = entity.surface.name
                ghost_settings.position = {x = entity.position.x, y = entity.position.y}
                storage.agricultural_roboports[entity.unit_number] = ghost_settings
                storage.agricultural_roboports[ghost_key] = nil
            else
                storage.agricultural_roboports[entity.unit_number] = {
                    mode = 0,
                    seed_logistic_only = false,
                    use_filter = false,
                    filter_invert = false,
                    filters = nil,
                    surface = entity.surface.name,
                    position = {x = entity.position.x, y = entity.position.y},
                }
            end
        end
        return
    end
    if entity.name == "entity-ghost" and entity.ghost_name and entity.ghost_name:match("^virtual%-.+%-seed$") then
        on_built_virtual_seed_ghost(entity, event)
        return
    end
    if event.tags and (entity.name == "entity-ghost" and entity.ghost_name == "agricultural-roboport" or entity.name == "agricultural-roboport") then
        local key = entity.name == "agricultural-roboport" and entity.unit_number or string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
        storage.agricultural_roboports[key] = {
            mode = event.tags.mode or 0,
            seed_logistic_only = event.tags.seed_logistic_only or false,
            use_filter = event.tags.use_filter or false,
            filter_invert = event.tags.filter_invert or false,
            filters = (type(event.tags.filters) == "table" and (function() local f = {}; for i=1,5 do f[i]=event.tags.filters[i] end; return f end)()) or nil,
        }
    end
end

local function on_remove_agricultural_roboport(event)
    local entity = event.entity
    if entity and entity.name == "agricultural-roboport" then
        storage.agricultural_roboports[entity.unit_number] = nil
    end
end

local function on_entity_settings_pasted(event)
    local source = event.source
    local destination = event.destination
    if source and destination and source.valid and destination.valid then
        local is_source_roboport = (source.name == "agricultural-roboport")
        local is_source_ghost = (source.name == "entity-ghost" and source.ghost_name == "agricultural-roboport")
        local is_dest_roboport = (destination.name == "agricultural-roboport")
        local is_dest_ghost = (destination.name == "entity-ghost" and destination.ghost_name == "agricultural-roboport")
        if (is_source_roboport or is_source_ghost) and (is_dest_roboport or is_dest_ghost) then
            local function get_key(entity)
                if entity.name == "agricultural-roboport" then
                    return entity.unit_number
                else
                    return string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
                end
            end
            local source_key = get_key(source)
            local dest_key = get_key(destination)
            copy_roboport_settings(source_key, dest_key)
        end
    end
end

local function on_player_setup_blueprint(event)
    local player = game.get_player(event.player_index)
    local bp
    if player.is_cursor_blueprint() then
        bp = player.cursor_stack
    else
        bp = event.item
    end
    if not (bp and bp.valid_for_read and bp.is_blueprint) then
        return
    end
    local entities = bp.get_blueprint_entities()
    if not entities then
        return
    end
    for i, ent in ipairs(entities) do
        if ent.name == "agricultural-roboport" then
            local surface = player.surface
            local real = surface.find_entity("agricultural-roboport", ent.position)
            if real then
                local settings = storage.agricultural_roboports[real.unit_number] or {}
                local tags = {
                    mode = settings.mode or 0,
                    seed_logistic_only = settings.seed_logistic_only or false,
                    use_filter = settings.use_filter or false,
                    filter_invert = settings.filter_invert or false,
                }
                if type(settings.filters) == "table" then
                    tags.filters = {}
                    for j = 1, 5 do tags.filters[j] = settings.filters[j] end
                end
                bp.set_blueprint_entity_tags(i, tags)
            else
                -- Check for ghost at this position
                local ghost = surface.find_entity("entity-ghost", ent.position)
                if ghost and ghost.ghost_name == "agricultural-roboport" then
                    local ghost_key = string.format("ghost_%d_%d_%s", ghost.position.x, ghost.position.y, ghost.surface.name)
                    local settings = storage.agricultural_roboports[ghost_key] or {}
                    local tags = {
                        mode = settings.mode or 0,
                        seed_logistic_only = settings.seed_logistic_only or false,
                        use_filter = settings.use_filter or false,
                        filter_invert = settings.filter_invert or false,
                    }
                    if type(settings.filters) == "table" then
                        tags.filters = {}
                        for j = 1, 5 do tags.filters[j] = settings.filters[j] end
                    end
                    bp.set_blueprint_entity_tags(i, tags)
                end
            end
        end
    end
end

-- Unified handler for on_robot_built_entity
local function on_robot_built_entity_dispatch(event)
    local entity = event.entity
    if entity.name:match("^virtual%-.+%-seed$") then
        on_robot_built_virtual_seed(event)
    else
        on_built_event_handler(event)
    end
end

-- Helper: Decide and perform actions based on operating mode
local function process_agricultural_roboport(entity, tick)
    if not (entity.energy and entity.energy > 0) then
        return
    end
    if entity.to_be_deconstructed() then
        return
    end
    local settings = storage.agricultural_roboports[entity.unit_number] or {}
    local mode = settings.mode or 0
    local seed_logistic_only = settings.seed_logistic_only or false
    if entity.status == defines.entity_status.working then
        entity.custom_status = {diode = defines.entity_status_diode.green, label = get_operating_mode_name and get_operating_mode_name(mode) or ""}
    end
    if mode <= 0 then
        if harvest then harvest(entity, tick) end
    end
    if mode >= 0 then
        if seed then seed(entity, seed_logistic_only) end
    end
end

-- =====================
-- Event subscriptions region
-- =====================

script.on_nth_tick(300, function(event)
    local count = 0
    for key, settings in pairs(storage.agricultural_roboports) do
        if type(key) == "number" and settings.surface and settings.position then
            local surface = game.surfaces[settings.surface]
            if surface then
                local entity = surface.find_entity("agricultural-roboport", settings.position)
                if entity and entity.valid and entity.unit_number == key then
                    process_agricultural_roboport(entity, event.tick)
                    count = count + 1
                end
            end
        end
    end
end)

script.on_event(defines.events.on_built_entity, on_built_event_handler, {{filter = "name", mode="or", name = "entity-ghost"}, {filter = "name", mode="or", name = "agricultural-roboport"}})

script.on_event({defines.events.on_entity_died, defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity}, on_remove_agricultural_roboport)

script.on_event(defines.events.on_robot_built_entity, on_robot_built_entity_dispatch)

script.on_event(defines.events.on_entity_settings_pasted, on_entity_settings_pasted)

script.on_event(defines.events.on_player_setup_blueprint, on_player_setup_blueprint)

script.on_configuration_changed(function()
    if not storage.virtual_seed_info then
        if build_virtual_seed_info then
            storage.virtual_seed_info = build_virtual_seed_info()
        else
            -- fallback: inline build logic
            local info = {}
            for seed_name, seed_item in pairs(prototypes.item) do
                if seed_name:match("%-seed$") then
                    local plant_result = seed_item.place_result or seed_item.plant_result
                    local plant_name = (type(plant_result) == "table" or type(plant_result) == "userdata") and plant_result.name or plant_result
                    local plant_proto = plant_name and prototypes.entity[plant_name]
                    local restrictions = plant_proto and plant_proto.autoplace_specification and plant_proto.autoplace_specification.tile_restriction
                    if not restrictions and plant_proto then
                        restrictions = plant_proto.autoplace and plant_proto.autoplace.tile_restriction
                    end
                    info[seed_name] = {
                        tile_restriction = restrictions,
                        plant_proto = plant_proto
                    }
                end
            end
            storage.virtual_seed_info = info
        end
    end
end)

