local agricultural_roboport_entity =  table.deepcopy(data.raw["roboport"]["roboport"])
agricultural_roboport_entity.name = "agricultural-roboport"
agricultural_roboport_entity.localised_name = {"agricultural-roboport.name"}
agricultural_roboport_entity.localised_description = {"agricultural-roboport.description"}
agricultural_roboport_entity.minable = {mining_time = 0.1, result = "agricultural-roboport"}
agricultural_roboport_entity.icon = "__agricultural-roboport__/graphics/roboport/roboport-icon.png"
agricultural_roboport_entity.filter_count = 5
agricultural_roboport_entity.flags = {"placeable-player", "player-creation", "get-by-unit-number"}
agricultural_roboport_entity.base.layers[1].filename = "__agricultural-roboport__/graphics/roboport/roboport-base.png"
agricultural_roboport_entity.base_patch.filename = "__agricultural-roboport__/graphics/roboport/roboport-base-patch.png"
agricultural_roboport_entity.door_animation_up.filename = "__agricultural-roboport__/graphics/roboport/roboport-door-up.png"
agricultural_roboport_entity.door_animation_down.filename = "__agricultural-roboport__/graphics/roboport/roboport-door-down.png"

local agricultural_roboport_item = table.deepcopy(data.raw["item"]["roboport"])
agricultural_roboport_item.name = "agricultural-roboport"
agricultural_roboport_item.place_result = "agricultural-roboport"
agricultural_roboport_item.icon = agricultural_roboport_entity.icon
agricultural_roboport_item.order = "c[signal]-b[agricultural-roboport]"

local agricultural_roboport_recipe = {
	type = "recipe",
	name = "agricultural-roboport",
	localised_name = {"agricultural-roboport.name"},
	enabled = false,
	energy_required = 10,
	ingredients = {
		{type = "item", name = "roboport", amount = 1},
		{type = "item", name = "agricultural-tower", amount = 1},
	},
	results = {
		{type = "item", name = "agricultural-roboport", amount = 1},
	},
}

local agricultural_roboport_technology = {
	type = "technology",
	name = "agricultural-roboport",
	localised_name = {"agricultural-roboport.technology"},
	localised_description = {"agricultural-roboport.technology-description"},
	icons = {{ icon = "__agricultural-roboport__/graphics/roboport/roboport-technology.png", icon_size = 256 }},
	effects = {
		{
			type = "unlock-recipe",
			recipe = "agricultural-roboport"
		}
	},
	prerequisites ={"construction-robotics", "agriculture", "agricultural-soil-analysis"},
	unit = {
		count = 200,
		ingredients = {
			{"automation-science-pack", 1},
			{"logistic-science-pack", 1},
			{"chemical-science-pack", 1},
			{"agricultural-science-pack", 1}
		},
		time = 30
	},
	order = "c-k-a"
}

data:extend{agricultural_roboport_entity, agricultural_roboport_item, agricultural_roboport_recipe, agricultural_roboport_technology}