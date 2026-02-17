-- Load prototypes after all other mods have made their changes
-- This ensures compatibility with mods that modify quality systems

require("prototypes.trees")

-- Generate controlled mutations tech tree in final-fixes stage
-- This runs AFTER mods that remove/modify quality unlock technologies
require("prototypes.technology")
