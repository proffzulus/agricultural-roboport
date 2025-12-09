-- filepath: scripts/UI.lua
-- All GUI-related event handlers for agricultural-roboport mod

local UI = {}
local helpers = helpers or require('helpers')
local serpent = serpent or require('serpent')

-- Helper to check if quality support is enabled (startup setting)
local function is_quality_enabled()
    if settings and settings.startup and settings.startup["agricultural-roboport-enable-quality"] then
        return settings.startup["agricultural-roboport-enable-quality"].value
    end
    return true -- Default to enabled if setting not found
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

-- Open GUI when player opens an agricultural-roboport or its ghost
script.on_event(defines.events.on_gui_opened, function(event)
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
        frame.add{
            type = "switch",
            name = "agricultural_roboport_mode_switch_" .. tostring(unit_key),
            switch_state = mode_to_switch_state(mode),
            left_label_caption = {"agricultural-roboport.mode-harvest"},
            right_label_caption = {"agricultural-roboport.mode-seed"},
            allow_none_state = true
        }
        frame.add{
            type = "checkbox",
            name = "agricultural_roboport_seed_logistic_only_" .. tostring(unit_key),
            state = seed_logistic_only,
            caption = {"agricultural-roboport.seed-logistic-only"}
        }
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
        local use_filter_checkbox = use_filter_row.add{
            type = "checkbox",
            name = "agricultural_roboport_use_filter_checkbox_" .. tostring(unit_key),
            state = settings.use_filter or false,
            caption = {"gui-inserter.use-filters"}
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
        local filters = settings.filters or {}
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
                                        write_file_log("[UI] Found seed from virtual entity ", entity_name, ": ", item_name)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        write_file_log("[UI] Total seeds added to filter: ", #seed_names)
        
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
                enabled = use_filter_checkbox.state,
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
        filters = update_filter_buttons_and_compress_filters(unit_key, filter_table, use_filter_checkbox.state, filters)
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
    end
end)

-- Remove GUI when closed
script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.get_player(event.player_index)
    if player.gui.relative.agricultural_roboport_mode then
        player.gui.relative.agricultural_roboport_mode.destroy()
    end
end)

-- Handle switch state change to set mode (support ghosts as well)
script.on_event(defines.events.on_gui_switch_state_changed, function(event)
    local element = event.element
    if not (element and element.valid) then return end
    -- Handle roboport mode switch
    -- When updating settings from UI, always update the table (never replace with nil or primitive)
    if element.name:find("^agricultural_roboport_mode_switch_") then
        local unit_key = element.name:match("^agricultural_roboport_mode_switch_(.+)$")
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
    elseif element.name:find("^agricultural_roboport_filter_invert_switch_") then
        local unit_key = element.name:match("^agricultural_roboport_filter_invert_switch_(.+)$")
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
                -- Find and rebuild filter table
                local frame = player.gui.relative.agricultural_roboport_mode
                local filter_flow = frame["agricultural_roboport_filter_flow_" .. tostring(unit_key)]
                if filter_flow then
                    local filter_outer = filter_flow["agricultural_roboport_filter_outer_flow_" .. tostring(unit_key)]
                    if filter_outer then
                        local filter_controls = filter_outer["agricultural_roboport_filter_controls_row_" .. tostring(unit_key)]
                        if filter_controls then
                            local filter_table = filter_controls["agricultural_roboport_filter_table_" .. tostring(unit_key)]
                            if filter_table then
                                -- Rebuild filter buttons with new elem_type
                                rebuild_filter_table(player, unit_key, filter_table, settings)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Handle radiobutton state change for 'Seed in logistic area only'
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local element = event.element
    if not (element and element.valid) then return end
    -- Handle 'Use filters' checkbox
    if element.name:find("^agricultural_roboport_use_filter_checkbox_") then
        local unit_key = element.name:match("^agricultural_roboport_use_filter_checkbox_(.+)$")
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
            -- Gray out or enable filter controls accordingly
            local parent = element.parent and element.parent.parent -- use_filter_row's parent is filter_outer_flow
            if parent then
                local controls_row = parent["agricultural_roboport_filter_controls_row_" .. tostring(unit_key)]
                if controls_row then
                    for _, child in pairs(controls_row.children) do
                        if child.type == "flow" then
                            for _, subchild in pairs(child.children) do
                                subchild.enabled = new_state
                            end
                        elseif child.type == "table" then
                            -- Use helper for button state and filter compression
                            local filters = settings.filters or {}
                            update_filter_buttons_and_compress_filters(unit_key, child, new_state, filters)
                        else
                            child.enabled = new_state
                        end
                    end
                end
            end
        end
    -- Handle 'Seed in logistic area only' checkbox
    elseif element.name:find("^agricultural_roboport_seed_logistic_only_") then
        local unit_key = element.name:match("^agricultural_roboport_seed_logistic_only_(.+)$")
        if unit_key then
            local num_key = tonumber(unit_key)
            if num_key then unit_key = num_key end
            if not storage.agricultural_roboports[unit_key] then
                storage.agricultural_roboports[unit_key] = {mode=0,seed_logistic_only=false,use_filter=false,filter_invert=false,filters=nil}
            end
            local settings = storage.agricultural_roboports[unit_key]
            settings.seed_logistic_only = element.state
        end
    end
end)

-- Handle filter choose-elem-button (both item and quality selectors)
script.on_event(defines.events.on_gui_elem_changed, function(event)
    local element = event.element
    if not (element and element.valid) then return end
    
    -- Handle combined item-with-quality selector OR simple item selector
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
                update_filter_buttons_and_compress_filters(unit_key, filter_table, settings.use_filter == true, new_filters)
                if quality_enabled and type(element.elem_value) == "table" then
                    write_file_log("[UI] Selected filter for key=", tostring(unit_key), "index=", tostring(idx), "value=", tostring(element.elem_value and (element.elem_value.name .. "@" .. element.elem_value.quality) or "nil"))
                else
                    write_file_log("[UI] Selected filter for key=", tostring(unit_key), "index=", tostring(idx), "value=", tostring(element.elem_value or "nil"))
                end
            end
        end
    end
end)

-- Handle quality dropdown selection changes
-- Deferred elem_value setter for choose-elem-buttons
script.on_event(defines.events.on_tick, function(event)
    if not _G._agroport_deferred_elem then return end
    for player_index, btns in pairs(_G._agroport_deferred_elem) do
        for _, entry in pairs(btns) do
            if entry.button and entry.button.valid then
                entry.button.elem_value = entry.value
            end
        end
        _G._agroport_deferred_elem[player_index] = nil
    end
end)

-- Helper: rebuild filter table when switching between whitelist/blacklist modes
function rebuild_filter_table(player, unit_key, old_filter_table, settings)
    local parent = old_filter_table.parent
    local filters = settings.filters or {}
    
    -- Build seed names list
    local prototypes = rawget(_G, 'prototypes')
    local seed_names = {}
    if prototypes and prototypes.entity then
        for entity_name, entity_proto in pairs(prototypes.entity) do
            if type(entity_name) == "string" and entity_name:match("^virtual%-.*%-seed$") then
                local items_to_place = entity_proto.items_to_place_this
                if items_to_place and #items_to_place > 0 then
                    for _, item_to_place in ipairs(items_to_place) do
                        local item_name = item_to_place.name
                        if prototypes.item and prototypes.item[item_name] and prototypes.item[item_name].plant_result then
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
            enabled = settings.use_filter or false,
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
    update_filter_buttons_and_compress_filters(unit_key, filter_table, settings.use_filter or false, filters)
end

-- Helper: update filter buttons and compress filters with quality support
function update_filter_buttons_and_compress_filters(unit_key, filter_table, use_filter_enabled, filters)
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
    
    -- Enable/disable filter slots based on use_filter and slot status
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
            if use_filter_enabled then
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
    return compressed_filters
end

return UI
