-- This script is part of the Agricultural Roboport mod for Factorio.
-- Contains functions to seed virtual trees in the area of a roboport, roboport mode of operation and gui

local serpent = serpent or {}
-- Helper: Logging utility using Factorio's helpers for file logging

-- implement "seeding" routine:
-- place entity-ghost with ghost-name "virtual-tree-seed" every 3 tiles within all construction range
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
    local radius = seed_logistic_only and roboport.logistic_cell.logistic_radius or roboport.logistic_cell.construction_radius
    local step = 3

    -- Per-roboport settings and precomputed candidate positions
    local rsettings = storage.agricultural_roboports[roboport.unit_number] or {}
    rsettings.precomputed = rsettings.precomputed or {}
    local filters = rsettings.filters
    if type(filters) ~= "table" then filters = {} end
    local use_filter = rsettings.use_filter or false
    local filter_invert = rsettings.filter_invert or false

    -- Recompute precomputed positions when the requested seeding mode (logistic-only vs construction) differs
    local requested_mode = not not seed_logistic_only -- ensure boolean
    if not rsettings.precomputed.seed_positions or rsettings.precomputed.mode ~= requested_mode then
        local positions = {}
        local radius_for_mode = seed_logistic_only and roboport.logistic_cell.logistic_radius or roboport.logistic_cell.construction_radius
        for x = math.ceil(roboport.position.x - radius_for_mode + 2), math.floor(roboport.position.x + radius_for_mode - 2), step do
            for y = math.ceil(roboport.position.y - radius_for_mode + 2), math.floor(roboport.position.y + radius_for_mode - 2), step do
                table.insert(positions, {x = x, y = y})
            end
        end
        rsettings.precomputed.seed_positions = positions
        rsettings.precomputed.next_seed_index = 1
        rsettings.precomputed.mode = requested_mode
        storage.agricultural_roboports[roboport.unit_number] = rsettings
    end

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

    local max_seeds = (settings.global["agricultural-roboport-max-seeds-per-tick"] and settings.global["agricultural-roboport-max-seeds-per-tick"].value) or 10
    local placed = 0

    -- Per-call checks limit (controls CPU work per call)
    local checks_per_call = (settings.global["agricultural-roboport-seed-checks-per-call"] and settings.global["agricultural-roboport-seed-checks-per-call"].value) or 10

    local positions = rsettings.precomputed.seed_positions or {}
    local total_positions = #positions
    if total_positions == 0 then return end

    local idx = rsettings.precomputed.next_seed_index or 1
    for i = 1, checks_per_call do
        if placed >= max_seeds then break end
        local pos = positions[idx]
        idx = idx + 1
        if idx > total_positions then idx = 1 end

        -- Check for any real entities (excluding corpses and those marked for deconstruction) or any ghosts in the area
        local area = {{pos.x - 1.4, pos.y - 1.4}, {pos.x + 1.4, pos.y + 1.4}}
        local entities = surface.find_entities_filtered{area = area}
        local obstacle_found = false
        for _, ent in ipairs(entities) do
            if ent.type ~= "corpse" then
                if ent.name == "entity-ghost" then
                    obstacle_found = true
                    break
                elseif not ent.to_be_deconstructed() then
                    obstacle_found = true
                    break
                end
            end
        end
        if not obstacle_found then
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
                    local restrictions = info.tile_restriction or nil
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
    rsettings.precomputed.next_seed_index = idx
    storage.agricultural_roboports[roboport.unit_number] = rsettings
end




-- implement "harvesting" routine:
-- get all entities of type "plant" in construction range, check if they are fully grown, if so mark for deconstruction
-- also get all neutral entities and mark them for deconstruction

function harvest(roboport, current_tick)
    local rsettings = storage.agricultural_roboports[roboport.unit_number] or {}
    if write_file_log then write_file_log("harvest:start", roboport.unit_number, current_tick) end
    local area = {
        {roboport.position.x - roboport.logistic_cell.construction_radius, roboport.position.y - roboport.logistic_cell.construction_radius},
        {roboport.position.x + roboport.logistic_cell.construction_radius, roboport.position.y + roboport.logistic_cell.construction_radius}
    }
    -- Build set of all plant entity names from valid seeds when available.
    local plant_names = {}
    if type(prototypes) == "table" and type(prototypes.item) == "table" then
        for seed_name, seed_item in pairs(prototypes.item) do
            if seed_name:match("%-seed$") and seed_item.plant_result then
                local plant_name = (type(seed_item.plant_result) == "table" or type(seed_item.plant_result) == "userdata") and seed_item.plant_result.name or seed_item.plant_result
                if plant_name then
                    plant_names[plant_name] = true
                end
            end
        end
    end
    -- Harvest fully grown plants and neutral entities, but limit work per call
    local max_harvest = (settings.global["agricultural-roboport-max-harvest-per-call"] and settings.global["agricultural-roboport-max-harvest-per-call"].value) or 5
    local harvest_done = 0
    local inspect_limit = math.max(20, max_harvest * 10)

    local ignore_cliffs = (settings.global["agricultural-roboport-ignore-cliffs"] and settings.global["agricultural-roboport-ignore-cliffs"].value) or false

    -- Ensure we have a precomputed grid of harvest positions (small cells) to scan incrementally
    rsettings.precomputed = rsettings.precomputed or {}
    local hpositions = rsettings.precomputed.harvest_positions
    if not hpositions then
        hpositions = {}
        local step_h = 3
        local radius_h = roboport.logistic_cell.construction_radius
        for x = math.ceil(roboport.position.x - radius_h + 2), math.floor(roboport.position.x + radius_h - 2), step_h do
            for y = math.ceil(roboport.position.y - radius_h + 2), math.floor(roboport.position.y + radius_h - 2), step_h do
                table.insert(hpositions, {x = x, y = y})
            end
        end
        rsettings.precomputed.harvest_positions = hpositions
        rsettings.precomputed.next_harvest_index = 1
        storage.agricultural_roboports[roboport.unit_number] = rsettings
    end

    -- How many cells to check per call (bounded). Prefer an explicit runtime setting if available, otherwise derive.
    local checks_per_call = (settings.global and settings.global["agricultural-roboport-harvest-checks-per-call"] and settings.global["agricultural-roboport-harvest-checks-per-call"].value) or math.max(5, max_harvest * 8)

    local positions = rsettings.precomputed.harvest_positions or {}
    local total_positions = #positions
    if total_positions == 0 then return end
    local idx = rsettings.precomputed.next_harvest_index or 1
    local inspected = 0
    for i = 1, checks_per_call do
        if harvest_done >= max_harvest then break end
        local pos = positions[idx]
        idx = idx + 1
        if idx > total_positions then idx = 1 end

        local cell_area = {{pos.x - 1.5, pos.y - 1.5}, {pos.x + 1.5, pos.y + 1.5}}
        local ents = roboport.surface.find_entities_filtered{area = cell_area, type = {"tree", "simple-entity", "cliff", "plant"}, force = "neutral"}
        for _, ent in ipairs(ents) do
            if harvest_done >= max_harvest then break end
            if not ent or not ent.valid then goto cell_next end
            -- Skip already marked
            if ent.to_be_deconstructed and ent.to_be_deconstructed() then
                if write_file_log then write_file_log("harvest:skipped_already_marked", roboport.unit_number, ent.name, ent.position.x, ent.position.y) end
                goto cell_next
            end
            inspected = inspected + 1
            if inspected > inspect_limit then break end

            local is_plant_by_name = plant_names[ent.name]
            local is_plant_by_proto = ent.prototype and ent.prototype.growth_ticks
            if is_plant_by_name or is_plant_by_proto then
                if ent.prototype and ent.prototype.growth_ticks then
                    if current_tick >= (ent.tick_grown or 0) then
                        ent.order_deconstruction(roboport.force)
                        if ent.to_be_deconstructed and ent.to_be_deconstructed() then
                            harvest_done = harvest_done + 1
                            if write_file_log then write_file_log("harvest:deconstruct", roboport.unit_number, ent.name, ent.position.x, ent.position.y) end
                        else
                            if write_file_log then write_file_log("harvest:order_failed", roboport.unit_number, ent.name, ent.position.x, ent.position.y) end
                        end
                    end
                else
                    ent.order_deconstruction(roboport.force)
                    if ent.to_be_deconstructed and ent.to_be_deconstructed() then
                        harvest_done = harvest_done + 1
                        if write_file_log then write_file_log("harvest:deconstruct", roboport.unit_number, ent.name, ent.position.x, ent.position.y) end
                    else
                        if write_file_log then write_file_log("harvest:order_failed", roboport.unit_number, ent.name, ent.position.x, ent.position.y) end
                    end
                end
                goto cell_next
            end

            -- Neutral objects
            local ent_type = ent.type
            if ent_type == "tree" or ent_type == "simple-entity" or (not ignore_cliffs and ent_type == "cliff") then
                ent.order_deconstruction(roboport.force)
                if ent.to_be_deconstructed and ent.to_be_deconstructed() then
                    harvest_done = harvest_done + 1
                    if write_file_log then write_file_log("harvest:deconstruct_neutral", roboport.unit_number, ent.name, ent.position.x, ent.position.y) end
                else
                    if write_file_log then write_file_log("harvest:order_failed_neutral", roboport.unit_number, ent.name, ent.position.x, ent.position.y) end
                end
            end
            ::cell_next::
        end
    end
    rsettings.precomputed.next_harvest_index = idx
    storage.agricultural_roboports[roboport.unit_number] = rsettings
    if write_file_log then write_file_log("harvest:done", roboport.unit_number, harvest_done, inspected) end
end


-- Helper: Get mode name
function get_operating_mode_name(mode)
    if mode == -1 then return {"agricultural-roboport-status.mode-harvest"} end
    if mode == 0 then return {"agricultural-roboport-status.mode-both"} end
    if mode == 1 then return {"agricultural-roboport-status.mode-seed"} end
    return {"agricultural-roboport.mode-unknown"}
end

-- Precompute candidate seed positions for a roboport (call once on built)
function precompute_seed_positions_for_roboport(entity)
    if not entity or not entity.valid then return end
    local unit = entity.unit_number
    if not unit then return end
    local rsettings = storage.agricultural_roboports[unit] or {}
    rsettings.precomputed = rsettings.precomputed or {}
    local radius = (rsettings and rsettings.seed_logistic_only) and entity.logistic_cell.logistic_radius or entity.logistic_cell.construction_radius
    local step = 3
    local positions = {}
    for x = math.ceil(entity.position.x - radius + 2), math.floor(entity.position.x + radius - 2), step do
        for y = math.ceil(entity.position.y - radius + 2), math.floor(entity.position.y + radius - 2), step do
            table.insert(positions, {x = x, y = y})
        end
    end
    rsettings.precomputed.seed_positions = positions
    rsettings.precomputed.next_seed_index = 1
    rsettings.precomputed.mode = not not rsettings.seed_logistic_only
    storage.agricultural_roboports[unit] = rsettings
end