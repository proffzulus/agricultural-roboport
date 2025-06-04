-- This script is part of the Agricultural Roboport mod for Factorio.
-- Contains functions to seed virtual trees in the area of a roboport, roboport mode of operation and gui

local serpent = serpent or {}
-- Helper: Logging utility using Factorio's helpers for file logging

-- implement "seeding" routine:
-- place entity-ghost with ghost-name "virtual-tree-seed" every 3 tiles within all construction range

-- Helper: Check if a surface matches all surface_conditions of a plant
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
                if type(k) == "string" and surface[k] ~= v then
                    return false
                end
            end
            return true
        end
    end
    return false
end

function seed(roboport, seed_logistic_only)
    local virtual_seed_info = storage.virtual_seed_info
    if not virtual_seed_info then
        virtual_seed_info = {}
        for seed_name, seed_item in pairs(prototypes.item) do
            if seed_name:match("%-seed$") then
                local plant_result = seed_item.place_result or seed_item.plant_result
                local plant_name = (type(plant_result) == "table" or type(plant_result) == "userdata") and plant_result.name or plant_result
                local plant_proto = plant_name and prototypes.entity[plant_name]
                local restrictions = plant_proto and plant_proto.autoplace_specification and plant_proto.autoplace_specification.tile_restriction
                if not restrictions and plant_proto then
                    restrictions = plant_proto.autoplace and plant_proto.autoplace.tile_restriction
                end
                virtual_seed_info[seed_name] = {
                    tile_restriction = restrictions,
                    plant_proto = plant_proto
                }
            end
        end
        storage.virtual_seed_info = virtual_seed_info
    end

    local surface = roboport.surface
    local force = roboport.force
    local radius
    if seed_logistic_only then
        radius = roboport.logistic_cell.logistic_radius
    else
        radius = roboport.logistic_cell.construction_radius
    end
    local step = 3

    local filters = storage.agricultural_roboports[tostring(roboport.unit_number).."_filters"]
    if type(filters) ~= "table" then filters = {} end
    local use_filter = storage.agricultural_roboports[tostring(roboport.unit_number).."_use_filter"]
    local filter_invert = storage.agricultural_roboports[tostring(roboport.unit_number).."_filter_invert"]

    local whitelist = {}
    local blacklist = {}
    if use_filter then
        if filter_invert then
            for _, seed in ipairs(filters) do
                if seed then blacklist[seed] = true end
            end
        else
            for _, seed in ipairs(filters) do
                if seed then table.insert(whitelist, seed) end
            end
        end
    end

    local max_seeds = settings.global["agricultural-roboport-max-seeds-per-tick"] and settings.global["agricultural-roboport-max-seeds-per-tick"].value or 10
    local placed = 0

    for x = math.ceil(roboport.position.x - radius + 2), math.floor(roboport.position.x + radius - 2), step do
        for y = math.ceil(roboport.position.y - radius + 2), math.floor(roboport.position.y + radius - 2), step do
            if placed >= max_seeds then return end
            local pos = {x = x, y = y}
            local entities = surface.count_entities_filtered{
                area = {{pos.x - 1.4, pos.y - 1.4}, {pos.x + 1.4, pos.y + 1.4}},
                type = {"corpse"},
                invert = true,
            }
            if entities == 0 then
                local tiles = {}
                for dx = -1, 1 do
                    for dy = -1, 1 do
                        table.insert(tiles, surface.get_tile(pos.x + dx, pos.y + dy))
                    end
                end
                local candidate_seeds = {}
                if use_filter and not filter_invert then
                    for _, seed in ipairs(whitelist) do
                        table.insert(candidate_seeds, seed)
                    end
                else
                    for seed_name, seed_item in pairs(prototypes.item) do
                        if seed_name:match("%-seed$") and seed_item.plant_result then
                            if not (use_filter and filter_invert and blacklist[seed_name]) then
                                table.insert(candidate_seeds, seed_name)
                            end
                        end
                    end
                end
                for _, seed_name in ipairs(candidate_seeds) do
                    local seed_item = prototypes.item[seed_name]
                    local plant_name = seed_item and seed_item.plant_result
                    local virtual_seed_name = "virtual-" .. seed_name
                    if plant_name and prototypes.entity[virtual_seed_name] then
                        local info = virtual_seed_info[seed_name] or {}
                        local restrictions = info.tile_restriction
                        -- Normalize restrictions to a flat list of tile names
                        local normalized_restrictions = nil
                        if restrictions then
                            normalized_restrictions = {}
                            for _, allowed_tile in pairs(restrictions) do
                                if type(allowed_tile) == "table" and allowed_tile.first then
                                    table.insert(normalized_restrictions, allowed_tile.first)
                                elseif type(allowed_tile) == "string" then
                                    table.insert(normalized_restrictions, allowed_tile)
                                end
                            end
                        end
                        -- If no restrictions or empty, allow planting anywhere
                        local allowed = true
                        if normalized_restrictions and #normalized_restrictions > 0 then
                            for _, plant_tile in ipairs(tiles) do
                                local tile_ok = false
                                for _, allowed_tile in ipairs(normalized_restrictions) do
                                    if plant_tile.name == allowed_tile then
                                        tile_ok = true
                                        break
                                    end
                                end
                                if not tile_ok then
                                    allowed = false
                                    break
                                end
                            end
                        end
                        -- Disable surface_conditions check entirely
                        -- if allowed and plant_proto and plant_proto.surface_conditions then
                        --     allowed = surface_matches_conditions(surface, plant_proto.surface_conditions)
                        -- end
                        if allowed then
                            local ghost = surface.create_entity{
                                name = "entity-ghost",
                                position = pos,
                                force = force,
                                ghost_name = virtual_seed_name,
                                raise_built = true,
                            }
                            placed = placed + 1
                            break -- Only plant one seed per tile
                        end
                    end
                end
            end
        end
    end
end




-- implement "harvesting" routine:
-- get all entities of type "plant" in construction range, check if they are fully grown, if so mark for deconstruction
-- also get all neutral entities and mark them for deconstruction

function harvest(roboport, current_tick)
    local area = {
        {roboport.position.x - roboport.logistic_cell.construction_radius, roboport.position.y - roboport.logistic_cell.construction_radius},
        {roboport.position.x + roboport.logistic_cell.construction_radius, roboport.position.y + roboport.logistic_cell.construction_radius}
    }
    -- Build set of all plant entity names from valid seeds
    local plant_names = {}
    for seed_name, seed_item in pairs(prototypes.item) do
        if seed_name:match("%-seed$") and seed_item.plant_result then
            local plant_name = (type(seed_item.plant_result) == "table" or type(seed_item.plant_result) == "userdata") and seed_item.plant_result.name or seed_item.plant_result
            if plant_name then
                plant_names[plant_name] = true
            end
        end
    end
    -- Harvest fully grown plants for all valid plant entities
    for plant_name, _ in pairs(plant_names) do
        for _, plant in pairs(roboport.surface.find_entities_filtered{ area = area, name = plant_name }) do
            if plant.valid then
                -- If plant has growth_ticks, only harvest if fully grown
                if plant.prototype.growth_ticks then
                    if current_tick >= (plant.tick_grown or 0) then
                        plant.order_deconstruction(roboport.force)
                    end
                else
                    plant.order_deconstruction(roboport.force)
                end
            end
        end
    end
    -- Mark neutral trees, rocks, and cliffs for deconstruction
    local neutral_types = {"tree", "simple-entity", "cliff"}
    for _, entity_type in ipairs(neutral_types) do
        for _, neutral in pairs(roboport.surface.find_entities_filtered{ area = area, type = entity_type, force = "neutral" }) do
            if neutral.valid then
                neutral.order_deconstruction(roboport.force)
            end
        end
    end
end


-- Helper: Get mode name
function get_operating_mode_name(mode)
    if mode == -1 then return {"agricultural-roboport-status.mode-harvest"} end
    if mode == 0 then return {"agricultural-roboport-status.mode-both"} end
    if mode == 1 then return {"agricultural-roboport-status.mode-seed"} end
    return {"agricultural-roboport.mode-unknown"}
end