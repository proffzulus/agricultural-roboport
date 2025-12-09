local util = require('util')

local virtual_seeds = {}

-- Parse additional seeds from settings (comma-separated list)
local additional_seed_names = {}
if settings and settings.startup and settings.startup["agricultural-roboport-additional-seeds"] then
    local setting_value = settings.startup["agricultural-roboport-additional-seeds"].value
    if setting_value and setting_value ~= "" then
        for seed_name in string.gmatch(setting_value, "([^,]+)") do
            -- Trim whitespace
            seed_name = seed_name:match("^%s*(.-)%s*$")
            if seed_name ~= "" then
                additional_seed_names[seed_name] = true
                log("Added additional seed from settings: " .. seed_name)
            end
        end
    end
end

-- Collect all potential seed items from multiple entity types
-- We'll merge items from data.raw.item, data.raw.capsule, etc.
local all_seed_candidates = {}

-- Helper to safely add items from a data.raw category
local function collect_from_category(category_name)
    if data.raw[category_name] then
        for name, proto in pairs(data.raw[category_name]) do
            if type(name) == "string" and type(proto) == "table" then
                -- Only add if not already present (avoid duplicates)
                if not all_seed_candidates[name] then
                    all_seed_candidates[name] = proto
                end
            end
        end
    end
end

-- Collect from common categories that might contain seeds
collect_from_category("item")
collect_from_category("capsule")
collect_from_category("ammo")
collect_from_category("tool")

-- Now iterate over all collected candidates
for seed_name, seed_item in pairs(all_seed_candidates) do
    -- Check if it ends with "-seed" OR is in the additional seeds list
    local is_seed = seed_name:match("%-seed$") or additional_seed_names[seed_name]
    
    if is_seed then
		log("Creating virtual seed for " .. seed_name)
		if (not seed_item.plant_result) then
			log("Skipping " .. seed_name .. " because it has no plant_result")
			goto continue
		end
        local base = util.table.deepcopy(data.raw["container"]["wooden-chest"])
        -- For additional seeds, append "-seed" suffix to virtual entity name
        local virtual_name = seed_name:match("%-seed$") and ("virtual-" .. seed_name) or ("virtual-" .. seed_name .. "-seed")
        base.name = virtual_name
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
        base.placeable_by = {item = seed_name, count = 1, quality = "any"}
        base.tile_width = 3
        base.tile_height = 3
        base.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}
		base.map_generator_bounding_box = {{-0.9, -0.9}, {0.9, 0.9}}
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
