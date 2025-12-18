-- Vegetation Planner - selection tool for manual seeding

-- Technology: Soil Analysis (very early, 10 red science)
data:extend({
    {
        type = "technology",
        name = "agricultural-soil-analysis",
        icon = "__agricultural-roboport__/graphics/soil-analysis.png",
        icon_size = 256,
        effects = {
			{
				type = "nothing",
				effect_description = {"shortcut-name.vegetation-planner"},
				icon = "__agricultural-roboport__/graphics/vegetation_planner.png",
				icon_size = 64
			}
		},
        unit = {
            count = 10,
            ingredients = {{"automation-science-pack", 1}},
            time = 5
        },
        order = "c-a-a-a" -- Very early placement
    }
})

-- Item: Selection tool (spawnable only, not craftable)
data:extend({
    {
        type = "selection-tool",
        name = "vegetation-planner",
        icon = "__agricultural-roboport__/graphics/vegetation_planner.png",
        icon_size = 64,
        stack_size = 1,
        flags = {"spawnable", "only-in-cursor", "not-stackable"},
        subgroup = "tool",
        order = "c[automated-construction]-e[vegetation-planner]",
        
        -- Normal selection: place seed ghosts (green box)
        select = {
            border_color = {r = 0.2, g = 0.8, b = 0.2},
            mode = {"any-tile"},
            cursor_box_type = "copy"
        },
        
        -- Alt selection: clear vegetation ghosts (red box)
        alt_select = {
            border_color = {r = 0.8, g = 0.2, b = 0.2},
            mode = {"any-tile"},
            cursor_box_type = "not-allowed"
        },
        
        -- Allow selection anywhere
        always_include_tiles = true
    }
})

-- Shortcut
data:extend({
    {
        type = "shortcut",
        name = "vegetation-planner",
        action = "lua",
        icon = "__agricultural-roboport__/graphics/vegetation_planner.png",
        icon_size = 64,
        small_icon = "__agricultural-roboport__/graphics/vegetation_planner.png",
        small_icon_size = 64,
        technology_to_unlock = "agricultural-soil-analysis",
		unavailable_until_unlocked = true,
		associated_control_input = "vegetation-planner",
		toggleable = true,
        order = "c[automated-construction]-e[vegetation-planner]"
    }
})

-- Custom input for shortcut keybind
data:extend({
    {
        type = "custom-input",
        name = "vegetation-planner",
        key_sequence = "ALT + V",
        action = "spawn-item",
        item_to_spawn = "vegetation-planner"
    }
})
