-- Vegetation Planner - manual seeding tool
-- Handles selection events for placing/clearing vegetation ghosts

local vegetation_planner = {}

-- Get planner settings from global storage (per-player)
-- Selection tools don't support tags, so we store settings per player
local function get_planner_settings(player_index)
    storage.vegetation_planner_settings = storage.vegetation_planner_settings or {}
    
    if not storage.vegetation_planner_settings[player_index] then
        storage.vegetation_planner_settings[player_index] = {
            use_filter = false,
            filter_invert = false,
            filters = {},
            force_sparse = false
        }
    end
    
    return storage.vegetation_planner_settings[player_index]
end

-- Helper: Convert selection area to position grid
local function area_to_positions(area, step)
    local positions = {}
    -- Round area to tile boundaries: floor for left/top, ceil for right/bottom
    local x1 = math.floor(math.min(area.left_top.x, area.right_bottom.x))
    local y1 = math.floor(math.min(area.left_top.y, area.right_bottom.y))
    local x2 = math.ceil(math.max(area.left_top.x, area.right_bottom.x))
    local y2 = math.ceil(math.max(area.left_top.y, area.right_bottom.y))
    
    for x = x1, x2, step do
        for y = y1, y2, step do
            table.insert(positions, {x = x, y = y})
        end
    end
    
    return positions
end

-- Handle normal selection: place seed ghosts
function vegetation_planner.on_player_selected_area(event)
    if event.item ~= "vegetation-planner" then return end
    
    local player = game.get_player(event.player_index)
    if not player then return end
    
    local surface = event.surface
    local area = event.area
    
    -- Get planner configuration from global storage
    local planner_settings = get_planner_settings(event.player_index)
    
    -- Determine step size (dense or sparse)
    local global_dense = (settings.startup["agricultural-roboport-dense-seeding"] 
        and settings.startup["agricultural-roboport-dense-seeding"].value) or false
    local use_dense = global_dense and not planner_settings.force_sparse
    local step = use_dense and 1 or 3
    
    -- Convert area to position grid
    local positions = area_to_positions(area, step)
    
    if #positions == 0 then
        player.print({"vegetation-planner.error-no-positions"})
        return
    end
    
    -- Get virtual seed info
    local virtual_seed_info = storage.virtual_seed_info
    if not virtual_seed_info then
        virtual_seed_info = Build_virtual_seed_info()
        storage.virtual_seed_info = virtual_seed_info
    end
    
    -- Build filter lists (same logic as roboport)
    local filters = planner_settings.filters or {}
    local use_filter = planner_settings.use_filter or false
    local filter_invert = planner_settings.filter_invert or false
    
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
    
    -- Build candidate seeds list
    local candidate_seeds = {} -- Format: {{name, quality, virtual_name, plant_proto, plant_collision_box}, ...}
    if use_filter and not filter_invert then
        -- Whitelist mode: only include items+qualities from whitelist
        local quality_support_enabled = is_quality_enabled()
        for item_name, qualities in pairs(whitelist) do
            -- Only include if seed exists in virtual_seed_info
            if virtual_seed_info[item_name] then
                local seed_item = prototypes.item[item_name]
                if seed_item then
                    -- Pre-compute virtual seed name
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
    
    -- Pre-filter candidates by surface conditions
    local surface_compatible_seeds = {}
    for _, seed_entry in ipairs(candidate_seeds) do
        if seed_entry.plant_proto and check_surface_conditions(seed_entry.plant_proto, surface) then
            table.insert(surface_compatible_seeds, seed_entry)
        end
    end
    candidate_seeds = surface_compatible_seeds
    
    if #candidate_seeds == 0 then
        player.print({"vegetation-planner.error-no-compatible-seeds"})
        return
    end
    
    -- In dense mode, sort seeds by plant size (largest first) for optimal packing
    if use_dense and #candidate_seeds > 1 then
        table.sort(candidate_seeds, function(a, b)
            local cbox_a = a.plant_collision_box
            local cbox_b = b.plant_collision_box
            
            if not cbox_a or not cbox_b then return false end
            
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
            
            return area_a > area_b
        end)
    end
    
    -- Place seeds at each position
    local placed = 0
    for _, pos in ipairs(positions) do
        -- Iterate through candidate seeds for this position
        for _, seed_entry in ipairs(candidate_seeds) do
            local seed_name = seed_entry.name
            local quality_name = seed_entry.quality
            local virtual_seed_name = seed_entry.virtual_name
            local plant_proto = seed_entry.plant_proto
            local plant_collision_box = seed_entry.plant_collision_box
            
            -- Validate entity exists
            if not prototypes.entity[virtual_seed_name] then
                goto continue
            end
            
            -- Try to find collision-free position
            local final_pos
            if use_dense then
                -- Dense mode: try wiggle offsets to find free spot
                final_pos = try_position_with_wiggle(surface, virtual_seed_name, pos, player.force, use_dense)
            else
                -- Sparse mode: single collision check at exact position
                if surface.can_place_entity{name = virtual_seed_name, position = pos, force = player.force} then
                    final_pos = pos
                end
            end
            
            if not final_pos then
                goto continue
            end
            
            -- Validate tiles at the collision-free position
            local tiles_allowed = validate_tiles_at_position(
                surface, final_pos, seed_name, virtual_seed_info, 
                plant_proto, plant_collision_box, use_dense
            )
            
            if not tiles_allowed then
                goto continue
            end
            
            -- Everything passed - create ghost
            local ghost_quality = is_quality_enabled() and quality_name or "normal"
            
            local ghost = surface.create_entity{
                name = "entity-ghost",
                position = final_pos,
                force = player.force,
                inner_name = virtual_seed_name,
                quality = ghost_quality,
                raise_built = true,
            }
            if ghost then
                placed = placed + 1
            end
            break -- Only plant one seed per tile
            
            ::continue::
        end
    end
end

-- Handle alt-selection: clear vegetation ghosts
function vegetation_planner.on_player_alt_selected_area(event)
    if event.item ~= "vegetation-planner" then return end
    
    local player = game.get_player(event.player_index)
    if not player then return end
    
    local surface = event.surface
    local area = event.area
    
    -- Get planner configuration from global storage
    local planner_settings = get_planner_settings(event.player_index)
    
    -- Round area to tile boundaries
    local x1 = math.floor(math.min(area.left_top.x, area.right_bottom.x))
    local y1 = math.floor(math.min(area.left_top.y, area.right_bottom.y))
    local x2 = math.ceil(math.max(area.left_top.x, area.right_bottom.x))
    local y2 = math.ceil(math.max(area.left_top.y, area.right_bottom.y))
    
    local rounded_area = {
        left_top = {x = x1, y = y1},
        right_bottom = {x = x2, y = y2}
    }
    
    -- Find all vegetation ghosts in area
    local ghosts = surface.find_entities_filtered{
        area = rounded_area,
        name = "entity-ghost",
        force = player.force
    }
    
    local cleared_count = 0
    for _, ghost in ipairs(ghosts) do
        if ghost.ghost_name and ghost.ghost_name:match("^virtual%-.*%-seed$") then
            -- TODO: Check if ghost matches filter settings
            -- For now, clear all vegetation ghosts
            ghost.destroy()
            cleared_count = cleared_count + 1
        end
    end
    
    -- Build filter info for display
    local filter_info = "no filter"
    if planner_settings.use_filter then
        local filter_count = 0
        for _, f in pairs(planner_settings.filters or {}) do
            if f then filter_count = filter_count + 1 end
        end
        local mode = planner_settings.filter_invert and "blacklist" or "whitelist"
        filter_info = mode .. " (" .. filter_count .. " items)"
    end
    
    local width = x2 - x1
    local height = y2 - y1
    local tile_count = width * height
end

-- Handle cursor stack changes to show/hide GUI
function vegetation_planner.on_player_cursor_stack_changed(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    
    local cursor = player.cursor_stack
    if cursor and cursor.valid_for_read and cursor.name == "vegetation-planner" then
        -- Player picked up the vegetation planner - show GUI
        local planner_settings = get_planner_settings(event.player_index)
        create_config_gui(player, planner_settings)
    else
        -- Player cleared cursor or switched items - hide GUI
        destroy_config_gui(player)
    end
end

-- Handle GUI events
function vegetation_planner.on_gui_checked_state_changed(event)
    if not event.element or not event.element.valid then return end
    local element_name = event.element.name
    
    -- Only handle vegetation planner GUI elements
    if not element_name:match("^vegetation_planner_") then return end
    
    local player = game.get_player(event.player_index)
    if not player then return end
    
    local planner_settings = get_planner_settings(event.player_index)
    
    if element_name == "vegetation_planner_use_filter" then
        planner_settings.use_filter = event.element.state
        
        -- Update GUI elements enabled state in real-time
        local frame = player.gui.screen.vegetation_planner_config
        if frame then
            -- Find and update filter mode switch and labels
            for _, child in pairs(frame.children) do
                if child.type == "flow" then
                    local switch = child.vegetation_planner_filter_invert
                    if switch then
                        switch.enabled = event.element.state
                        
                        -- Update label colors
                        local whitelist_label = child.vegetation_planner_whitelist_label
                        local blacklist_label = child.vegetation_planner_blacklist_label
                        if whitelist_label and blacklist_label then
                            if event.element.state then
                                whitelist_label.style.font_color = {r=1, g=1, b=1}
                                blacklist_label.style.font_color = {r=1, g=1, b=1}
                            else
                                whitelist_label.style.font_color = {r=0.5, g=0.5, b=0.5}
                                blacklist_label.style.font_color = {r=0.5, g=0.5, b=0.5}
                            end
                        end
                        break
                    end
                end
            end
            
            -- Update all filter sprite buttons
            local filter_table = frame.vegetation_planner_filter_table
            if filter_table then
                for i = 1, 5 do
                    local btn = filter_table["vegetation_planner_filter_sprite_" .. i]
                    if btn then
                        btn.enabled = event.element.state
                    end
                end
            end
        end
    elseif event.element.name == "vegetation_planner_force_sparse" then
        planner_settings.force_sparse = event.element.state
    end
end

function vegetation_planner.on_gui_switch_state_changed(event)
    if not event.element or not event.element.valid then return end
    local element_name = event.element.name
    
    -- Only handle vegetation planner GUI elements
    if not element_name:match("^vegetation_planner_") then return end
    
    if element_name == "vegetation_planner_filter_invert" then
        local planner_settings = get_planner_settings(event.player_index)
        planner_settings.filter_invert = (event.element.switch_state == "right")
    end
end

function vegetation_planner.on_gui_click(event)
    if not event.element or not event.element.valid then return end
    local element_name = event.element.name
    
    -- Only handle vegetation planner GUI elements
    if not element_name:match("^vegetation_planner_") then return end
    
    local player = game.get_player(event.player_index)
    if not player then return end
    
    -- Handle seed selection in picker
    if element_name:match("^vegetation_planner_seed_select_") then
        local seed_name = element_name:match("^vegetation_planner_seed_select_(.+)$")
        if seed_name then
            -- Store selected seed temporarily
            storage.vegetation_planner_temp_selection = storage.vegetation_planner_temp_selection or {}
            storage.vegetation_planner_temp_selection[event.player_index] = {
                seed = seed_name,
                quality = storage.vegetation_planner_temp_selection[event.player_index] and 
                         storage.vegetation_planner_temp_selection[event.player_index].quality or "normal"
            }
        end
        return
    end
    
    -- Handle quality selection
    if element_name:match("^vegetation_planner_quality_") then
        local quality = element_name:match("^vegetation_planner_quality_(.+)$")
        if quality then
            storage.vegetation_planner_temp_selection = storage.vegetation_planner_temp_selection or {}
            storage.vegetation_planner_temp_selection[event.player_index] = 
                storage.vegetation_planner_temp_selection[event.player_index] or {}
            storage.vegetation_planner_temp_selection[event.player_index].quality = quality
        end
        return
    end
    
    -- Handle confirm button
    if element_name == "vegetation_planner_seed_picker_confirm" then
        local temp = storage.vegetation_planner_temp_selection and 
                     storage.vegetation_planner_temp_selection[event.player_index]
        if temp and temp.seed then
            local dialog = player.gui.screen.vegetation_planner_seed_picker
            if dialog and dialog.valid then
                local filter_index = dialog.tags.filter_index
                if filter_index then
                    local planner_settings = get_planner_settings(event.player_index)
                    planner_settings.filters[filter_index] = temp.seed
                end
            end
        end
        close_seed_picker(player)
        storage.vegetation_planner_temp_selection[event.player_index] = nil
        return
    end
    
    -- Handle close buttons
    if element_name == "vegetation_planner_seed_picker_close" or 
       element_name == "vegetation_planner_seed_picker_close_x" then
        close_seed_picker(player)
        storage.vegetation_planner_temp_selection[event.player_index] = nil
        return
    end
    
    -- Handle filter sprite button clicks in main config GUI
    local filter_idx = element_name:match("^vegetation_planner_filter_sprite_(%d+)$")
    if filter_idx then
        filter_idx = tonumber(filter_idx)
        local planner_settings = get_planner_settings(event.player_index)
        
        if event.button == defines.mouse_button_type.left then
            -- Open seed picker dialog
            show_seed_picker(player, filter_idx)
        elseif event.button == defines.mouse_button_type.right then
            -- Right-click to clear filter
            planner_settings.filters[filter_idx] = nil
            
            -- Update sprite button
            event.element.sprite = nil
            event.element.tooltip = {"vegetation-planner.click-to-set"}
        end
        return
    end
end

return vegetation_planner
