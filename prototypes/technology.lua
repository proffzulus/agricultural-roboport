-- Technology definitions for Controlled Mutations
-- Progression: 20% improvement chance per level (0.20, 0.40, 0.60, 0.80, 1.00)

local technologies = {}

-- Helper to create science pack ingredients matching quality prerequisites
local function get_quality_science_packs(level)
    local packs = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
    }
    
    -- Level 3+: add production and utility science
    if level >= 3 then
		table.insert(packs, {"production-science-pack", 1})
        table.insert(packs, {"utility-science-pack", 1})
		table.insert(packs, {"agricultural-science-pack", 1})
    end
    
    -- Level 4+: legendary quality prerequisite
    if level >= 4 then
        table.insert(packs, {"space-science-pack", 1})
    end
    if level > 5 then
		table.insert(packs, {"promethium-science-pack", 1})
    end
    return packs
end

-- Level 1: 20% improvement chance
-- Prerequisites: agricultural-soil-analysis + quality-module
table.insert(technologies, {
    type = "technology",
    name = "agricultural-controlled-mutations-1",
    icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
    icon_size = 256,
    effects = {
        {
            type = "nothing",
            effect_description = {"agricultural-roboport.controlled-mutation-effect-1"}
        }
    },
    prerequisites = {"agricultural-soil-analysis", "quality-module"},
    unit = {
        count = 50,
        ingredients = get_quality_science_packs(1),
        time = 30
    },
    order = "e-a-a"
})

-- Level 2: 40% improvement chance
table.insert(technologies, {
    type = "technology",
    name = "agricultural-controlled-mutations-2",
    icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
    icon_size = 256,
    effects = {
        {
            type = "nothing",
            effect_description = {"agricultural-roboport.controlled-mutation-effect-2"}
        }
    },
    prerequisites = {"agricultural-controlled-mutations-1"},
    unit = {
        count = 50,
        ingredients = get_quality_science_packs(2),
        time = 30
    },
    order = "e-a-b"
})

-- Level 3: 60% improvement chance
-- Prerequisites: epic-quality + controlled-mutations-2
table.insert(technologies, {
    type = "technology",
    name = "agricultural-controlled-mutations-3",
    icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
    icon_size = 256,
    effects = {
        {
            type = "nothing",
            effect_description = {"agricultural-roboport.controlled-mutation-effect-3"}
        }
    },
    prerequisites = {"epic-quality", "agricultural-controlled-mutations-2", "production-science-pack"},
    unit = {
        count = 50,
        ingredients = get_quality_science_packs(3),
        time = 30
    },
    order = "e-a-c"
})

-- Level 4: 80% improvement chance
-- Prerequisites: legendary-quality + controlled-mutations-3
table.insert(technologies, {
    type = "technology",
    name = "agricultural-controlled-mutations-4",
    icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
    icon_size = 256,
    effects = {
        {
            type = "nothing",
            effect_description = {"agricultural-roboport.controlled-mutation-effect-4"}
        }
    },
    prerequisites = {"legendary-quality", "agricultural-controlled-mutations-3"},
    unit = {
        count = 50,
        ingredients = get_quality_science_packs(4),
        time = 30
    },
    order = "e-a-d"
})

-- Level 5: 100% improvement chance
table.insert(technologies, {
    type = "technology",
    name = "agricultural-controlled-mutations-5",
    icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
    icon_size = 256,
    effects = {
        {
            type = "nothing",
            effect_description = {"agricultural-roboport.controlled-mutation-effect-5"}
        }
    },
    prerequisites = {"agricultural-controlled-mutations-4"},
    unit = {
        count = 50,
        ingredients = get_quality_science_packs(5),
        time = 30
    },
    order = "e-a-e"
})

-- Level 6: 120% improvement chance
table.insert(technologies, {
	type = "technology",
	name = "agricultural-controlled-mutations-6",
	icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
	icon_size = 256,
	effects = {
		{
			type = "nothing",
			effect_description = {"agricultural-roboport.controlled-mutation-effect-6"}
		}
	},
	prerequisites = {"agricultural-controlled-mutations-5", "promethium-science-pack"},
	unit = {
		count = 2500,
		ingredients = get_quality_science_packs(6),
		time = 30
	},
	order = "e-a-f"
})

-- Level 7: 140% improvement chance
table.insert(technologies, {
	type = "technology",
	name = "agricultural-controlled-mutations-7",
	icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
	icon_size = 256,
	effects = {
		{
			type = "nothing",
			effect_description = {"agricultural-roboport.controlled-mutation-effect-7"}
		}
	},
	prerequisites = {"agricultural-controlled-mutations-6"},
	unit = {
		count = 5000,
		ingredients = get_quality_science_packs(7),
		time = 30
	},
	order = "e-a-g"
})

-- Level 8: 160% improvement chance
table.insert(technologies, {
	type = "technology",
	name = "agricultural-controlled-mutations-8",
	icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
	icon_size = 256,
	effects = {
		{
			type = "nothing",
			effect_description = {"agricultural-roboport.controlled-mutation-effect-8"}
		}
	},
	prerequisites = {"agricultural-controlled-mutations-7"},
	unit = {
		count = 15000,
		ingredients = get_quality_science_packs(8),
		time = 30
	},
	order = "e-a-h"
})

data:extend(technologies)
