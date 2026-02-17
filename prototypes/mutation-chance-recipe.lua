-- Phantom recipe used purely for displaying mutation chance bonus in technology effects
-- This recipe cannot actually be crafted anywhere

-- Create a crafting category that no machine will ever have
data:extend({
    {
        type = "recipe-category",
        name = "agricultural-mutation-phantom"
    }
})

-- Create the phantom recipe
data:extend({
    {
        type = "recipe",
        name = "agricultural-mutation-chance",
        category = "agricultural-mutation-phantom",
        enabled = false,
        hidden = true,
        energy_required = 1,
        ingredients = {},
        results = {},
        icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
        icon_size = 256
    }
})
