-- Load prototypes at the correct stage in the data lifecycle
require("prototypes.roboport")
require("prototypes.vegetation-planner")
require("prototypes.mutation-chance-recipe")

-- Note: Controlled mutations tech tree is loaded in data-final-fixes.lua
-- to ensure compatibility with mods that modify quality unlock technologies
