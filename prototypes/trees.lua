local util = require('util')

local virtual_seeds = {}

-- Check if dense seeding mode is enabled
local dense_mode = settings.startup["agricultural-roboport-dense-seeding"] and settings.startup["agricultural-roboport-dense-seeding"].value or false

-- Scan ALL data.raw prototype types for items with plant_result
-- No category filtering - any item type with plant_result is a seed
log("[Agricultural Roboport] Scanning all data.raw prototypes for items with plant_result...")
log("[Agricultural Roboport] Dense seeding mode: " .. tostring(dense_mode))

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
                base.hidden_in_factoriopedia = true
                
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
                
                -- In dense mode, use actual plant collision boxes; otherwise use default 3x3
                if dense_mode then
                    -- Get the plant entity to copy its collision boxes
                    local plant_name = item_proto.plant_result
                    local plant_proto = nil
                    
                    -- Search for plant entity in data.raw
                    for entity_type, entities in pairs(data.raw) do
                        if entities[plant_name] then
                            plant_proto = entities[plant_name]
                            break
                        end
                    end
                    
                    if plant_proto then
                        -- For dense mode, use actual collision_box (red box) from the plant
                        -- This is what the game uses for placement validation
                        local coll_box = plant_proto.collision_box or {{-0.4, -0.4}, {0.4, 0.4}}
                        
                        base.collision_box = coll_box
                        base.map_generator_bounding_box = coll_box
                        base.selection_box = coll_box  -- Use same as collision for consistency
                        
                        -- Calculate tile dimensions from collision box
                        base.tile_width = math.max(1, math.ceil(coll_box[2][1] - coll_box[1][1]))
                        base.tile_height = math.max(1, math.ceil(coll_box[2][2] - coll_box[1][2]))
                        
                        -- Copy collision_mask from plant to match its collision behavior exactly
                        if plant_proto.collision_mask then
                            base.collision_mask = util.table.deepcopy(plant_proto.collision_mask)
                            log("[Agricultural Roboport] Dense mode: Copied collision_mask from plant for " .. virtual_name)
                        end
                        
                        -- Enable placeable-off-grid for dense packing
                        base.flags = base.flags or {}
                        table.insert(base.flags, "placeable-off-grid")
                        
                        log("[Agricultural Roboport] Dense mode: Using plant collision_box for " .. virtual_name .. " size: " .. base.tile_width .. "x" .. base.tile_height)
                    else
                        -- Fallback to small default if plant not found
                        base.tile_width = 1
                        base.tile_height = 1
                        base.collision_box = {{-0.4, -0.4}, {0.4, 0.4}}
                        base.map_generator_bounding_box = {{-0.4, -0.4}, {0.4, 0.4}}
                        base.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
                        log("[Agricultural Roboport] Dense mode: Plant not found, using small default for " .. virtual_name)
                    end
                else
                    -- Default 3x3 mode
                    base.tile_width = 3
                    base.tile_height = 3
                    base.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}
                    base.map_generator_bounding_box = {{-0.9, -0.9}, {0.9, 0.9}}
                    base.selection_box = {{-0.9, -0.9}, {0.9, 0.9}}
                end
                
                base.minable = {mining_time = 0.1, result = nil}
                base.inventory_size = 0
                -- Set default collision_mask only if not already set in dense mode
                if not base.collision_mask then
                    base.collision_mask = {layers={object=true, train=true, is_object=true, is_lower_object=true}}
                end
                
                table.insert(virtual_seeds, base)
                seed_count = seed_count + 1
                
                log("[Agricultural Roboport] Created virtual seed: " .. virtual_name .. " for plant: " .. tostring(item_proto.plant_result) .. " (placeable_by: " .. item_name .. ")")
            end
        end
    end
end

log("[Agricultural Roboport] Prototype scan complete: " .. seed_count .. " virtual seeds created, " .. skipped_count .. " items skipped")
if seed_count == 0 then
	log("[Agricultural Roboport] WARNING: No virtual seeds were created! Check if there are any items with plant_result in the prototypes.")
else
	data:extend(virtual_seeds)
end