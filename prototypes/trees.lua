local util = require('util')

local virtual_seeds = {}

-- Scan ALL data.raw prototype types for items with plant_result
-- No category filtering - any item type with plant_result is a seed
log("[Agricultural Roboport] Scanning all data.raw prototypes for items with plant_result...")

local seed_count = 0
local skipped_count = 0

-- Iterate through all prototype categories in data.raw
for category_name, category_prototypes in pairs(data.raw) do
    if type(category_prototypes) == "table" then
        for item_name, item_proto in pairs(category_prototypes) do
            -- Check if this item has a plant_result property
            if type(item_proto) == "table" and item_proto.plant_result then
                log("[Agricultural Roboport] Found seed candidate: " .. item_name .. " (category: " .. category_name .. ")")
                
                -- Determine virtual seed entity name
                -- Standard seeds (ending with "-seed"): virtual-{name}
                -- Non-standard seeds: virtual-{name}-seed
                local virtual_name = item_name:match("%-seed$") and ("virtual-" .. item_name) or ("virtual-" .. item_name .. "-seed")
                
                -- Create virtual seed entity based on wooden chest
                local base = util.table.deepcopy(data.raw["container"]["wooden-chest"])
                base.name = virtual_name
                base.localised_name = {"agricultural-roboport.request-for-planting"}
                
                -- Set icon from seed item
                base.icon = item_proto.icon or (item_proto.icons and item_proto.icons[1] and item_proto.icons[1].icon)
                base.icon_size = item_proto.icon_size
                
                -- Create visual appearance
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
                            filename = base.icon,
                            priority = "extra-high",
                            width = 64,
                            height = 64,
                            scale = 0.2,
                            shift = util.by_pixel(0, -10),
                        },
                    }
                }
                
                -- Configure placement and collision
                base.placeable_by = {item = item_name, count = 1, quality = "any"}
                base.tile_width = 3
                base.tile_height = 3
                base.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}
                base.map_generator_bounding_box = {{-0.9, -0.9}, {0.9, 0.9}}
                base.selection_box = {{-0.9, -0.9}, {0.9, 0.9}}
                base.minable = {mining_time = 0.1, result = nil}
                base.inventory_size = 0
                base.collision_mask = {layers={object=true, train=true, is_object=true, is_lower_object=true}}
                
                table.insert(virtual_seeds, base)
                seed_count = seed_count + 1
                
                log("[Agricultural Roboport] Created virtual seed: " .. virtual_name .. " for plant: " .. tostring(item_proto.plant_result) .. " (placeable_by: " .. item_name .. ")")
            end
        end
    end
end

log("[Agricultural Roboport] Prototype scan complete: " .. seed_count .. " virtual seeds created, " .. skipped_count .. " items skipped")

data:extend(virtual_seeds)
