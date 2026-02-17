-- Technology definitions for Controlled Mutations
-- Dynamic generation based on available quality tiers
-- Progression: 20% improvement chance per level
--
-- NOTE: This file is loaded in data-final-fixes.lua to ensure compatibility with mods
-- that modify or remove quality unlock technologies (e.g., ic-more-qualities)

-- Check if quality feature is available (both mod and setting)
local function is_quality_available()
    return mods["quality"] 
        and settings.startup["agricultural-roboport-enable-quality"] 
        and settings.startup["agricultural-roboport-enable-quality"].value
end

-- Early exit if quality is not available
if not is_quality_available() then
    log("Agricultural Roboport: Quality disabled - skipping controlled mutations tech tree")
    return
end

log("Agricultural Roboport: Generating dynamic controlled mutations tech tree")

-- Build sorted quality map from prototypes (excluding normal quality at level 0)
local qualities = {}
if data.raw["quality"] then
    for name, quality_proto in pairs(data.raw["quality"]) do
        if quality_proto.level and quality_proto.level > 0 then
            table.insert(qualities, {
                name = name,
                level = quality_proto.level
            })
        end
    end
end

-- Sort by level
table.sort(qualities, function(a, b) return a.level < b.level end)

if #qualities == 0 then
    log("Agricultural Roboport: No quality tiers found - skipping controlled mutations tech tree")
    return
end

log("Agricultural Roboport: Found " .. #qualities .. " quality tiers")

-- Build map of which technology unlocks each quality tier
local quality_unlock_tech = {}
if data.raw["technology"] then
    for tech_name, tech_proto in pairs(data.raw["technology"]) do
        if tech_proto.effects then
            for _, effect in pairs(tech_proto.effects) do
                if effect.type == "unlock-quality" and effect.quality then
                    quality_unlock_tech[effect.quality] = tech_name
                    log("Agricultural Roboport: Quality '" .. effect.quality .. "' unlocked by tech '" .. tech_name .. "'")
                end
            end
        end
    end
end

-- Generate N+4 tech levels (where N = number of quality tiers)
-- This ensures 80% improvement chance past the highest quality tier
local num_quality_tiers = #qualities
local num_tech_levels = num_quality_tiers + 4
local technologies = {}

log("Agricultural Roboport: Generating " .. num_tech_levels .. " controlled mutations tech levels")

-- Helper to get prerequisites for a given tech level
local function get_prerequisites(level)
    local prereqs = {}
    
    if level == 1 then
        -- First tech requires soil analysis and the tech that unlocks first quality tier
        table.insert(prereqs, "agricultural-soil-analysis")
        local first_quality_name = qualities[1].name
        local unlock_tech = quality_unlock_tech[first_quality_name]
        if unlock_tech and data.raw["technology"][unlock_tech] then
            table.insert(prereqs, unlock_tech)
            log("Agricultural Roboport: Tech level 1 requires unlock tech '" .. unlock_tech .. "'")
        else
            log("Agricultural Roboport: WARNING - No unlock tech found for quality '" .. first_quality_name .. "', using only soil-analysis")
        end
    else
        -- Subsequent techs require previous controlled mutations tech
        table.insert(prereqs, "agricultural-controlled-mutations-" .. (level - 1))
        
        -- Add quality unlock tech as prerequisite at appropriate levels
        -- Tech level L requires quality tier min(L, N) to be unlocked
        local quality_index = math.min(level, num_quality_tiers)
        if quality_index > 1 and quality_index <= #qualities then
            local quality_name = qualities[quality_index].name
            local unlock_tech = quality_unlock_tech[quality_name]
            if unlock_tech and data.raw["technology"][unlock_tech] then
                -- Check if this unlock tech isn't already a prerequisite from previous level
                local already_required = false
                if level > 2 and quality_index == math.min(level - 1, num_quality_tiers) then
                    already_required = true
                end
                if not already_required then
                    table.insert(prereqs, unlock_tech)
                    log("Agricultural Roboport: Tech level " .. level .. " requires unlock tech '" .. unlock_tech .. "'")
                end
            end
        end
        
        -- Add promethium prerequisite for very late techs (intentional special case)
        if level == num_quality_tiers + 2 and data.raw["technology"]["promethium-science-pack"] then
            table.insert(prereqs, "promethium-science-pack")
        end
    end
    
    return prereqs
end

-- Helper to collect science packs from specific technologies (union of packs)
-- Checks both data.raw and a temporary table of techs being created
local function collect_science_packs_from_techs(tech_names, exclude_list, temp_techs)
    local pack_set = {}
    local pack_list = {}
    
    exclude_list = exclude_list or {}
    local exclude_set = {}
    for _, name in ipairs(exclude_list) do
        exclude_set[name] = true
    end
    
    temp_techs = temp_techs or {}
    
    for _, tech_name in ipairs(tech_names) do
        if not exclude_set[tech_name] then
            -- Check temp_techs first (for controlled-mutations being created in this pass)
            local tech = temp_techs[tech_name] or data.raw["technology"][tech_name]
            if tech and tech.unit and tech.unit.ingredients then
                for _, ingredient in ipairs(tech.unit.ingredients) do
                    local pack_name = type(ingredient) == "table" and ingredient[1] or ingredient
                    if pack_name and not pack_set[pack_name] then
                        pack_set[pack_name] = true
                        table.insert(pack_list, {pack_name, 1})
                    end
                end
            end
        end
    end
    
    -- If no packs found, use basic packs as fallback
    if #pack_list == 0 then
        return {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1},
            {"chemical-science-pack", 1}
        }
    end
    
    return pack_list
end

-- Helper to get science pack ingredients based on level
-- Science packs are the union of:
-- 1. Quality unlock tech for this level (if any)
-- 2. Previous controlled-mutations tech (if any)
-- 3. Promethium-science-pack if it's a prerequisite
-- Explicitly excludes agricultural-soil-analysis to avoid wood science from Lignumis
local function get_science_packs(level, prereqs, temp_techs)
    local techs_to_inherit_from = {}
    local has_promethium_prereq = false
    
    -- Collect science packs from quality unlock tech and previous level
    for _, prereq_name in ipairs(prereqs) do
        -- Track if we have promethium prerequisite
        if prereq_name == "promethium-science-pack" then
            has_promethium_prereq = true
        end
        
        -- Include quality unlock techs and previous controlled-mutations
        if prereq_name:match("^agricultural%-controlled%-mutations%-") or 
           prereq_name:match("quality") then
            table.insert(techs_to_inherit_from, prereq_name)
        end
    end
    
    -- Exclude agricultural-soil-analysis to avoid Lignumis wood science
    local packs = collect_science_packs_from_techs(techs_to_inherit_from, {"agricultural-soil-analysis"}, temp_techs)
    
    -- If we have promethium prerequisite, manually add promethium-science-pack
    -- (The promethium-science-pack tech itself doesn't require promethium in its ingredients)
    if has_promethium_prereq and data.raw["tool"]["promethium-science-pack"] then
        local has_pack = false
        for _, pack in ipairs(packs) do
            if pack[1] == "promethium-science-pack" then
                has_pack = true
                break
            end
        end
        if not has_pack then
            table.insert(packs, {"promethium-science-pack", 1})
        end
    end
    
    log("Agricultural Roboport: Tech level " .. level .. " inheriting " .. #packs .. " science pack types from: " .. table.concat(techs_to_inherit_from, ", "))
    
    return packs
end

-- Helper to get research count based on level
local function get_research_count(level)
    if level <= num_quality_tiers then
        return 50
    elseif level == num_quality_tiers + 1 then
        return 100
    elseif level == num_quality_tiers + 2 then
        return 2500
    elseif level == num_quality_tiers + 3 then
        return 5000
    else
        return 15000
    end
end

-- Helper to get order string (supports up to 26 levels: a-z)
local function get_order(level)
    local letter = string.char(96 + level) -- 'a' = 97, so 96 + 1 = 'a'
    return "e-a-" .. letter
end

-- Generate all technology levels
local temp_techs = {} -- Track techs being created so we can reference them before data:extend
for level = 1, num_tech_levels do
    local prereqs = get_prerequisites(level)
    local tech = {
        type = "technology",
        name = "agricultural-controlled-mutations-" .. level,
        icon = "__agricultural-roboport__/graphics/controlled_mutations.png",
        icon_size = 256,
        effects = {
            {
                type = "change-recipe-productivity",
                recipe = "agricultural-mutation-chance",
                change = 0.20  -- Each level adds 20% improvement chance
            }
        },
        prerequisites = prereqs,
        unit = {
            count = get_research_count(level),
            ingredients = get_science_packs(level, prereqs, temp_techs),
            time = 30
        },
        order = get_order(level)
    }
    
    table.insert(technologies, tech)
    temp_techs[tech.name] = tech -- Store for reference by later levels
    log("Agricultural Roboport: Created tech level " .. level .. " with " .. #tech.prerequisites .. " prerequisites and " .. #tech.unit.ingredients .. " science packs")
end

data:extend(technologies)
log("Agricultural Roboport: Successfully generated " .. #technologies .. " controlled mutations technologies")
