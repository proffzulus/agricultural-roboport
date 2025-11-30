-- filepath: scripts/UI.lua
-- All GUI-related event handlers for agricultural-roboport mod

local UI = {}
local helpers = helpers or require('helpers')
local serpent = serpent or require('serpent')


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
                filters = nil,
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
        -- Add the filter table (choose-elem-buttons)
        local filter_table = filter_controls_row.add{
            type = "table",
            name = "agricultural_roboport_filter_table_" .. tostring(unit_key),
            column_count = 5
        }
        local filters = settings.filters or {}
        -- Only support item selection for now
        -- Use rawget(_G, 'prototypes') for prototype existence check (Factorio 2.0+)
        -- Prepare for deferred elem_value setting
        _G._agroport_deferred_elem = _G._agroport_deferred_elem or {}
        _G._agroport_deferred_elem[player.index] = {}
        -- Build a list of all item names ending with '-seed'
        local prototypes = rawget(_G, 'prototypes')
        local seed_names = {}
        if prototypes and prototypes.item then
            for name, proto in pairs(prototypes.item) do
                if type(name) == "string" and name:match("%-seed$") then
                    table.insert(seed_names, name)
                end
            end
        end
        for i = 1, 5 do
            local val = filters[i]
            local valid_prototype = false
            local proto = nil
            -- prototypes already defined above
            if type(val) == "string" and prototypes and prototypes.item then
                proto = prototypes.item[val]
                if proto then
                    valid_prototype = true
                end
            end
            local btn = filter_table.add{
                type = "choose-elem-button",
                name = "agricultural_roboport_filter_elem_" .. tostring(unit_key) .. "_" .. tostring(i),
                elem_type = "item",
                elem_filters = {
                    {filter = "name", name = seed_names}
                },
                enabled = use_filter_checkbox.state -- Only enable if use_filter is checked
            }
            -- Defer setting elem_value to next tick
            if valid_prototype then
                table.insert(_G._agroport_deferred_elem[player.index], {button=btn, value=val})
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

-- Handle filter choose-elem-button
script.on_event(defines.events.on_gui_elem_changed, function(event)
    local element = event.element
    if element and element.valid and element.name:find("^agricultural_roboport_filter_elem_") then
        local unit_key, idx = element.name:match("^agricultural_roboport_filter_elem_(.+)_(%d)$")
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
            if type(filters) == "table" and idx ~= nil then
                filters[idx] = element.elem_value
                -- Shift left if any value is erased (set to nil) and compress to start
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
                -- Update UI: re-disable/enable buttons as needed and update their values
                local player = game.get_player(event.player_index)
                if player and player.valid then
                    local filter_table = element.parent
                    update_filter_buttons_and_compress_filters(unit_key, filter_table, settings.use_filter == true, new_filters)
                    write_file_log("[UI] Selected filter for key=", tostring(unit_key), "index=", tostring(idx), "value=", tostring(element.elem_value))
                end
            end
        end
    end
end)

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

-- Helper: update filter buttons and compress filters (vanilla inserter logic)
function update_filter_buttons_and_compress_filters(unit_key, filter_table, use_filter_enabled, filters)
    -- Get all seed names from prototypes
    local prototypes = rawget(_G, 'prototypes')
    local all_seed_names = {}
    if prototypes and prototypes.item then
        for name, proto in pairs(prototypes.item) do
            if type(name) == "string" and name:match("%-seed$") then
                table.insert(all_seed_names, name)
            end
        end
    end
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
    -- Assign values and unique elem_filters to buttons
    for i = 1, 5 do
        local btn = filter_table["agricultural_roboport_filter_elem_" .. tostring(unit_key) .. "_" .. tostring(i)]
        if btn then
            btn.elem_value = compressed_filters[i]
            -- Build available seeds for this button: all seeds minus those selected in other slots
            local selected = {}
            for j = 1, 5 do
                if j ~= i and compressed_filters[j] then
                    selected[compressed_filters[j]] = true
                end
            end
            local available_seeds = {}
            for _, seed in ipairs(all_seed_names) do
                if not selected[seed] or seed == compressed_filters[i] then
                    table.insert(available_seeds, seed)
                end
            end
            btn.elem_filters = {{filter = "name", name = available_seeds}}
        end
    end
    -- Only the next empty button is enabled, all others are disabled except those with a value
    local first_empty = nil
    local filter_values = {}
    for i = 1, 5 do
        local val = compressed_filters[i]
        filter_values[i] = val
        if val == nil and not first_empty then
            first_empty = i
        end
    end
    local enabled_log = {}
    for i = 1, 5 do
        local btn = filter_table["agricultural_roboport_filter_elem_" .. tostring(unit_key) .. "_" .. tostring(i)]
        if btn then
            if use_filter_enabled then
                if filter_values[i] ~= nil or i == first_empty then
                    btn.enabled = true
                    enabled_log[i] = true
                else
                    btn.enabled = false
                    enabled_log[i] = false
                end
            else
                btn.enabled = false
                enabled_log[i] = false
            end
        end
    end
    -- Save compressed filters back to settings table
    local settings = storage.agricultural_roboports[unit_key]
    settings.filters = compressed_filters
    return compressed_filters
end

return UI
