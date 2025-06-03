local util = require('util')

local virtual_seeds = {}
local static_picture = {
    layers = {
        {
            filename = "__base__/graphics/entity/tree/08/tree-08-a-trunk.png",
            priority = "extra-high",
            width = 210,
            height = 286,
            scale = 0.3,
            shift = util.by_pixel(-5, -38),
        }
    }
}

for seed_name, seed_item in pairs(data.raw.item or {}) do
    if seed_name:match("%-seed$") then
        local base = util.table.deepcopy(data.raw["container"]["wooden-chest"])
        base.name = "virtual-" .. seed_name
        base.icon = seed_item.icon
        base.icon_size = seed_item.icon_size
        base.picture = static_picture
        base.placeable_by = {item = seed_name, count = 1}
        base.tile_width = 3
        base.tile_height = 3
        base.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}
        base.selection_box = {{-0.9, -0.9}, {0.9, 0.9}}
        base.minable = nil
        base.inventory_size = 0
        table.insert(virtual_seeds, base)
    end
end

data:extend(virtual_seeds)



