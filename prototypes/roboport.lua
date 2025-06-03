-- Apply green tint to all icons and graphics for entity
local green_tint = {r = 0.7, g = 1, b = 0.6, a = 1}

local agricultural_roboport_entity =  table.deepcopy(data.raw["roboport"]["roboport"])
agricultural_roboport_entity.name = "agricultural-roboport"
agricultural_roboport_entity.localised_name = {"agricultural-roboport.name"}
agricultural_roboport_entity.minable = {mining_time = 0.1, result = "agricultural-roboport"}
agricultural_roboport_entity.icons = {
	{
	icon = agricultural_roboport_entity.icon,
	icon_size = agricultural_roboport_entity.icon_size,
	tint = green_tint
	}
}
agricultural_roboport_entity.filter_count = 5

local agricultural_roboport_item = table.deepcopy(data.raw["item"]["roboport"])
agricultural_roboport_item.name = "agricultural-roboport"
agricultural_roboport_item.place_result = "agricultural-roboport"
local agricultural_roboport_recipe = {
	type = "recipe",
	name = "agricultural-roboport",
	localised_name = {"agricultural-roboport.name"},
	enabled = true,
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
	icon = data.raw.technology["construction-robotics"].icon,
	icon_size = data.raw.technology["construction-robotics"].icon_size,
	icon_mipmaps = data.raw.technology["construction-robotics"].icon_mipmaps,
	icons = {
		{
			icon = data.raw.technology["construction-robotics"].icon,
			icon_size = data.raw.technology["construction-robotics"].icon_size,
			tint = green_tint
		}
	},
	effects = {
		{
			type = "unlock-recipe",
			recipe = "agricultural-roboport"
		}
	},
	prerequisites ={"construction-robotics", "agriculture"},
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



-- Entity icons
if agricultural_roboport_entity.icons then
    for _, icon in ipairs(agricultural_roboport_entity.icons) do
        icon.tint = green_tint
    end
end
if agricultural_roboport_entity.icon then
    agricultural_roboport_entity.icon = nil -- use icons only
end
if agricultural_roboport_entity.icon_mipmaps then
    agricultural_roboport_entity.icon_mipmaps = nil
end

-- Entity graphics (base, door, etc.)
local function tint_layers(layers)
    if not layers then return end
    for _, layer in ipairs(layers) do
        if layer.filename or layer.filenames then
            layer.tint = green_tint
            if layer.hr_version then
                layer.hr_version.tint = green_tint
            end
        end
    end
end
if agricultural_roboport_entity.base then tint_layers(agricultural_roboport_entity.base.layers or {agricultural_roboport_entity.base}) end
if agricultural_roboport_entity.base_patch then tint_layers(agricultural_roboport_entity.base_patch.layers or {agricultural_roboport_entity.base_patch}) end
if agricultural_roboport_entity.door_animation_up then tint_layers(agricultural_roboport_entity.door_animation_up.layers or {agricultural_roboport_entity.door_animation_up}) end
if agricultural_roboport_entity.door_animation_down then tint_layers(agricultural_roboport_entity.door_animation_down.layers or {agricultural_roboport_entity.door_animation_down}) end
if agricultural_roboport_entity.base_animation then tint_layers(agricultural_roboport_entity.base_animation.layers or {agricultural_roboport_entity.base_animation}) end
if agricultural_roboport_entity.charge_approach_animation then tint_layers(agricultural_roboport_entity.charge_approach_animation.layers or {agricultural_roboport_entity.charge_approach_animation}) end
if agricultural_roboport_entity.circuit_connector_sprites then
    for _, sprite in pairs(agricultural_roboport_entity.circuit_connector_sprites) do
        if sprite and (sprite.filename or sprite.filenames) then
            sprite.tint = green_tint
            if sprite.hr_version then sprite.hr_version.tint = green_tint end
        end
    end
end

-- Item icons (set both icon and icons, do not remove icon)
if agricultural_roboport_item.icon then
    agricultural_roboport_item.icons = {
        {
            icon = agricultural_roboport_item.icon,
            icon_size = agricultural_roboport_item.icon_size,
            tint = green_tint
        }
    }
    -- Keep icon property for compatibility
end
if agricultural_roboport_item.icon_mipmaps then
    agricultural_roboport_item.icon_mipmaps = nil
end

-- Technology icon (leave as is, already custom)