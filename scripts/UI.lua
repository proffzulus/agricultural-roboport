-- filepath: scripts/UI.lua
-- All GUI-related event handlers for agricultural-roboport mod

local UI = {}
local util = require('scripts.util')
local serpent = serpent or require('serpent')

-- Helper to check if quality support is enabled (startup setting)
local function is_quality_enabled()
    if settings and settings.startup and settings.startup["agricultural-roboport-enable-quality"] then
        return settings.startup["agricultural-roboport-enable-quality"].value
    end
    return true -- Default to enabled if setting not found
end

-- Helper: Check if plant is compatible with surface conditions
local function check_surface_conditions(plant_ref, surface)
    -- plant_ref may be a string (name) or a prototype object; normalize to name
    local plant_key = nil
    if type(plant_ref) == "string" then
        plant_key = plant_ref
    else
        -- userdata/table prototype: attempt to read .name
        local ok, n = pcall(function() return plant_ref and plant_ref.name end)
        if ok and n then plant_key = n end
    end
    
    local prototypes = rawget(_G, 'prototypes')
    local plant_proto = (plant_key and prototypes and prototypes.entity) and prototypes.entity[plant_key] or nil
    if not plant_proto then
        return true -- No prototype means be permissive
    end
    
    if plant_proto.surface_conditions then
        -- Iterate through all surface conditions required by this plant
        for _, condition in ipairs(plant_proto.surface_conditions) do
            local property_id = condition.property
            local min_value = condition.min
            local max_value = condition.max
            
            -- Get the current surface property value
            local property_value = nil
            if surface and type(surface.get_property) == "function" then
                local ok, val = pcall(function() return surface.get_property(property_id) end)
                if ok then
                    property_value = val
                end
            end
            
            -- If we couldn't get the property value, be permissive
            if property_value ~= nil then
                -- Check if property value is within the required range
                local min_check = (min_value == nil) or (property_value >= min_value)
                local max_check = (max_value == nil) or (property_value <= max_value)
                
                if not min_check or not max_check then
                    return false -- Surface condition not met
                end
            end
        end
    end
    
    return true -- All conditions met or no conditions
end


local function mode_to_switch_state(mode)
    if mode == -1 then return "left" end
    if mode == 0 then return "none" end
    if mode == 1 then return "right" end
    return "none"
end

local function switch_state_to_mode(state)
    if state == "left" then return -1 end
    if state == "none" then return 0 end
    if state == "right" then return 1 end
    return 0
end

-- ========================================================================
-- VEGETATION PLANNER HELPER FUNCTIONS
-- ========================================================================

-- Get planner settings from global storage (per-player)
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

-- Helper: Build list of all available seed items from virtual_seed_info
local function get_available_seeds()
    local seeds = {}
    
    -- Use the existing virtual_seed_info built by Build_virtual_seed_info()
    if storage.virtual_seed_info then
        for seed_name, _ in pairs(storage.virtual_seed_info) do
            table.insert(seeds, seed_name)
        end
    end
    
    -- Sort alphabetically
    table.sort(seeds)
    
    return seeds
end

-- Helper: Create or update vegetation planner configuration GUI
local function create_planner_config_gui(player, planner_settings)
    -- Destroy existing GUI if present
    if player.gui.screen.vegetation_planner_config then
        player.gui.screen.vegetation_planner_config.destroy()
    end
    
    -- Create frame in top-left corner (matching roboport style)
    local frame = player.gui.screen.add{
        type = "frame",
        name = "vegetation_planner_config",
        direction = "vertical",
        caption = {"vegetation-planner.config-title"}
    }
    
    -- Position in top-left
    frame.location = {x = 10, y = 50}
    
    -- Use filter checkbox
    frame.add{
        type = "checkbox",
        name = "vegetation_planner_use_filter",
        state = planner_settings.use_filter or false,
        caption = {"gui-inserter.use-filters"}
    }
    
    -- Filter controls container
    local filter_controls = frame.add{
        type = "flow",
        name = "vegetation_planner_filter_controls",
        direction = "vertical"
    }
    
    -- Filter mode switch (whitelist/blacklist) - horizontal flow
    local filter_mode_flow = filter_controls.add{type = "flow", direction = "horizontal", style = "horizontal_flow"}
    local whitelist_label = filter_mode_flow.add{
        type = "label",
        name = "vegetation_planner_whitelist_label",
        caption = {"gui-inserter.whitelist"},
        style = "caption_label"
    }
    local filter_switch = filter_mode_flow.add{
        type = "switch",
        name = "vegetation_planner_filter_invert",
        switch_state = (planner_settings.filter_invert and "right") or "left",
        left_label_caption = "",
        right_label_caption = "",
        enabled = planner_settings.use_filter or false
    }
    local blacklist_label = filter_mode_flow.add{
        type = "label",
        name = "vegetation_planner_blacklist_label",
        caption = {"gui-inserter.blacklist"},
        style = "caption_label"
    }
    
    -- Gray out labels when disabled
    if not (planner_settings.use_filter or false) then
        whitelist_label.style.font_color = {r=0.5, g=0.5, b=0.5}
        blacklist_label.style.font_color = {r=0.5, g=0.5, b=0.5}
    end
    
    -- Force sparse mode checkbox (only show when dense seeding is globally enabled)
    local dense_setting = settings.startup["agricultural-roboport-dense-seeding"]
    if dense_setting and dense_setting.value == true then
        filter_controls.add{
            type = "checkbox",
            name = "vegetation_planner_force_sparse",
            state = planner_settings.force_sparse or false,
            caption = {"vegetation-planner.force-sparse"}
        }
    end
    
    -- Filter slots using choose-elem-button (same as roboport!)
    filter_controls.add{type = "label", caption = {"gui-inserter.filter"}}
    
    local filter_table = filter_controls.add{
        type = "table",
        name = "vegetation_planner_filter_table",
        column_count = 5,
        style = "filter_slot_table"
    }
    
    -- Get available seeds for filter
    local seed_names = get_available_seeds()
    
    local filters = planner_settings.filters or {}
    local is_blacklist = planner_settings.filter_invert == true
    local quality_enabled = is_quality_enabled()
    
    for i = 1, 5 do
        local filter_entry = filters[i]
        
        -- Use choose-elem-button just like roboport!
        local btn = filter_table.add{
            type = "choose-elem-button",
            name = "vegetation_planner_filter_" .. i,
            elem_type = (quality_enabled and not is_blacklist) and "item-with-quality" or "item",
            elem_filters = {
                {filter = "name", name = seed_names}
            },
            enabled = planner_settings.use_filter or false,
            style = "slot_button"
        }
        
        -- Set current value if exists
        if filter_entry then
            local item_name, quality_name
            
            -- Handle both old string format and new table format
            if type(filter_entry) == "string" then
                item_name = filter_entry
                quality_name = "normal"
            elseif type(filter_entry) == "table" then
                item_name = filter_entry.name
                quality_name = filter_entry.quality or "normal"
            end
            
            if item_name then
                if quality_enabled and not is_blacklist then
                    btn.elem_value = {name = item_name, quality = quality_name}
                else
                    btn.elem_value = item_name
                end
            end
        end
    end
    
    -- Set enabled state for filter controls
    filter_controls.enabled = planner_settings.use_filter or false
    
    player.opened = frame
end

-- Helper: Destroy vegetation planner configuration GUI
local function destroy_planner_config_gui(player)
    if player.gui.screen.vegetation_planner_config then
        player.gui.screen.vegetation_planner_config.destroy()
    end
end

-- ========================================================================
-- ROBOPORT UI EVENT HANDLERS
-- ========================================================================

-- Open GUI when player opens an agricultural-roboport or its ghost
function UI.on_gui_opened(event)
    local entity = event.entity
    local is_roboport = entity and entity.name == "agricultural-roboport"
    local is_roboport_ghost = entity and entity.name == "entity-ghost" and entity.ghost_name == "agricultural-roboport"
    if is_roboport or is_roboport_ghost then
        local player = game.get_player(event.player_index)
        if player.gui.relative.agricultural_roboport_mode then
            player.gui.relative.agricultural_roboport_mode.destroy()
        end
        local unit_key
        if is_roboport then
            unit_key = entity.unit_number
        elseif is_roboport_ghost then
            unit_key = string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
        end
        -- Fix: force settings table to be present for ghosts (and real) so UI always sees a table, not metatable default
        -- Always ensure a table exists for ghost roboports before reading/writing settings
        if not storage.agricultural_roboports[unit_key] then
            storage.agricultural_roboports[unit_key] = {
                mode = 0,
                seed_logistic_only = false,
                use_filter = false,
                filter_invert = false,
                filters = nil, -- Format: {{name="seed-name", quality="quality-name"}, ...}
            }
        end
        local settings = storage.agricultural_roboports[unit_key]
        local mode = settings.mode or 0
        local seed_logistic_only = settings.seed_logistic_only or false
        
        -- Check if circuit network controls mode or filters (read from settings)
        local circuit_controls_mode = settings.circuit_mode_enabled or false
        local circuit_controls_filters = settings.circuit_filter_enabled or false
        local circuit_mode_value = mode
        local circuit_filters = {}
        
        if is_roboport and entity.get_control_behavior then
            local control_behavior = entity.get_control_behavior()
            if control_behavior then
                -- Check if circuit controls operating mode (from settings)
                if circuit_controls_mode then
                    local mode_signal = settings.circuit_mode_signal or {type = "virtual", name = "signal-M"}
                    if mode_signal and mode_signal.name then
                        local red_network = entity.get_circuit_network(defines.wire_connector_id.circuit_red)
                        local green_network = entity.get_circuit_network(defines.wire_connector_id.circuit_green)
                        
                        local signal_value = 0
                        if red_network then
                            local signal = red_network.get_signal(mode_signal)
                            if signal then signal_value = signal_value + signal end
                        end
                        if green_network then
                            local signal = green_network.get_signal(mode_signal)
                            if signal then signal_value = signal_value + signal end
                        end
                        
                        -- Mode is circuit-controlled
                        if signal_value < 0 then
                            circuit_mode_value = -1
                        elseif signal_value > 0 then
                            circuit_mode_value = 1
                        else
                            circuit_mode_value = 0
                        end
                    end
                end
                
                -- Check if circuit filter control is explicitly enabled
                local red_network = entity.get_circuit_network(defines.wire_connector_id.circuit_red)
                local green_network = entity.get_circuit_network(defines.wire_connector_id.circuit_green)
                
                if circuit_controls_filters and (red_network or green_network) then
                    -- Read circuit filters
                    circuit_controls_filters = true
                    
                    -- Read circuit filters from both networks
                    local virtual_seed_info = storage.virtual_seed_info
                    if not virtual_seed_info then
                        virtual_seed_info = Build_virtual_seed_info and Build_virtual_seed_info() or {}
                    end
                    
                    local function read_filter_signals(network)
                        if not network then return end
                        local signals = network.signals
                        if not signals then return end
                        
                        for _, signal_data in ipairs(signals) do
                            if signal_data.signal and signal_data.signal.name and signal_data.count > 0 then
                                local signal_name = signal_data.signal.name
                                if virtual_seed_info[signal_name] then
                                    local quality_name = "normal"
                                    -- Quality field is a string, not an object
                                    if signal_data.signal.quality then
                                        quality_name = signal_data.signal.quality
                                    end
                                    table.insert(circuit_filters, {name = signal_name, quality = quality_name})
                                end
                            end
                        end
                    end
                    
                    read_filter_signals(red_network)
                    read_filter_signals(green_network)
                end
            end
        end
        
        local frame = player.gui.relative.add{
            type = "frame",
            name = "agricultural_roboport_mode",
            caption = {"agricultural-roboport.mode-title"},
            anchor = {
                gui = defines.relative_gui_type.roboport_gui,
                position = defines.relative_gui_position.right,
                entity = entity
            },
            direction = "vertical"
        }
        
        local mode_switch = frame.add{
            type = "switch",
            name = "agricultural_roboport_mode_switch_" .. tostring(unit_key),
            switch_state = mode_to_switch_state(circuit_controls_mode and circuit_mode_value or mode),
            left_label_caption = {"agricultural-roboport.mode-harvest"},
            right_label_caption = {"agricultural-roboport.mode-seed"},
            allow_none_state = true,
            enabled = not circuit_controls_mode
        }
        frame.add{
            type = "checkbox",
            name = "agricultural_roboport_seed_logistic_only_" .. tostring(unit_key),
            state = seed_logistic_only,
            caption = {"agricultural-roboport.seed-logistic-only"}
        }
        
        -- Check if wires are connected
        local has_wires = false
        if is_roboport and entity.get_control_behavior then
            local red_network = entity.get_circuit_network(defines.wire_connector_id.circuit_red)
            local green_network = entity.get_circuit_network(defines.wire_connector_id.circuit_green)
            has_wires = (red_network ~= nil or green_network ~= nil)
        end
        
        -- Circuit controls section (only show if wires are connected)
        local circuit_section = nil
        if has_wires then
            circuit_section = frame.add{
                type = "flow",
                name = "agricultural_roboport_circuit_section_" .. tostring(unit_key),
                direction = "vertical"
            }
        end
        
        -- Set mode of operation from circuit checkbox + signal picker (only if wires connected)
        if has_wires and circuit_section then
            local mode_control_flow = circuit_section.add{
                type = "flow",
                direction = "horizontal",
                style = "horizontal_flow"
            }
            mode_control_flow.add{
                type = "checkbox",
                name = "agricultural_roboport_circuit_mode_enable_" .. tostring(unit_key),
                state = circuit_controls_mode,
                caption = {"agricultural-roboport.circuit-set-operating-mode"},
                tooltip = {"agricultural-roboport.circuit-mode-tooltip"}
            }
            mode_control_flow.add{
                type = "choose-elem-button",
                name = "agricultural_roboport_circuit_mode_signal_" .. tostring(unit_key),
                elem_type = "signal",
                signal = settings.circuit_mode_signal or {type = "virtual", name = "signal-M"},
                enabled = circuit_controls_mode,
                style = "slot_button"
            }
            
            -- Set filters from circuit checkbox
            local filter_control_checkbox = circuit_section.add{
                type = "checkbox",
                name = "agricultural_roboport_circuit_filter_enable_" .. tostring(unit_key),
                state = settings.circuit_filter_enabled or false,
                caption = {"agricultural-roboport.circuit-set-filters"},
                tooltip = {"agricultural-roboport.circuit-filter-tooltip"}
            }
        end
        -- Filter group
        local filter_flow = frame.add{
            type = "flow",
            name = "agricultural_roboport_filter_flow_" .. tostring(unit_key),
            direction = "vertical"
        }
        filter_flow.add{
            type = "label",
            caption = {"gui-inserter.filter"}
        }
        -- Add 'Use filters' checkbox and container for filter controls
        local filter_outer_flow = filter_flow.add{
            type = "flow",
            name = "agricultural_roboport_filter_outer_flow_" .. tostring(unit_key),
            direction = "vertical"
        }
        local use_filter_row = filter_outer_flow.add{
            type = "flow",
            direction = "horizontal",
            style = "horizontal_flow"
        }
        
        -- When circuit controls filters, set use_filter to true and use circuit filters
        local effective_use_filter = circuit_controls_filters or (settings.use_filter or false)
        local effective_filters = circuit_controls_filters and circuit_filters or (settings.filters or {})
        
        local use_filter_checkbox = use_filter_row.add{
            type = "checkbox",
            name = "agricultural_roboport_use_filter_checkbox_" .. tostring(unit_key),
            state = effective_use_filter,
            caption = {"gui-inserter.use-filters"},
            enabled = not circuit_controls_filters
        }
        -- Container for the rest of the filter controls
        local filter_controls_row = filter_outer_flow.add{
            type = "flow",
            name = "agricultural_roboport_filter_controls_row_" .. tostring(unit_key),
            direction = "horizontal",
            style = "horizontal_flow"
        }
        -- Add whitelist/blacklist switch in a horizontal flow
        local switch_row = filter_controls_row.add{
            type = "flow",
            direction = "horizontal",
            style = "horizontal_flow"
        }
        switch_row.add{
            type = "label",
            caption = {"gui-inserter.whitelist"},
            style = "caption_label"
        }
        local filter_invert_switch = switch_row.add{
            type = "switch",
            name = "agricultural_roboport_filter_invert_switch_" .. tostring(unit_key),
            switch_state = (settings.filter_invert and "right") or "left",
            left_label_caption = "",
            right_label_caption = "",
            allow_none_state = false
        }
        switch_row.add{
            type = "label",
            caption = {"gui-inserter.blacklist"},
            style = "caption_label"
        }
        -- Add the filter table (choose-elem-buttons) - now with quality support
        -- Each filter slot has 2 rows: item selector and quality selector
        local filter_table = filter_controls_row.add{
            type = "table",
            name = "agricultural_roboport_filter_table_" .. tostring(unit_key),
            column_count = 5, -- 5 filter slots
            style = "filter_slot_table"
        }
        -- Use circuit filters if circuit controls filters, otherwise use manual filters
        local filters = effective_filters
        -- Only support item selection for now
        -- Use rawget(_G, 'prototypes') for prototype existence check (Factorio 2.0+)
        -- Prepare for deferred elem_value setting
        _G._agroport_deferred_elem = _G._agroport_deferred_elem or {}
        _G._agroport_deferred_elem[player.index] = {}
        -- Build a list of all seed items by checking which items can place virtual-*-seed entities
        local prototypes = rawget(_G, 'prototypes')
        local seed_names = {}
        
        write_file_log("[UI] Scanning for seeds by checking virtual seed entities...")
        
        -- Find all virtual-*-seed entities and determine which items can place them
        if prototypes and prototypes.entity then
            for entity_name, entity_proto in pairs(prototypes.entity) do
                -- Check if this is a virtual seed entity (starts with "virtual-" and has "seed" in name)
                if type(entity_name) == "string" and entity_name:match("^virtual%-.*%-seed$") then
                    -- Get items_to_place_this to find which item can place this entity
                    local items_to_place = entity_proto.items_to_place_this
                    if items_to_place and #items_to_place > 0 then
                        for _, item_to_place in ipairs(items_to_place) do
                            local item_name = item_to_place.name
                            -- Verify the item exists and has plant_result
                            if prototypes.item and prototypes.item[item_name] then
                                local item_proto = prototypes.item[item_name]
                                if item_proto.plant_result then
                                    -- Check if plant is compatible with current surface (performance & UX optimization)
                                    local plant_ref = item_proto.plant_result
                                    local surface_check_result = check_surface_conditions(plant_ref, entity.surface)
                                    if surface_check_result then
                                        -- Avoid duplicates
                                        local already_added = false
                                        for _, existing in ipairs(seed_names) do
                                            if existing == item_name then
                                                already_added = true
                                                break
                                            end
                                        end
                                        if not already_added then
                                            table.insert(seed_names, item_name)
                                            write_file_log("[UI] Added compatible seed ", item_name, " for surface ", entity.surface.name)
                                        end
                                    else
                                        write_file_log("[UI] Filtered out incompatible seed ", item_name, " for surface ", entity.surface.name, " (surface conditions not met)")
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        write_file_log("[UI] Total surface-compatible seeds added to filter: ", #seed_names)
        
        -- Blacklist mode uses simple item selector (no quality), whitelist uses item-with-quality
        local quality_enabled = is_quality_enabled()
        local is_blacklist_mode = settings.filter_invert == true
        local use_quality_selector = quality_enabled and not is_blacklist_mode
        
        for i = 1, 5 do
            local filter_entry = filters[i] -- Now a table: {name="...", quality="..."}
            local item_name = nil
            local quality_name = nil
            
            -- Handle both old string format and new table format for migration
            if type(filter_entry) == "string" then
                item_name = filter_entry
                quality_name = "normal" -- Default to normal quality for old saves
            elseif type(filter_entry) == "table" then
                item_name = filter_entry.name
                quality_name = filter_entry.quality or "normal"
            end
            
            -- Blacklist mode: always use simple item selector (no quality)
            -- Whitelist mode: use item-with-quality if quality enabled
            local filter_btn = filter_table.add{
                type = "choose-elem-button",
                name = "agricultural_roboport_filter_" .. tostring(unit_key) .. "_" .. tostring(i),
                elem_type = use_quality_selector and "item-with-quality" or "item",
                elem_filters = {
                    {filter = "name", name = seed_names}
                },
                enabled = (effective_use_filter and not circuit_controls_filters),
                style = "slot_button"
            }
            
            -- Defer setting elem_value to next tick for proper initialization
            if item_name and prototypes and prototypes.item and prototypes.item[item_name] then
                local elem_value
                if use_quality_selector then
                    elem_value = {name = item_name, quality = quality_name or "normal"}
                else
                    elem_value = item_name -- Simple string for item-only mode (blacklist or quality disabled)
                end
                table.insert(_G._agroport_deferred_elem[player.index], {button=filter_btn, value=elem_value})
            end
        end
        -- Set enabled state for switch and filter table based on use_filter_checkbox
        filter_invert_switch.enabled = use_filter_checkbox.state
        switch_row.enabled = use_filter_checkbox.state
        filter_controls_row.enabled = use_filter_checkbox.state
        -- Helper: update filter buttons and compress filters (vanilla inserter logic)
        filters = update_filter_buttons_and_compress_filters(unit_key, filter_table, use_filter_checkbox.state, filters, circuit_controls_filters)
        filter_table.enabled = true -- Table container itself should always be enabled for layout
        write_file_log("[UI] Open GUI for key=", tostring(unit_key), "mode=", tostring(mode))
        -- Log parent chain for debugging
        local function log_parent_chain(element)
            local chain = {}
            local e = element
            while e do
                table.insert(chain, 1, e.name or e.type or tostring(e))
                e = e.parent
            end
            -- write_file_log("[UI DEBUG] Parent chain: " .. table.concat(chain, " -> "))
        end
        log_parent_chain(filter_table)
        -- After creating the filter controls, set their enabled state based on the stored settings
        -- Use the unified settings table for this unit (works for real and ghost keys)
        local filter_controls_enabled = (settings and settings.use_filter) == true
        for _, child in pairs(filter_controls_row.children) do
            if child.type == "flow" then
                for _, subchild in pairs(child.children) do
                    subchild.enabled = filter_controls_enabled
                end
            else
                child.enabled = filter_controls_enabled
            end
        end
        
        -- Track that this player has this roboport GUI open for real-time updates
        storage.open_roboport_guis = storage.open_roboport_guis or {}
        storage.open_roboport_guis[event.player_index] = {
            unit_key = unit_key,
            entity = entity,
            is_roboport = is_roboport
        }
        write_file_log("[GUI OPEN] Registered GUI tracking for player", event.player_index, "unit_key=", tostring(unit_key))
    end
end

-- Remove GUI when closed
function UI.on_gui_closed(event)
    local player = game.get_player(event.player_index)
    if player.gui.relative.agricultural_roboport_mode then
        player.gui.relative.agricultural_roboport_mode.destroy()
    end
    
    -- Stop tracking this GUI
    if storage.open_roboport_guis then
        storage.open_roboport_guis[event.player_index] = nil
    end
end

-- Periodic update of open GUIs to show real-time circuit filter changes
function UI.update_open_guis()
    if not storage.open_roboport_guis then 
        write_file_log("[GUI UPDATE] No open roboport GUIs tracked")
        return 
    end
    
    local gui_count = 0
    for _ in pairs(storage.open_roboport_guis) do
        gui_count = gui_count + 1
    end
    write_file_log("[GUI UPDATE] Checking", gui_count, "open GUIs")
    
    for player_index, gui_info in pairs(storage.open_roboport_guis) do
        local player = game.get_player(player_index)
        if not (player and player.valid and player.gui.relative.agricultural_roboport_mode) then
            -- GUI is no longer open, stop tracking
            write_file_log("[GUI UPDATE] Player", player_index, "GUI no longer open")
            storage.open_roboport_guis[player_index] = nil
            goto continue
        end
        
        local entity = gui_info.entity
        local unit_key = gui_info.unit_key
        local is_roboport = gui_info.is_roboport
        
        if not (entity and entity.valid) then
            write_file_log("[GUI UPDATE] Entity for player", player_index, "no longer valid")
            storage.open_roboport_guis[player_index] = nil
            goto continue
        end
        
        -- Get settings for this roboport
        local settings = storage.agricultural_roboports[unit_key]
        if not settings then 
            write_file_log("[GUI UPDATE] No settings for unit_key", tostring(unit_key))
            goto continue 
        end
        
        local circuit_mode_enabled = settings.circuit_mode_enabled or false
        local circuit_filter_enabled = settings.circuit_filter_enabled or false
        write_file_log("[GUI UPDATE] Player", player_index, "circuit_mode_enabled=", circuit_mode_enabled, "circuit_filter_enabled=", circuit_filter_enabled)
        
        -- Skip if neither circuit control is enabled
        if not circuit_mode_enabled and not circuit_filter_enabled then goto continue end
        
        -- Read circuit networks
        if is_roboport and entity.get_control_behavior then
            local red_network = entity.get_circuit_network(defines.wire_connector_id.circuit_red)
            local green_network = entity.get_circuit_network(defines.wire_connector_id.circuit_green)
            
            write_file_log("[GUI UPDATE] Networks: red=", red_network ~= nil, "green=", green_network ~= nil)
            
            local frame = player.gui.relative.agricultural_roboport_mode
            if not frame then goto continue end
            
            -- Update operating mode switch if circuit controls it
            if circuit_mode_enabled then
                local mode_signal = settings.circuit_mode_signal or {type = "virtual", name = "signal-M"}
                if mode_signal and mode_signal.name then
                    local signal_value = 0
                    
                    if red_network then
                        local signal = red_network.get_signal(mode_signal)
                        if signal then signal_value = signal_value + signal end
                    end
                    if green_network then
                        local signal = green_network.get_signal(mode_signal)
                        if signal then signal_value = signal_value + signal end
                    end
                    
                    -- Determine mode from signal
                    local circuit_mode = 0
                    if signal_value < 0 then
                        circuit_mode = -1
                    elseif signal_value > 0 then
                        circuit_mode = 1
                    end
                    
                    -- Update mode switch display
                    local mode_switch = frame["agricultural_roboport_mode_switch_" .. tostring(unit_key)]
                    if mode_switch and mode_switch.valid then
                        mode_switch.switch_state = mode_to_switch_state(circuit_mode)
                        write_file_log("[GUI UPDATE] Updated mode switch to", circuit_mode, "from signal value", signal_value)
                    end
                end
            end
            
            -- Update filters if circuit controls them
            if circuit_filter_enabled then
                -- Read filters from circuit (even if no signals present, to clear the display)
                local circuit_filters = {}
                
                if red_network or green_network then
                    local virtual_seed_info = storage.virtual_seed_info
                    if not virtual_seed_info then
                        virtual_seed_info = Build_virtual_seed_info and Build_virtual_seed_info() or {}
                    end
                    
                    local function read_filter_signals(network)
                        if not network then return end
                        local signals = network.signals
                        if not signals then return end
                        
                        for _, signal_data in ipairs(signals) do
                            if signal_data.signal and signal_data.signal.name and signal_data.count > 0 then
                                local signal_name = signal_data.signal.name
                                if virtual_seed_info[signal_name] then
                                    local quality_name = "normal"
                                    -- Quality field is a string, not an object
                                    if signal_data.signal.quality then
                                        quality_name = signal_data.signal.quality
                                    end
                                    table.insert(circuit_filters, {name = signal_name, quality = quality_name})
                                end
                            end
                        end
                    end
                    
                    read_filter_signals(red_network)
                    read_filter_signals(green_network)
                end
                
                write_file_log("[GUI UPDATE] Circuit filters found:", #circuit_filters)
                
                -- Update filter button display
                local filter_flow = frame["agricultural_roboport_filter_flow_" .. tostring(unit_key)]
                if filter_flow then
                    local filter_outer = filter_flow["agricultural_roboport_filter_outer_flow_" .. tostring(unit_key)]
                    if filter_outer then
                        local filter_controls = filter_outer["agricultural_roboport_filter_controls_row_" .. tostring(unit_key)]
                        if filter_controls then
                            local filter_table = filter_controls["agricultural_roboport_filter_table_" .. tostring(unit_key)]
                            if filter_table then
                                -- Update filter button values to show circuit filters
                                local quality_enabled = is_quality_enabled()
                                
                                for i = 1, 5 do
                                    local filter_btn = filter_table["agricultural_roboport_filter_" .. tostring(unit_key) .. "_" .. tostring(i)]
                                    if filter_btn and filter_btn.valid then
                                        local filter_entry = circuit_filters[i]
                                        
                                        if filter_entry and type(filter_entry) == "table" and filter_entry.name then
                                            local uses_quality_selector = (filter_btn.elem_type == "item-with-quality")
                                            if uses_quality_selector then
                                                filter_btn.elem_value = {
                                                    name = filter_entry.name,
                                                    quality = filter_entry.quality or "normal"
                                                }
                                            else
                                                filter_btn.elem_value = filter_entry.name
                                            end
                                        else
                                            -- Clear empty slots
                                            filter_btn.elem_value = nil
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        ::continue::
    end
end

-- Handle filter choose-elem-button (both item and quality selectors)
function UI.on_gui_elem_changed(event)
    local element = event.element
    if not (element and element.valid) then return end
    
    -- Handle vegetation planner filter selection
    if element.name:find("^vegetation_planner_filter_") then
        local idx = tonumber(element.name:match("^vegetation_planner_filter_(%d+)$"))
        if idx then
            local planner_settings = get_planner_settings(event.player_index)
            local filters = planner_settings.filters or {}
            if type(filters) ~= "table" then filters = {} end
            
            local quality_enabled = is_quality_enabled()
            local is_blacklist = planner_settings.filter_invert == true
            
            if element.elem_value then
                local item_name, quality_name
                
                if type(element.elem_value) == "table" then
                    -- Item-with-quality mode
                    item_name = element.elem_value.name
                    quality_name = element.elem_value.quality or "normal"
                else
                    -- Simple item mode
                    item_name = element.elem_value
                    quality_name = "normal"
                end
                
                -- Check for duplicates (same logic as roboport)
                local is_duplicate = false
                if is_blacklist then
                    -- Blacklist: check if item name already exists (quality doesn't matter)
                    for i = 1, 5 do
                        if i ~= idx and filters[i] then
                            local other_entry = filters[i]
                            local other_name = type(other_entry) == "table" and other_entry.name or other_entry
                            if other_name == item_name then
                                is_duplicate = true
                                break
                            end
                        end
                    end
                else
                    -- Whitelist: check exact item+quality combination
                    for i = 1, 5 do
                        if i ~= idx and filters[i] then
                            local other_entry = filters[i]
                            local other_name = type(other_entry) == "table" and other_entry.name or other_entry
                            local other_quality = type(other_entry) == "table" and (other_entry.quality or "normal") or "normal"
                            if other_name == item_name and other_quality == quality_name then
                                is_duplicate = true
                                break
                            end
                        end
                    end
                end
                
                if is_duplicate then
                    -- Reject duplicate - clear the selection
                    element.elem_value = nil
                    filters[idx] = nil
                else
                    -- Store with proper format
                    if is_blacklist then
                        filters[idx] = {name = item_name, quality = "normal"}
                    elseif quality_enabled then
                        filters[idx] = {name = item_name, quality = quality_name}
                    else
                        filters[idx] = {name = item_name, quality = "normal"}
                    end
                end
            else
                -- Clear filter
                filters[idx] = nil
            end
            
            -- Compress filters
            local new_filters = {}
            for i = 1, 5 do
                if filters[i] ~= nil then
                    table.insert(new_filters, filters[i])
                end
            end
            for i = #new_filters + 1, 5 do
                new_filters[i] = nil
            end
            planner_settings.filters = new_filters
            
            -- Update UI buttons to reflect compressed filters
            local player = game.get_player(event.player_index)
            if player and player.valid then
                local filter_table = element.parent
                if filter_table and filter_table.valid then
                    -- Update all filter buttons with compressed array
                    for i = 1, 5 do
                        local btn = filter_table["vegetation_planner_filter_" .. i]
                        if btn and btn.valid then
                            local filter_entry = new_filters[i]
                            if filter_entry then
                                local item_name, quality_name
                                
                                if type(filter_entry) == "string" then
                                    item_name = filter_entry
                                    quality_name = "normal"
                                elseif type(filter_entry) == "table" then
                                    item_name = filter_entry.name
                                    quality_name = filter_entry.quality or "normal"
                                end
                                
                                if item_name then
                                    if quality_enabled and not is_blacklist then
                                        btn.elem_value = {name = item_name, quality = quality_name}
                                    else
                                        btn.elem_value = item_name
                                    end
                                end
                            else
                                -- Clear empty slots
                                btn.elem_value = nil
                            end
                        end
                    end
                end
            end
            
            -- Debug logging
            if quality_enabled and type(element.elem_value) == "table" then
                write_file_log("[Vegetation Planner] Selected filter index=", tostring(idx), "value=", tostring(element.elem_value and (element.elem_value.name .. "@" .. element.elem_value.quality) or "nil"))
            else
                write_file_log("[Vegetation Planner] Selected filter index=", tostring(idx), "value=", tostring(element.elem_value or "nil"))
            end
        end
        return
    end
    
    -- Handle agricultural roboport filter selection (item-with-quality selector OR simple item selector)
    if element.name:find("^agricultural_roboport_filter_") then
        local unit_key, idx = element.name:match("^agricultural_roboport_filter_(.+)_(%d+)$")
        if unit_key and idx then
            local num_key = tonumber(unit_key)
            if num_key then unit_key = num_key end
            idx = tonumber(idx)
            if not storage.agricultural_roboports[unit_key] then
                storage.agricultural_roboports[unit_key] = {mode=0,seed_logistic_only=false,use_filter=false,filter_invert=false,filters=nil}
            end
            local settings = storage.agricultural_roboports[unit_key]
            local filters = settings.filters or {}
            if type(filters) ~= "table" then filters = {} end
            
            local quality_enabled = is_quality_enabled()
            local is_blacklist_mode = settings.filter_invert == true
            
            -- Update or create filter entry
            if element.elem_value then
                local item_name, quality_name
                
                if type(element.elem_value) == "table" then
                    -- Item-with-quality mode - elem_value is {name="item-name", quality="quality-name"}
                    item_name = element.elem_value.name
                    quality_name = element.elem_value.quality or "normal"
                else
                    -- Simple item mode - elem_value is just the item name string
                    item_name = element.elem_value
                    quality_name = "normal"
                end
                
                -- For blacklist mode, check item name only (ignore quality)
                -- For whitelist mode, check exact item+quality combination
                local is_duplicate = false
                if is_blacklist_mode then
                    -- Blacklist: check if item name already exists (quality doesn't matter)
                    for i = 1, 5 do
                        if i ~= idx and filters[i] then
                            local other_entry = filters[i]
                            local other_name = type(other_entry) == "table" and other_entry.name or other_entry
                            if other_name == item_name then
                                is_duplicate = true
                                break
                            end
                        end
                    end
                else
                    -- Whitelist: check exact item+quality combination
                    for i = 1, 5 do
                        if i ~= idx and filters[i] then
                            local other_entry = filters[i]
                            local other_name = type(other_entry) == "table" and other_entry.name or other_entry
                            local other_quality = type(other_entry) == "table" and (other_entry.quality or "normal") or "normal"
                            if other_name == item_name and other_quality == quality_name then
                                is_duplicate = true
                                break
                            end
                        end
                    end
                end
                
                if is_duplicate then
                    -- Reject duplicate - clear the selection
                    element.elem_value = nil
                    filters[idx] = nil
                else
                    -- Blacklist mode: always store with normal quality (quality is ignored)
                    -- Whitelist mode: store with actual quality
                    if is_blacklist_mode then
                        filters[idx] = {name = item_name, quality = "normal"}
                    elseif quality_enabled then
                        filters[idx] = {name = item_name, quality = quality_name}
                    else
                        filters[idx] = {name = item_name, quality = "normal"}
                    end
                end
            else
                -- Item cleared - remove filter entry entirely
                filters[idx] = nil
            end
            
            -- Compress filters (remove nils, shift left)
            local new_filters = {}
            for i = 1, 5 do
                if filters[i] ~= nil then
                    table.insert(new_filters, filters[i])
                end
            end
            for i = #new_filters + 1, 5 do
                new_filters[i] = nil
            end
            settings.filters = new_filters
            
            -- Update UI
            local player = game.get_player(event.player_index)
            if player and player.valid then
                local filter_table = element.parent
                local circuit_controls_filters = settings.circuit_filter_enabled or false
                update_filter_buttons_and_compress_filters(unit_key, filter_table, settings.use_filter == true, new_filters, circuit_controls_filters)
                if quality_enabled and type(element.elem_value) == "table" then
                    write_file_log("[UI] Selected filter for key=", tostring(unit_key), "index=", tostring(idx), "value=", tostring(element.elem_value and (element.elem_value.name .. "@" .. element.elem_value.quality) or "nil"))
                else
                    write_file_log("[UI] Selected filter for key=", tostring(unit_key), "index=", tostring(idx), "value=", tostring(element.elem_value or "nil"))
                end
            end
        end
    end
    
    -- Handle circuit mode signal picker
    if element.name and element.name:find("^agricultural_roboport_circuit_mode_signal_") then
        local unit_key = element.name:match("^agricultural_roboport_circuit_mode_signal_(.+)$")
        if unit_key then
            local num_key = tonumber(unit_key)
            if num_key then unit_key = num_key end
            if not storage.agricultural_roboports[unit_key] then
                storage.agricultural_roboports[unit_key] = {mode=0,seed_logistic_only=false,use_filter=false,filter_invert=false,filters=nil}
            end
            local settings = storage.agricultural_roboports[unit_key]
            if element.elem_value then
                settings.circuit_mode_signal = element.elem_value
                write_file_log("[UI] Set circuit mode signal for key=", tostring(unit_key), " to ", serpent.line(element.elem_value))
            end
        end
    end
end

-- Handle quality dropdown selection changes
-- Deferred elem_value setter for choose-elem-buttons
function UI.on_tick(event)
    -- Handle deferred elem_value setting for choose-elem-buttons
    if _G._agroport_deferred_elem then
        for player_index, btns in pairs(_G._agroport_deferred_elem) do
            -- Verify player exists (may be nil in editor mode)
            local player = game.get_player(player_index)
            if not player then
                _G._agroport_deferred_elem[player_index] = nil
                goto continue
            end
            
            for _, entry in pairs(btns) do
                if entry.button and entry.button.valid then
                    entry.button.elem_value = entry.value
                end
            end
            _G._agroport_deferred_elem[player_index] = nil
            ::continue::
        end
    end
    
    -- Update open roboport GUIs with circuit filter changes (every 10 ticks for performance)
    if event.tick % 10 == 0 then
        UI.update_open_guis()
    end
end

-- Helper: rebuild filter table when switching between whitelist/blacklist modes
function rebuild_filter_table(player, unit_key, old_filter_table, settings, surface)
    local parent = old_filter_table.parent
    local filters = settings.filters or {}
    
    -- Build seed names list with surface compatibility filtering
    local prototypes = rawget(_G, 'prototypes')
    local seed_names = {}
    if prototypes and prototypes.entity then
        for entity_name, entity_proto in pairs(prototypes.entity) do
            if type(entity_name) == "string" and entity_name:match("^virtual%-.*%-seed$") then
                local items_to_place = entity_proto.items_to_place_this
                if items_to_place and #items_to_place > 0 then
                    for _, item_to_place in ipairs(items_to_place) do
                        local item_name = item_to_place.name
                        local item_proto = prototypes.item and prototypes.item[item_name]
                        if item_proto and item_proto.plant_result then
                            -- Check surface compatibility if surface is provided
                            if surface and not check_surface_conditions(item_proto.plant_result, surface) then
                                write_file_log("[UI rebuild] Filtered out incompatible seed ", item_name, " for surface ", surface.name)
                                goto skip_item
                            end
                            
                            local already_added = false
                            for _, existing in ipairs(seed_names) do
                                if existing == item_name then
                                    already_added = true
                                    break
                                end
                            end
                            if not already_added then
                                table.insert(seed_names, item_name)
                            end
                            ::skip_item::
                        end
                    end
                end
            end
        end
    end
    
    -- Destroy old table
    old_filter_table.destroy()
    
    -- Create new table with appropriate elem_type
    local quality_enabled = is_quality_enabled()
    local is_blacklist_mode = settings.filter_invert == true
    local use_quality_selector = quality_enabled and not is_blacklist_mode
    
    local filter_table = parent.add{
        type = "table",
        name = "agricultural_roboport_filter_table_" .. tostring(unit_key),
        column_count = 5,
        style = "filter_slot_table"
    }
    
    -- Prepare deferred elem setting
    _G._agroport_deferred_elem = _G._agroport_deferred_elem or {}
    _G._agroport_deferred_elem[player.index] = _G._agroport_deferred_elem[player.index] or {}
    
    for i = 1, 5 do
        local filter_entry = filters[i]
        local item_name = nil
        local quality_name = nil
        
        if type(filter_entry) == "string" then
            item_name = filter_entry
            quality_name = "normal"
        elseif type(filter_entry) == "table" then
            item_name = filter_entry.name
            quality_name = filter_entry.quality or "normal"
        end
        
        local filter_btn = filter_table.add{
            type = "choose-elem-button",
            name = "agricultural_roboport_filter_" .. tostring(unit_key) .. "_" .. tostring(i),
            elem_type = use_quality_selector and "item-with-quality" or "item",
            elem_filters = {
                {filter = "name", name = seed_names}
            },
            enabled = (settings.use_filter and not (settings.circuit_filter_enabled or false)),
            style = "slot_button"
        }
        
        if item_name and prototypes and prototypes.item and prototypes.item[item_name] then
            local elem_value
            if use_quality_selector then
                elem_value = {name = item_name, quality = quality_name or "normal"}
            else
                -- For item-only selector (blacklist mode), use simple string
                elem_value = item_name
            end
            table.insert(_G._agroport_deferred_elem[player.index], {button=filter_btn, value=elem_value})
        end
    end
    
    -- Update button states
    update_filter_buttons_and_compress_filters(unit_key, filter_table, settings.use_filter or false, filters, false)
end

-- Helper: update filter buttons and compress filters with quality support
function update_filter_buttons_and_compress_filters(unit_key, filter_table, use_filter_enabled, filters, circuit_controls_filters)
    -- Compress filters array to the start (remove nil gaps)
    local compressed_filters = {}
    for i = 1, 5 do
        if filters[i] ~= nil then
            table.insert(compressed_filters, filters[i])
        end
    end
    for i = #compressed_filters + 1, 5 do
        compressed_filters[i] = nil
    end
    
    local quality_enabled = is_quality_enabled()
    
    -- Update each filter button with item-with-quality or simple item
    for i = 1, 5 do
        local filter_btn = filter_table["agricultural_roboport_filter_" .. tostring(unit_key) .. "_" .. tostring(i)]
        if filter_btn and filter_btn.valid then
            local filter_entry = compressed_filters[i]
            
            -- Determine if this button uses quality selector based on its elem_type
            local uses_quality_selector = (filter_btn.elem_type == "item-with-quality")
            
            -- Set button value
            if filter_entry and type(filter_entry) == "table" and filter_entry.name then
                if uses_quality_selector then
                    filter_btn.elem_value = {
                        name = filter_entry.name,
                        quality = filter_entry.quality or "normal"
                    }
                else
                    -- Simple item selector - use string only
                    filter_btn.elem_value = filter_entry.name
                end
            else
                filter_btn.elem_value = nil
            end
        end
    end
    
    -- Enable/disable filter slots based on use_filter, circuit control, and slot status
    local first_empty = nil
    for i = 1, 5 do
        local filter_entry = compressed_filters[i]
        if filter_entry == nil and not first_empty then
            first_empty = i
        end
    end
    
    for i = 1, 5 do
        local filter_btn = filter_table["agricultural_roboport_filter_" .. tostring(unit_key) .. "_" .. tostring(i)]
        if filter_btn and filter_btn.valid then
            -- Disable if circuit controls filters
            if circuit_controls_filters then
                filter_btn.enabled = false
            elseif use_filter_enabled then
                -- Enable if has value OR is first empty slot
                filter_btn.enabled = (compressed_filters[i] ~= nil or i == first_empty)
            else
                filter_btn.enabled = false
            end
        end
    end
    
    -- Save compressed filters back to settings table
    local settings = storage.agricultural_roboports[unit_key]
    settings.filters = compressed_filters
    
    -- Update filter visualization in alt-mode
    local entity = nil
    for _, surface in pairs(game.surfaces) do
        local entities = surface.find_entities_filtered{name = "agricultural-roboport"}
        for _, ent in ipairs(entities) do
            if ent.unit_number == tonumber(unit_key) then
                entity = ent
                break
            end
        end
        if entity then break end
    end
    
    return compressed_filters
end

-- Event: Cursor stack changed (show/hide vegetation planner GUI)
function UI.on_player_cursor_stack_changed(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    
    local cursor = player.cursor_stack
    if cursor and cursor.valid_for_read and cursor.name == "vegetation-planner" then
        -- Check if player has researched the technology
        if not player.force.technologies["agricultural-soil-analysis"].researched then
            -- Tech not researched - clear cursor
            player.clear_cursor()
            player.print({"vegetation-planner.tech-not-researched"})
            player.set_shortcut_toggled("vegetation-planner", false)
            return
        end
        
        -- Player picked up the vegetation planner - show GUI and toggle shortcut
        local planner_settings = get_planner_settings(event.player_index)
        create_planner_config_gui(player, planner_settings)
        player.set_shortcut_toggled("vegetation-planner", true)
    else
        -- Player cleared cursor or switched items - hide GUI and untoggle shortcut
        destroy_planner_config_gui(player)
        player.set_shortcut_toggled("vegetation-planner", false)
    end
end

-- Handle shortcut click (toggle tool in/out of cursor)
function UI.on_lua_shortcut(event)
    if event.prototype_name ~= "vegetation-planner" then return end
    
    local player = game.get_player(event.player_index)
    if not player then return end
    
    -- Check if player has researched the technology
    if not player.force.technologies["agricultural-soil-analysis"].researched then
        player.print({"vegetation-planner.tech-not-researched"})
        player.set_shortcut_toggled("vegetation-planner", false)
        return
    end
    
    local cursor = player.cursor_stack
    if cursor and cursor.valid_for_read and cursor.name == "vegetation-planner" then
        -- Tool is already in cursor - clear it
        player.clear_cursor()
        player.set_shortcut_toggled("vegetation-planner", false)
    else
        -- Give player the tool
        player.clear_cursor()
        player.cursor_stack.set_stack{name = "vegetation-planner", count = 1}
        player.set_shortcut_toggled("vegetation-planner", true)
    end
end

-- Extend existing GUI event handlers to handle both roboport and vegetation planner
-- (Merged handler - handles both roboport and vegetation planner checkboxes)
function UI.on_gui_checked_state_changed(event)
    if not event.element or not event.element.valid then return end
    local element = event.element
    local element_name = element.name
    
    -- Handle vegetation planner elements
    if element_name and element_name:match("^vegetation_planner_") then
        local player = game.get_player(event.player_index)
        if not player then return end
        
        local planner_settings = get_planner_settings(event.player_index)
        
        if element_name == "vegetation_planner_use_filter" then
            planner_settings.use_filter = event.element.state
            
            -- Update filter controls enabled state in real-time
            local frame = player.gui.screen.vegetation_planner_config
            if frame then
                local filter_controls = frame.vegetation_planner_filter_controls
                if filter_controls then
                    filter_controls.enabled = event.element.state
                    
                    -- Update switch enabled state and label colors
                    local filter_mode_flow = filter_controls.children[1]
                    if filter_mode_flow then
                        local whitelist_label = filter_mode_flow.vegetation_planner_whitelist_label
                        local switch = filter_mode_flow.vegetation_planner_filter_invert
                        local blacklist_label = filter_mode_flow.vegetation_planner_blacklist_label
                        
                        if switch and switch.valid then
                            switch.enabled = event.element.state
                        end
                        
                        -- Update label colors
                        if whitelist_label and blacklist_label then
                            if event.element.state then
                                whitelist_label.style.font_color = {r=1, g=1, b=1}
                                blacklist_label.style.font_color = {r=1, g=1, b=1}
                            else
                                whitelist_label.style.font_color = {r=0.5, g=0.5, b=0.5}
                                blacklist_label.style.font_color = {r=0.5, g=0.5, b=0.5}
                            end
                        end
                    end
                    
                    -- Also update individual filter buttons
                    local filter_table = filter_controls.vegetation_planner_filter_table
                    if filter_table then
                        for i = 1, 5 do
                            local btn = filter_table["vegetation_planner_filter_" .. i]
                            if btn and btn.valid then
                                btn.enabled = event.element.state
                            end
                        end
                    end
                end
            end
        elseif element_name == "vegetation_planner_force_sparse" then
            planner_settings.force_sparse = event.element.state
        end
    -- Handle agricultural roboport 'Use filters' checkbox
    elseif element_name and element_name:find("^agricultural_roboport_use_filter_checkbox_") then
        local unit_key = element_name:match("^agricultural_roboport_use_filter_checkbox_(.+)$")
        if unit_key then
            local num_key = tonumber(unit_key)
            if num_key then unit_key = num_key end
            if not storage.agricultural_roboports[unit_key] then
                storage.agricultural_roboports[unit_key] = {mode=0,seed_logistic_only=false,use_filter=false,filter_invert=false,filters=nil}
            end
            local settings = storage.agricultural_roboports[unit_key]
            local new_state = (element.state == true)
            settings.use_filter = new_state
            write_file_log("[UI] Use filters checkbox for key=", tostring(unit_key), "state=", tostring(new_state))
            -- Get circuit filter control state
            local circuit_controls_filters = settings.circuit_filter_enabled or false
            -- Gray out or enable filter controls accordingly
            local parent = element.parent and element.parent.parent
            if parent then
                local controls_row = parent["agricultural_roboport_filter_controls_row_" .. tostring(unit_key)]
                if controls_row then
                    for _, child in pairs(controls_row.children) do
                        if child.type == "flow" then
                            for _, subchild in pairs(child.children) do
                                subchild.enabled = new_state and not circuit_controls_filters
                            end
                        elseif child.type == "table" then
                            local filters = settings.filters or {}
                            update_filter_buttons_and_compress_filters(unit_key, child, new_state, filters, circuit_controls_filters)
                        else
                            child.enabled = new_state and not circuit_controls_filters
                        end
                    end
                end
            end
        end
    -- Handle 'Seed in logistic area only' checkbox
    elseif element_name and element_name:find("^agricultural_roboport_seed_logistic_only_") then
        local unit_key = element_name:match("^agricultural_roboport_seed_logistic_only_(.+)$")
        if unit_key then
            local num_key = tonumber(unit_key)
            if num_key then unit_key = num_key end
            if not storage.agricultural_roboports[unit_key] then
                storage.agricultural_roboports[unit_key] = {mode=0,seed_logistic_only=false,use_filter=false,filter_invert=false,filters=nil}
            end
            local settings = storage.agricultural_roboports[unit_key]
            settings.seed_logistic_only = element.state
        end
    -- Handle 'Set mode of operation from circuit' checkbox
    elseif element_name and element_name:find("^agricultural_roboport_circuit_mode_enable_") then
        local unit_key = element_name:match("^agricultural_roboport_circuit_mode_enable_(.+)$")
        if unit_key then
            local num_key = tonumber(unit_key)
            if num_key then unit_key = num_key end
            if not storage.agricultural_roboports[unit_key] then
                storage.agricultural_roboports[unit_key] = {mode=0,seed_logistic_only=false,use_filter=false,filter_invert=false,filters=nil}
            end
            local settings = storage.agricultural_roboports[unit_key]
            settings.circuit_mode_enabled = element.state
            
            -- Enable/disable mode signal picker
            local parent = element.parent
            if parent then
                local signal_btn = parent["agricultural_roboport_circuit_mode_signal_" .. tostring(unit_key)]
                if signal_btn then
                    signal_btn.enabled = element.state
                end
            end
            
            -- Enable/disable mode switch based on circuit control
            -- Navigate up to frame level: element -> mode_control_flow -> circuit_section -> frame
            local frame = element.parent and element.parent.parent and element.parent.parent.parent
            if frame then
                local mode_switch = frame["agricultural_roboport_mode_switch_" .. tostring(unit_key)]
                if mode_switch then
                    mode_switch.enabled = not element.state
                    write_file_log("[CHECKBOX] Set mode_switch.enabled =", not element.state)
                    -- When disabling circuit control, restore the switch to show the stored mode
                    if not element.state then
                        mode_switch.switch_state = mode_to_switch_state(settings.mode or 0)
                        write_file_log("[CHECKBOX] Restored mode_switch to", settings.mode or 0)
                    end
                end
            end
        end
    -- Handle 'Set filters from circuit' checkbox
    elseif element_name and element_name:find("^agricultural_roboport_circuit_filter_enable_") then
        local unit_key = element_name:match("^agricultural_roboport_circuit_filter_enable_(.+)$")
        if unit_key then
            local num_key = tonumber(unit_key)
            if num_key then unit_key = num_key end
            if not storage.agricultural_roboports[unit_key] then
                storage.agricultural_roboports[unit_key] = {mode=0,seed_logistic_only=false,use_filter=false,filter_invert=false,filters=nil}
            end
            local settings = storage.agricultural_roboports[unit_key]
            settings.circuit_filter_enabled = element.state
            
            -- Enable/disable manual filter controls
            local grandparent = element.parent and element.parent.parent
            if grandparent then
                local use_filter_outer = grandparent["agricultural_roboport_filter_flow_" .. tostring(unit_key)]
                if use_filter_outer then
                    local filter_outer = use_filter_outer["agricultural_roboport_filter_outer_flow_" .. tostring(unit_key)]
                    if filter_outer then
                        local use_filter_checkbox = nil
                        for _, child in pairs(filter_outer.children) do
                            if child.type == "flow" then
                                for _, subchild in pairs(child.children) do
                                    if subchild.name and subchild.name:find("^agricultural_roboport_use_filter_checkbox_") then
                                        use_filter_checkbox = subchild
                                        break
                                    end
                                end
                            end
                        end
                        
                        if use_filter_checkbox then
                            use_filter_checkbox.enabled = not element.state
                        end
                        
                        local filter_controls = filter_outer["agricultural_roboport_filter_controls_row_" .. tostring(unit_key)]
                        if filter_controls then
                            local filter_table = filter_controls["agricultural_roboport_filter_table_" .. tostring(unit_key)]
                            
                            -- Update all filter controls and individual buttons
                            for _, child in pairs(filter_controls.children) do
                                if element.state then
                                    child.enabled = false
                                else
                                    -- Re-enable based on use_filter checkbox state
                                    if use_filter_checkbox then
                                        child.enabled = use_filter_checkbox.state
                                    end
                                end
                            end
                            
                            -- Explicitly update filter buttons using the helper function
                            if filter_table then
                                update_filter_buttons_and_compress_filters(
                                    unit_key,
                                    filter_table,
                                    use_filter_checkbox and use_filter_checkbox.state or false,
                                    settings.filters or {},
                                    element.state
                                )
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Extend GUI switch handler to handle both roboport and vegetation planner
-- (Merged handler - handles both systems)
function UI.on_gui_switch_state_changed(event)
    if not event.element or not event.element.valid then return end
    local element = event.element
    local element_name = element.name
    
    -- Handle vegetation planner elements
    if element_name and element_name:match("^vegetation_planner_") then
        if element_name == "vegetation_planner_filter_invert" then
            local player = game.get_player(event.player_index)
            local planner_settings = get_planner_settings(event.player_index)
            local old_invert = planner_settings.filter_invert
            planner_settings.filter_invert = (element.switch_state == "right")
            
            -- When switching to blacklist mode, strip quality from all filters (keep only item names)
            if planner_settings.filter_invert and not old_invert then
                local filters = planner_settings.filters or {}
                for i = 1, #filters do
                    if type(filters[i]) == "table" and filters[i].name then
                        filters[i] = {name = filters[i].name, quality = "normal"}
                    end
                end
                planner_settings.filters = filters
            end
            
            -- Rebuild filter table to switch between item-with-quality and item elem_type
            if player and player.gui.screen.vegetation_planner_config then
                local frame = player.gui.screen.vegetation_planner_config
                local filter_controls = frame.vegetation_planner_filter_controls
                if filter_controls then
                    local old_filter_table = filter_controls.vegetation_planner_filter_table
                    if old_filter_table then
                        -- Get current filters
                        local filters = planner_settings.filters or {}
                        local is_blacklist = planner_settings.filter_invert
                        local quality_enabled = is_quality_enabled()
                        local use_filter = planner_settings.use_filter or false
                        
                        -- Destroy old table
                        old_filter_table.destroy()
                        
                        -- Create new table with correct elem_type
                        local new_filter_table = filter_controls.add{
                            type = "table",
                            name = "vegetation_planner_filter_table",
                            column_count = 5,
                            style = "filter_slot_table"
                        }
                        
                        -- Get available seeds
                        local seed_names = get_available_seeds()
                        
                        -- Create buttons with correct elem_type
                        for i = 1, 5 do
                            local filter_entry = filters[i]
                            
                            local btn = new_filter_table.add{
                                type = "choose-elem-button",
                                name = "vegetation_planner_filter_" .. i,
                                elem_type = (quality_enabled and not is_blacklist) and "item-with-quality" or "item",
                                elem_filters = {
                                    {filter = "name", name = seed_names}
                                },
                                enabled = use_filter,
                                style = "slot_button"
                            }
                            
                            -- Set current value if exists
                            if filter_entry then
                                local item_name, quality_name
                                
                                if type(filter_entry) == "string" then
                                    item_name = filter_entry
                                    quality_name = "normal"
                                elseif type(filter_entry) == "table" then
                                    item_name = filter_entry.name
                                    quality_name = filter_entry.quality or "normal"
                                end
                                
                                if item_name then
                                    if quality_enabled and not is_blacklist then
                                        -- Whitelist with quality: use item-with-quality
                                        btn.elem_value = {name = item_name, quality = quality_name}
                                    else
                                        -- Blacklist or no quality: use simple item name
                                        btn.elem_value = item_name
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    -- Handle roboport mode switch
    elseif element_name and element_name:find("^agricultural_roboport_mode_switch_") then
        local unit_key = element_name:match("^agricultural_roboport_mode_switch_(.+)$")
        if unit_key then
            local num_key = tonumber(unit_key)
            if num_key then unit_key = num_key end
            if not storage.agricultural_roboports[unit_key] then
                storage.agricultural_roboports[unit_key] = {mode=0,seed_logistic_only=false,use_filter=false,filter_invert=false,filters=nil}
            end
            local settings = storage.agricultural_roboports[unit_key]
            local new_mode = switch_state_to_mode(element.switch_state)
            settings.mode = new_mode
        end
    -- Handle filter invert switch
    elseif element_name and element_name:find("^agricultural_roboport_filter_invert_switch_") then
        local unit_key = element_name:match("^agricultural_roboport_filter_invert_switch_(.+)$")
        if unit_key then
            local num_key = tonumber(unit_key)
            if num_key then unit_key = num_key end
            if not storage.agricultural_roboports[unit_key] then
                storage.agricultural_roboports[unit_key] = {mode=0,seed_logistic_only=false,use_filter=false,filter_invert=false,filters=nil}
            end
            local settings = storage.agricultural_roboports[unit_key]
            local invert = (element.switch_state == "right")
            settings.filter_invert = invert
            
            -- When switching to blacklist mode, strip quality from all filters (keep only item names)
            if invert then
                local filters = settings.filters or {}
                for i = 1, #filters do
                    if type(filters[i]) == "table" and filters[i].name then
                        filters[i] = {name = filters[i].name, quality = "normal"}
                    end
                end
                settings.filters = filters
            end
            
            -- Rebuild the filter UI to switch between item and item-with-quality selectors
            local player = game.get_player(event.player_index)
            if player and player.gui.relative.agricultural_roboport_mode then
                -- Find the roboport entity to get its surface
                local roboport_entity = nil
                if type(unit_key) == "number" then
                    for _, surface in pairs(game.surfaces) do
                        for _, roboport in pairs(surface.find_entities_filtered{name="agricultural-roboport"}) do
                            if roboport.unit_number == unit_key then
                                roboport_entity = roboport
                                break
                            end
                        end
                        if roboport_entity then break end
                    end
                elseif type(unit_key) == "string" and unit_key:match("^ghost_") then
                    local _, _, surface_name = unit_key:match("^ghost_[%d%.%-]+_[%d%.%-]+_(.+)$")
                    if surface_name and game.surfaces[surface_name] then
                        roboport_entity = {surface = game.surfaces[surface_name]}
                    end
                end
                
                -- Find and rebuild filter table
                local frame = player.gui.relative.agricultural_roboport_mode
                local filter_flow = frame["agricultural_roboport_filter_flow_" .. tostring(unit_key)]
                if filter_flow then
                    local filter_outer = filter_flow["agricultural_roboport_filter_outer_flow_" .. tostring(unit_key)]
                    if filter_outer then
                        local filter_controls = filter_outer["agricultural_roboport_filter_controls_row_" .. tostring(unit_key)]
                        if filter_controls then
                            local filter_table = filter_controls["agricultural_roboport_filter_table_" .. tostring(unit_key)]
                            if filter_table and roboport_entity then
                                rebuild_filter_table(player, unit_key, filter_table, settings, roboport_entity.surface)
                                -- After rebuild, update button states based on circuit control
                                local new_filter_table = filter_controls["agricultural_roboport_filter_table_" .. tostring(unit_key)]
                                if new_filter_table then
                                    local circuit_controls_filters = settings.circuit_filter_enabled or false
                                    update_filter_buttons_and_compress_filters(unit_key, new_filter_table, settings.use_filter or false, settings.filters or {}, circuit_controls_filters)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Extend GUI click handler to handle both roboport and vegetation planner
-- (Merged handler - handles both systems)
function UI.on_gui_click(event)
    -- Vegetation planner and roboport use choose-elem-button, switches, and checkboxes
    -- No click handlers needed
end

return UI
