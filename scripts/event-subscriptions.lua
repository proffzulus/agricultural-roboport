-- Centralized event subscription management for agricultural-roboport mod
-- All script.on_event registrations go here to avoid conflicts

local event_subscriptions = {}

function event_subscriptions.register_all(handlers)
    -- Runtime mod settings changed
    script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
        if handlers.tdm and handlers.tdm.on_runtime_mod_setting_changed then
            handlers.tdm.on_runtime_mod_setting_changed(event)
        end
    end)

    -- Entity built events
    script.on_event(defines.events.script_raised_built, function(event)
        if handlers.roboport and handlers.roboport.on_script_raised_built then
            handlers.roboport.on_script_raised_built(event)
        end
    end)

    script.on_event(defines.events.on_built_entity, function(event)
        if handlers.roboport and handlers.roboport.on_built_entity then
            handlers.roboport.on_built_entity(event)
        end
    end, {{filter = "name", mode="or", name = "entity-ghost"}, {filter = "name", mode="or", name = "agricultural-roboport"}, {filter="type", mode="or", type="plant"}})

    script.on_event(defines.events.on_robot_built_entity, function(event)
        if handlers.roboport and handlers.roboport.on_robot_built_entity then
            handlers.roboport.on_robot_built_entity(event)
        end
    end)

    -- Entity removed events (combined dispatch)
    script.on_event({defines.events.on_entity_died, defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity}, function(event)
        if handlers.roboport and handlers.roboport.on_entity_removed then
            handlers.roboport.on_entity_removed(event)
        end
    end)

    -- Settings and blueprint events
    script.on_event(defines.events.on_entity_settings_pasted, function(event)
        if handlers.roboport and handlers.roboport.on_entity_settings_pasted then
            handlers.roboport.on_entity_settings_pasted(event)
        end
    end)

    script.on_event(defines.events.on_player_setup_blueprint, function(event)
        if handlers.roboport and handlers.roboport.on_player_setup_blueprint then
            handlers.roboport.on_player_setup_blueprint(event)
        end
    end)

    -- Tower planting/mining events
    script.on_event(defines.events.on_tower_planted_seed, function(event)
        if handlers.roboport and handlers.roboport.on_tower_planted_seed then
            handlers.roboport.on_tower_planted_seed(event)
        end
    end)

    script.on_event(defines.events.on_tower_mined_plant, function(event)
        if handlers.roboport and handlers.roboport.on_tower_mined_plant then
            handlers.roboport.on_tower_mined_plant(event)
        end
    end)

    -- Selection tool events (vegetation planner)
    script.on_event(defines.events.on_player_selected_area, function(event)
        if handlers.vegetation_planner and handlers.vegetation_planner.on_player_selected_area then
            handlers.vegetation_planner.on_player_selected_area(event)
        end
    end)

    script.on_event(defines.events.on_player_alt_selected_area, function(event)
        if handlers.vegetation_planner and handlers.vegetation_planner.on_player_alt_selected_area then
            handlers.vegetation_planner.on_player_alt_selected_area(event)
        end
    end)

    -- Cursor stack changed (vegetation planner GUI)
    script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
        if handlers.ui and handlers.ui.on_player_cursor_stack_changed then
            handlers.ui.on_player_cursor_stack_changed(event)
        end
    end)

    -- Shortcut clicked (vegetation planner toggle)
    script.on_event(defines.events.on_lua_shortcut, function(event)
        if handlers.ui and handlers.ui.on_lua_shortcut then
            handlers.ui.on_lua_shortcut(event)
        end
    end)

    -- GUI events (both roboport UI and vegetation planner UI)
    script.on_event(defines.events.on_gui_opened, function(event)
        if handlers.ui and handlers.ui.on_gui_opened then
            handlers.ui.on_gui_opened(event)
        end
    end)

    script.on_event(defines.events.on_gui_closed, function(event)
        if handlers.ui and handlers.ui.on_gui_closed then
            handlers.ui.on_gui_closed(event)
        end
    end)

    script.on_event(defines.events.on_gui_switch_state_changed, function(event)
        if handlers.ui and handlers.ui.on_gui_switch_state_changed then
            handlers.ui.on_gui_switch_state_changed(event)
        end
    end)

    script.on_event(defines.events.on_gui_checked_state_changed, function(event)
        if handlers.ui and handlers.ui.on_gui_checked_state_changed then
            handlers.ui.on_gui_checked_state_changed(event)
        end
    end)

    script.on_event(defines.events.on_gui_elem_changed, function(event)
        if handlers.ui and handlers.ui.on_gui_elem_changed then
            handlers.ui.on_gui_elem_changed(event)
        end
    end)

    script.on_event(defines.events.on_gui_click, function(event)
        if handlers.ui and handlers.ui.on_gui_click then
            handlers.ui.on_gui_click(event)
        end
    end)

    script.on_event(defines.events.on_tick, function(event)
        if handlers.ui and handlers.ui.on_tick then
            handlers.ui.on_tick(event)
        end
    end)
end

return event_subscriptions
