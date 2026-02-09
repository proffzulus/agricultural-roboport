-- This script is part of the Agricultural Roboport mod for Factorio.
-- Contains functions to seed virtual trees in the area of a roboport, roboport mode of operation and gui

local serpent = serpent or {}
local tile_buildability = require("scripts.tile_buildability")
-- Forward-declare surface check so it can be used by `seed` which appears earlier
local check_surface_conditions

-- Helper to check if quality support is enabled (startup setting)
local function is_quality_enabled()
    if settings and settings.startup and settings.startup["agricultural-roboport-enable-quality"] then
        return settings.startup["agricultural-roboport-enable-quality"].value
    end
    return true -- Default to enabled if setting not found
end

-- Helper: Logging utility using Factorio's helpers for file logging

-- Helper: Try to place entity at position with small adjustments (wiggle) if exact position fails
-- Returns: adjusted_position (or nil if all attempts fail), number_of_collision_checks_performed
local function try_position_with_wiggle(surface, entity_name, base_pos, force, dense_mode)
    -- Get the virtual seed entity's collision box to determine check area
    local entity_proto = prototypes.entity[entity_name]
    local check_x_extent = 1.4 -- Default for sparse mode
    local check_y_extent = 1.4
    
    if entity_proto and entity_proto.collision_box then
        local cbox = entity_proto.collision_box
        if cbox and type(cbox) == "table" and cbox[1] and cbox[2] then
            -- Calculate exact extents from collision box (preserve aspect ratio)
            local width = math.abs((cbox[2][1] or 0) - (cbox[1][1] or 0))
            local height = math.abs((cbox[2][2] or 0) - (cbox[1][2] or 0))
            check_x_extent = width / 2
            check_y_extent = height / 2
        end
    end
    
    -- In dense mode, try sub-tile offsets; in sparse mode, only try exact position
    local offsets = dense_mode and {
        {0, 0},           -- Exact position first
        {0.25, 0},        -- Small offsets to find adjacent free spots
        {-0.25, 0},
        {0, 0.25},
        {0, -0.25},
        {0.25, 0.25},
        {-0.25, -0.25},
        {0.25, -0.25},
        {-0.25, 0.25},
    } or {{0, 0}}  -- Sparse mode: only try exact position
    
    local checks_performed = 0
    for _, offset in ipairs(offsets) do
        local test_pos = {x = base_pos.x + offset[1], y = base_pos.y + offset[2]}
        checks_performed = checks_performed + 1
        
        -- Use can_place_entity with explicit build_check_type for precise collision detection
        if surface.can_place_entity{
            name = entity_name,
            position = test_pos,
            force = force,
            build_check_type = defines.build_check_type.manual_ghost
        } then
            return test_pos, checks_performed
        end
        
        ::continue_offset::
    end
    
    return nil, checks_performed  -- All attempts failed, but return check count
end

-- Helper: Validate tiles at a specific position for a plant
-- Returns: allowed (boolean), reason (string or nil)
local function validate_tiles_at_position(surface, position, seed_name, virtual_seed_info, plant_proto, plant_collision_box, dense_mode)
    local info = virtual_seed_info[seed_name] or {}
    local restrictions = info.tile_restriction
    local tile_buildability_rules = info.tile_buildability_rules
    
    -- Build tiles array based on plant collision box
    local tiles = {}
    if dense_mode and plant_collision_box and type(plant_collision_box) == "table" and plant_collision_box[1] and plant_collision_box[2] then
        -- In dense mode, check all tiles covered by the PLANT's collision box
        -- Calculate world-space collision box boundaries
        local box_left = position.x + (plant_collision_box[1][1] or 0)
        local box_top = position.y + (plant_collision_box[1][2] or 0)
        local box_right = position.x + (plant_collision_box[2][1] or 0)
        local box_bottom = position.y + (plant_collision_box[2][2] or 0)
        
        -- Find all tiles that the collision box overlaps (even partially)
        -- Use floor for left/top edges and floor for right/bottom edges to ensure we check all overlapping tiles
        local x1 = math.floor(box_left)
        local y1 = math.floor(box_top)
        local x2 = math.floor(box_right)
        local y2 = math.floor(box_bottom)
        
        for x = x1, x2 do
            for y = y1, y2 do
                table.insert(tiles, surface.get_tile(x, y))
            end
        end
    else
        -- Sparse mode or fallback: check 3x3 area
        for dx = -1, 1 do
            for dy = -1, 1 do
                table.insert(tiles, surface.get_tile(position.x + dx, position.y + dy))
            end
        end
    end
    
    -- Normalize tile_restriction to a flat list of tile names
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
    
    -- Check for resource tiles (avoid placing on ore patches, etc.)
    -- Check center tile for resources
    local center_tile = surface.get_tile(position)
    local resource_count = surface.count_entities_filtered{
        position = position,
        radius = 1.5,
        type = "resource"
    }
    if resource_count > 0 then
        return false, "resource_tile"
    end
    
    -- First check tile_restriction (tile names) if present
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
                return false, "tile_restriction_failed"
            end
        end
    end
    
    -- ALWAYS check tile_buildability_rules if they exist
    if tile_buildability_rules then
        local allowed_tbr, dbg = tile_buildability.evaluate_tile_buildability(surface, position, seed_name, info, plant_proto, plant_collision_box)
        if write_file_log then
            write_file_log("seed:tile_check", seed_name, dbg.center_tile or "<nil>", allowed_tbr and "allowed" or "blocked", serpent and serpent.block and serpent.block(dbg) or tostring(dbg))
        end
        if not allowed_tbr then
            return false, "tile_buildability_failed"
        end
    end
    
    return true, nil
end

-- implement "seeding" routine:
-- place entity-ghost with ghost-name "virtual-tree-seed" every 3 tiles within all construction range
function seed(roboport, seed_logistic_only)
    local virtual_seed_info = storage.virtual_seed_info
    if not virtual_seed_info then
        virtual_seed_info = Build_virtual_seed_info()
        storage.virtual_seed_info = virtual_seed_info
    end

    local surface = roboport.surface
    local force = roboport.force
    local radius = seed_logistic_only and roboport.logistic_cell.logistic_radius or roboport.logistic_cell.construction_radius
    
    -- Check if dense seeding mode is enabled (startup setting)
    local dense_mode = (settings.startup["agricultural-roboport-dense-seeding"] and settings.startup["agricultural-roboport-dense-seeding"].value) or false
    local step = dense_mode and 1 or 3

    -- Per-roboport settings and precomputed candidate positions
    local rsettings = storage.agricultural_roboports[roboport.unit_number] or {}
    rsettings.precomputed = rsettings.precomputed or {}
    local filters = rsettings.filters
    if type(filters) ~= "table" then filters = {} end
    local use_filter = rsettings.use_filter or false
    local filter_invert = rsettings.filter_invert or false
    
    -- Circuit network: check if "set filters" mode is enabled
    -- If enabled, read circuit signals and override manual filters
    local circuit_filter_enabled = rsettings.circuit_filter_enabled or false
    
    if circuit_filter_enabled and roboport.get_control_behavior and roboport.get_control_behavior() then
        local control_behavior = roboport.get_control_behavior()
        
        -- Read circuit network signals for filters
        local red_network = roboport.get_circuit_network(defines.wire_connector_id.circuit_red)
        local green_network = roboport.get_circuit_network(defines.wire_connector_id.circuit_green)
        
        -- If circuit filter control is enabled and connected to circuit network, read signals
        if (red_network or green_network) then
            -- Read all signals from both networks
            local circuit_filters = {}
            
            local function process_network_signals(network)
                if not network then return end
                local signals = network.signals
                if not signals then return end
                
                for _, signal_data in ipairs(signals) do
                    if signal_data.signal and signal_data.signal.name and signal_data.count > 0 then
                        local signal_name = signal_data.signal.name
                        
                        -- Check if this signal corresponds to a seed item (only accept seedable items)
                        if virtual_seed_info[signal_name] then
                            -- Extract quality from item signal if it has quality information
                            -- In Factorio 2.0+, item signals can have quality embedded
                            local quality_name = "normal" -- Default quality
                            
                            -- Extract quality from signal (quality field is a string, not an object)
                            if signal_data.signal.quality then
                                quality_name = signal_data.signal.quality
                            end
                            
                            -- Add to circuit filters
                            table.insert(circuit_filters, {
                                name = signal_name,
                                quality = quality_name
                            })
                            
                            if write_file_log then
                                write_file_log("[CIRCUIT DEBUG] Added filter:", signal_name, "with quality:", quality_name)
                            end
                        end
                    end
                end
            end
            
            process_network_signals(red_network)
            process_network_signals(green_network)
            
            -- Override manual filters with circuit filters
            if #circuit_filters > 0 or not read_contents then
                -- If we have circuit filters OR circuit is in "set filters" mode with no signals,
                -- override manual filters
                filters = circuit_filters
                use_filter = true
                -- filter_invert stays as per manual setting (circuit doesn't control whitelist/blacklist mode)
                
                if write_file_log then
                    write_file_log("[CIRCUIT] Set filters from circuit network:", #circuit_filters, "filters")
                end
            end
        end
    end

    -- Recompute precomputed positions when the requested seeding mode (logistic-only vs construction) differs
    local requested_mode = not not seed_logistic_only -- ensure boolean
    if not rsettings.precomputed.seed_positions or rsettings.precomputed.mode ~= requested_mode or rsettings.precomputed.dense ~= dense_mode then
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
        rsettings.precomputed.dense = dense_mode
        storage.agricultural_roboports[roboport.unit_number] = rsettings
    end

    local whitelist = {} -- Format: {["item-name"] = {quality1=true, quality2=true, ...}}
    local blacklist = {} -- Format: {["item-name"] = true} (quality ignored for blacklist)
    if use_filter then
        if filter_invert then
            -- Blacklist mode: store item names only, ignore quality
            for _, filter_entry in ipairs(filters) do
                if filter_entry then
                    local item_name = nil
                    
                    -- Support both old string format and new table format
                    if type(filter_entry) == "string" then
                        item_name = filter_entry
                    elseif type(filter_entry) == "table" and filter_entry.name then
                        item_name = filter_entry.name
                    end
                    
                    if item_name then
                        blacklist[item_name] = true
                    end
                end
            end
        else
            for _, filter_entry in ipairs(filters) do
                if filter_entry then
                    local item_name = nil
                    local quality_name = "normal"
                    
                    -- Support both old string format and new table format
                    if type(filter_entry) == "string" then
                        item_name = filter_entry
                        quality_name = "normal"
                    elseif type(filter_entry) == "table" and filter_entry.name then
                        item_name = filter_entry.name
                        quality_name = filter_entry.quality or "normal"
                    end
                    
                    if item_name then
                        if not whitelist[item_name] then
                            whitelist[item_name] = {}
                        end
                        whitelist[item_name][quality_name] = true
                    end
                end
            end
        end
    end

    local max_seeds = (settings and settings.global and settings.global["agricultural-roboport-max-seeds-per-tick"] and settings.global["agricultural-roboport-max-seeds-per-tick"].value) or 10
    local placed = 0

    -- Per-call checks limit (controls CPU work per call)
    local checks_per_call = (settings and settings.global and settings.global["agricultural-roboport-seed-checks-per-call"] and settings.global["agricultural-roboport-seed-checks-per-call"].value) or 10

    local positions = rsettings.precomputed.seed_positions or {}
    local total_positions = #positions
    if total_positions == 0 then return end

    -- Build candidate seeds list once per seed() call with ALL metadata pre-computed
    -- This eliminates prototype lookups and string operations from the hot loop
    local candidate_seeds = {} -- Format: {{name, quality, virtual_name, plant_proto, plant_collision_box}, ...}
    if use_filter and not filter_invert then
        -- Whitelist mode: only include items+qualities from whitelist
        local quality_support_enabled = is_quality_enabled()
        for item_name, qualities in pairs(whitelist) do
            -- Only include if seed exists in virtual_seed_info
            if virtual_seed_info[item_name] then
                local seed_item = prototypes.item[item_name]
                if seed_item then
                    -- Pre-compute virtual seed name (expensive string operation)
                    local virtual_seed_name = item_name:match("%-seed$") 
                        and "virtual-" .. item_name 
                        or "virtual-" .. item_name .. "-seed"
                    
                    -- Pre-fetch plant prototype and collision box
                    local plant_ref = seed_item.plant_result
                    local plant_name = type(plant_ref) == "string" and plant_ref or (plant_ref and plant_ref.name or nil)
                    local plant_proto = plant_name and prototypes.entity[plant_name] or nil
                    local plant_collision_box = plant_proto and plant_proto.collision_box or nil
                    
                    if quality_support_enabled then
                        for quality_name, _ in pairs(qualities) do
                            table.insert(candidate_seeds, {
                                name = item_name,
                                quality = quality_name,
                                virtual_name = virtual_seed_name,
                                plant_proto = plant_proto,
                                plant_collision_box = plant_collision_box
                            })
                        end
                    else
                        table.insert(candidate_seeds, {
                            name = item_name,
                            quality = "normal",
                            virtual_name = virtual_seed_name,
                            plant_proto = plant_proto,
                            plant_collision_box = plant_collision_box
                        })
                    end
                end
            end
        end
    else
        -- No filter OR blacklist mode: include all seeds with NORMAL quality only
        for seed_name, _ in pairs(virtual_seed_info) do
            local is_blacklisted = use_filter and filter_invert and blacklist[seed_name]
            if not is_blacklisted then
                local seed_item = prototypes.item[seed_name]
                if seed_item then
                    -- Pre-compute virtual seed name
                    local virtual_seed_name = seed_name:match("%-seed$")
                        and "virtual-" .. seed_name
                        or "virtual-" .. seed_name .. "-seed"
                    
                    -- Pre-fetch plant prototype and collision box
                    local plant_ref = seed_item.plant_result
                    local plant_name = type(plant_ref) == "string" and plant_ref or (plant_ref and plant_ref.name or nil)
                    local plant_proto = plant_name and prototypes.entity[plant_name] or nil
                    local plant_collision_box = plant_proto and plant_proto.collision_box or nil
                    
                    table.insert(candidate_seeds, {
                        name = seed_name,
                        quality = "normal",
                        virtual_name = virtual_seed_name,
                        plant_proto = plant_proto,
                        plant_collision_box = plant_collision_box
                    })
                end
            end
        end
    end
    
    -- Pre-filter candidates by surface conditions (performance optimization)
    -- Check once per seed() call instead of per tile position
    local surface_compatible_seeds = {}
    for _, seed_entry in ipairs(candidate_seeds) do
        -- Use pre-cached plant_proto instead of re-fetching
        if seed_entry.plant_proto and check_surface_conditions(seed_entry.plant_proto, surface) then
            table.insert(surface_compatible_seeds, seed_entry)
        end
    end
    candidate_seeds = surface_compatible_seeds
    
    -- Log candidate seeds for this surface (once per seed() call)
    if write_file_log and #candidate_seeds > 0 then
        local seed_names_log = {}
        local seen_names = {}
        for _, seed_entry in ipairs(candidate_seeds) do
            if not seen_names[seed_entry.name] then
                table.insert(seed_names_log, seed_entry.name)
                seen_names[seed_entry.name] = true
            end
        end
        write_file_log("[SEED] Surface " .. surface.name .. " candidate seeds (" .. #candidate_seeds .. " total): " .. table.concat(seed_names_log, ", "))
    end
    
    -- In dense mode, sort seeds by plant size (largest first) for optimal packing
    -- Skip sorting if only 0-1 seeds (performance optimization)
    if dense_mode and #candidate_seeds > 1 then
        table.sort(candidate_seeds, function(a, b)
            -- Use pre-cached collision boxes instead of re-fetching prototypes
            local cbox_a = a.plant_collision_box
            local cbox_b = b.plant_collision_box
            
            if not cbox_a or not cbox_b then return false end
            
            -- Calculate collision box areas
            local calc_area = function(cbox)
                if cbox and type(cbox) == "table" and cbox[1] and cbox[2] then
                    local width = (cbox[2][1] or 0) - (cbox[1][1] or 0)
                    local height = (cbox[2][2] or 0) - (cbox[1][2] or 0)
                    return width * height
                end
                return 0
            end
            
            local area_a = calc_area(cbox_a)
            local area_b = calc_area(cbox_b)
            
            -- Sort descending (largest first)
            return area_a > area_b
        end)
    end

    local idx = rsettings.precomputed.next_seed_index or 1
    local remaining_checks = checks_per_call
    
    -- Early exit if no candidate seeds (e.g., empty whitelist filter)
    if #candidate_seeds == 0 then
        return
    end
    
    while remaining_checks > 0 and placed < max_seeds do
        -- Wrap index if needed
        if idx > total_positions then idx = 1 end
        
        local pos = positions[idx]
        idx = idx + 1

        -- Iterate through pre-computed candidate seeds for this position
        for _, seed_entry in ipairs(candidate_seeds) do
            -- All data pre-cached: no prototype lookups, no string operations
            local seed_name = seed_entry.name
            local quality_name = seed_entry.quality
            local virtual_seed_name = seed_entry.virtual_name
            local plant_proto = seed_entry.plant_proto
            local plant_collision_box = seed_entry.plant_collision_box
            
            -- Validate entity exists
            if not prototypes.entity[virtual_seed_name] then
                goto continue
            end
            
            -- Step 1: Try to find collision-free position
            -- Track collision checks performed to account for wiggle cost
            local final_pos, checks_used
            if dense_mode then
                -- Dense mode: try wiggle offsets to find free spot (up to 9 checks)
                final_pos, checks_used = try_position_with_wiggle(surface, virtual_seed_name, pos, force, dense_mode)
                remaining_checks = remaining_checks - checks_used
            else
                -- Sparse mode: single collision check at exact position (cost: 1 check)
                checks_used = 1
                remaining_checks = remaining_checks - 1
                if surface.can_place_entity{name = virtual_seed_name, position = pos, force = force} then
                    final_pos = pos
                end
            end
            
            if not final_pos then
                -- No collision-free position found
                goto continue
            end
            
            -- Step 2: Validate tiles at the collision-free position
            local tiles_allowed, tile_fail_reason = validate_tiles_at_position(
                surface, final_pos, seed_name, virtual_seed_info, 
                plant_proto, plant_collision_box, dense_mode
            )
            
            if not tiles_allowed then
                -- Tiles don't meet requirements at this position
                if write_file_log then
                    write_file_log("seed:tile_reject", seed_name, "pos:", final_pos.x, final_pos.y, "reason:", tile_fail_reason or "unknown")
                end
                goto continue
            end
            
            -- Step 3: Everything passed - create ghost
            -- Force quality to "normal" if quality support is disabled
            local ghost_quality = is_quality_enabled() and quality_name or "normal"
            
            local ghost = surface.create_entity{
                name = "entity-ghost",
                position = final_pos,
                force = force,
                inner_name = virtual_seed_name,
                quality = ghost_quality,
                raise_built = true,
            }
            if ghost and write_file_log then
                write_file_log("[SEED] Created ghost:", virtual_seed_name, "quality:", ghost_quality, "ghost.quality:", ghost.quality and ghost.quality.name or "nil", "wiggle:", final_pos.x ~= pos.x or final_pos.y ~= pos.y)
            end
            placed = placed + 1
            break -- Only plant one seed per tile
            
            ::continue::
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
    local max_harvest = (settings and settings.global and settings.global["agricultural-roboport-max-harvest-per-call"] and settings.global["agricultural-roboport-max-harvest-per-call"].value) or 5
    local harvest_done = 0
    local inspect_limit = math.max(20, max_harvest * 10)

    local ignore_cliffs = (settings and settings.global and settings.global["agricultural-roboport-ignore-cliffs"] and settings.global["agricultural-roboport-ignore-cliffs"].value) or false

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
	return {"agricultural-roboport-status.mode-unknown"}
end


check_surface_conditions = function(plant_ref, surface)
    -- Check if surface properties match plant requirements using official Factorio API
    -- plant_ref may be a string (name) or a prototype object; normalize to name
    local plant_key = nil
    if type(plant_ref) == "string" then
        plant_key = plant_ref
    else
        -- userdata/table prototype: attempt to read .name
        local ok, n = pcall(function() return plant_ref and plant_ref.name end)
        if ok and n then plant_key = n end
    end
    if write_file_log then write_file_log("check_surface_conditions:start", plant_key or tostring(plant_ref) or "<nil>", surface and surface.name or "<nil>") end
    local plant_proto = (plant_key and prototypes and prototypes.entity) and prototypes.entity[plant_key] or nil
    if not plant_proto then
        if write_file_log then write_file_log("check_surface_conditions:plant_proto_missing", plant_key or tostring(plant_ref) or "<nil>") end
        return true
    end
    if plant_proto.surface_conditions then
        if write_file_log then write_file_log("check_surface_conditions:checking", #plant_proto.surface_conditions, "condition(s) for", plant_key) end
        
        -- Iterate through all surface conditions required by this plant
        for _, condition in ipairs(plant_proto.surface_conditions) do
            local property_id = condition.property
            local min_value = condition.min
            local max_value = condition.max
            
            -- Get the current surface property value using the official API
            local property_value = nil
            if surface and type(surface.get_property) == "function" then
                local ok, val = pcall(function() return surface.get_property(property_id) end)
                if ok then
                    property_value = val
                else
                    if write_file_log then write_file_log("check_surface_conditions:get_property_failed", property_id, "error:", val) end
                end
            else
                if write_file_log then write_file_log("check_surface_conditions:get_property_unavailable", property_id) end
            end
            
            -- If we couldn't get the property value, be permissive
            if property_value == nil then
                if write_file_log then write_file_log("check_surface_conditions:property_unknown", property_id, "being_permissive") end
                -- Continue to next condition
            else
                -- Check if property value is within the required range
                -- min and max can be nil (meaning unbounded)
                local min_check = (min_value == nil) or (property_value >= min_value)
                local max_check = (max_value == nil) or (property_value <= max_value)
                
                if write_file_log then 
                    write_file_log("check_surface_conditions:property_check", 
                        "property=", property_id, 
                        "value=", property_value, 
                        "min=", min_value or "unbounded", 
                        "max=", max_value or "unbounded",
                        "min_ok=", min_check,
                        "max_ok=", max_check)
                end
                
                if not min_check or not max_check then
                    if write_file_log then 
                        write_file_log("check_surface_conditions:condition_failed", 
                            plant_key, 
                            "property=", property_id,
                            "value=", property_value,
                            "required_min=", min_value or "unbounded",
                            "required_max=", max_value or "unbounded")
                    end
                    return false
                end
            end
        end
    end
    if write_file_log then write_file_log("check_surface_conditions:ok", plant_key or tostring(plant_ref) or "<nil>") end
    return true
end

-- Export helper functions for use by other modules (e.g., vegetation-planner)
_G.try_position_with_wiggle = try_position_with_wiggle
_G.validate_tiles_at_position = validate_tiles_at_position
_G.check_surface_conditions = check_surface_conditions
_G.is_quality_enabled = is_quality_enabled
_G.Build_virtual_seed_info = Build_virtual_seed_info