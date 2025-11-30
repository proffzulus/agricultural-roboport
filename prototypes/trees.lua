local util = require('util')

local virtual_seeds = {}


for seed_name, seed_item in pairs(data.raw.item or {}) do
    if seed_name:match("%-seed$") then
		log("Creating virtual seed for " .. seed_name)
		if (not seed_item.plant_result) then
			log("Skipping " .. seed_name .. " because it has no plant_result")
			goto continue
		end
        local base = util.table.deepcopy(data.raw["container"]["wooden-chest"])
        base.name = "virtual-" .. seed_name
		base.localised_name = {"agricultural-roboport.request-for-planting"};
        base.icon = seed_item.icon or seed_item.icons[1].icon
        base.icon_size = seed_item.icon_size
        base.picture = {
            layers = {
                {
                    filename = "__core__/graphics/icons/item-to-be-delivered-symbol.png",
                    priority = "extra-high",
                    width = 64,
                    height = 92,
                    scale = 0.4,
                    shift = util.by_pixel(0, -10),
                },
                {
                    filename = seed_item.icon or seed_item.icons[1].icon,
                    priority = "extra-high",
                    width =  64,
                    height = 64,
                    scale = 0.2,
                    shift = util.by_pixel(0, -10),
                },
            }
        }
        base.placeable_by = {item = seed_name, count = 1}
        base.tile_width = 3
        base.tile_height = 3
        base.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}
        base.selection_box = {{-0.9, -0.9}, {0.9, 0.9}}
		base.minable = {mining_time = 0.1, result = nil}
        base.inventory_size = 0
		base.collision_mask = {layers={object=true, train=true, is_object=true, is_lower_object=true}}
        table.insert(virtual_seeds, base)
		log("Added virtual seed for plant " .. seed_item.plant_result .. " with entity name " .. base.name .. ", placeable_by item " .. seed_name .. "")
    end
::continue::
end

data:extend(virtual_seeds)
