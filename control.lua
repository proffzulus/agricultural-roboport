-- this part is used to surpress lint errors. These objects do exist in the game environment, but they are not defined in the script.
storage = storage or {}
serpent = serpent or {}
-- Do not assign `game`, `defines` or `settings` here — assigning
-- them to empty tables can overwrite the real Factorio globals at runtime
-- and cause errors (e.g. `game.write_file` missing). Leave them alone so
-- the engine-provided globals are used when available.

-- Import refactored modules
local util = require("scripts.util")
local tdm = require("scripts.tdm")
local UI = require("scripts.UI")
local tile_buildability = require("scripts.tile_buildability")
local vegetation_planner = require("scripts.vegetation-planner")
local event_subscriptions = require("scripts.event-subscriptions")
require("scripts.agricultural-roboport")
require("debug-commands")

-- Module-level flag for deferred rebuild (cannot use storage in on_load)
local rebuild_on_next_tick = false

-- Make write_file_log global for all modules to use
function write_file_log(...)
    return util.write_file_log(...)
end

-- Quality order and helpers
-- Quality system tables (built dynamically at runtime from prototypes.quality)
-- Stored in storage state to support mods that modify quality tiers
local function build_quality_tables()
    if not is_quality_enabled() then
        -- Quality disabled - set empty tables
        storage.quality_by_level = {}
        storage.quality_level = {}
        storage.max_quality_level = 0
        storage.quality_tables_version = 2  -- Track table format version
        log("Agricultural Roboport: Quality disabled - skipping quality table initialization")
        return
    end
    
    if not prototypes or not prototypes.quality then
        log("Agricultural Roboport: Warning - prototypes.quality not available, cannot build quality tables")
        return
    end
    
    -- Build sorted list of qualities
    -- Exclude any quality with "unknown" in the name (Factorio internal, not for gameplay)
    local qualities = {}
    for name, quality_proto in pairs(prototypes.quality) do
        -- Skip any quality containing "unknown" (matches "unknown", "quality-unknown", etc.)
        if not name:match("unknown") then
            table.insert(qualities, {
                name = name,
                level = quality_proto.level
            })
        end
    end
    
    -- Sort by level
    table.sort(qualities, function(a, b) return a.level < b.level end)
    
    -- Build lookup tables using sequential tier indices (0, 1, 2, ...)
    -- instead of prototype.level which can be skipped by mods for stat bonuses
    storage.quality_by_level = {}
    storage.quality_level = {}
    storage.max_quality_level = 0
    
    for tier_index, quality in ipairs(qualities) do
        local tier = tier_index - 1  -- 0-based tier index
        storage.quality_by_level[tier] = quality.name
        storage.quality_level[quality.name] = tier
        storage.max_quality_level = tier
    end
    
    storage.quality_tables_version = 2  -- Mark as using tier-based format
    
    log("Agricultural Roboport: Built quality tables with " .. #qualities .. " tiers (max tier: " .. storage.max_quality_level .. ")")
end

local function adjacent_quality_name(current_name, dir)
    if not storage.quality_level or not storage.quality_by_level or not storage.max_quality_level then
        -- Fallback if tables not initialized yet
        log("Agricultural Roboport: Warning - quality tables not initialized, returning current quality")
        return current_name
    end
    
    local idx = storage.quality_level[current_name] or 0
    local new_idx = util.clamp(idx + dir, 0, storage.max_quality_level)
    return storage.quality_by_level[new_idx] or current_name
end

-- Runtime-only sprite table (not persisted to storage)
-- Maps hash_string key -> sprite_id (rendering ID)
local quality_plant_sprites = {}

-- Helper to check if quality support is enabled (startup setting)
local function is_quality_enabled()
    if settings and settings.startup and settings.startup["agricultural-roboport-enable-quality"] then
        return settings.startup["agricultural-roboport-enable-quality"].value
    end
    return true -- Default to enabled if setting not found
end

-- Use util for utility functions
local clamp = util.clamp
local table_size = util.table_size

-- Metatable for roboport settings storage
-- NOTE: We do NOT use __index here because we need nil checks to work properly.
-- Each roboport/ghost must explicitly have its settings created.
local roboport_modes_mt = {}

-- Helper function to create default roboport settings
function create_default_roboport_settings()
    return {
        mode = 0, -- default to harvest and seed
        seed_logistic_only = false,
        use_filter = false,
        filter_invert = false,
        filters = nil,
        circuit_mode_enabled = false,
        circuit_mode_signal = nil,
        circuit_filter_enabled = false,
        surface = nil,
        position = nil
    }
end

function Build_virtual_seed_info()
    local info = {}
    if write_file_log then 
        write_file_log("Build_virtual_seed_info:start", "scanning all virtual seed entities")
    end
    
    -- Scan all virtual-*-seed entities to build info by their placeable items
    for entity_name, entity_proto in pairs(prototypes.entity) do
        if entity_name:match("^virtual%-.+%-seed$") then
            -- Get the actual seed item from items_to_place_this
            if entity_proto.items_to_place_this and #entity_proto.items_to_place_this > 0 then
                local seed_name = entity_proto.items_to_place_this[1].name
                local seed_item = prototypes.item[seed_name]
                
                if seed_item then
                    local plant_result = seed_item.place_result or seed_item.plant_result
                    local plant_name = (type(plant_result) == "table" or type(plant_result) == "userdata") and plant_result.name or plant_result
                    local plant_proto = plant_name and prototypes.entity[plant_name]
                    
                    if write_file_log then
                        write_file_log("Build_virtual_seed_info:processing", 
                            "virtual_entity=", entity_name,
                            "seed=", seed_name, 
                            "plant_name=", plant_name or "nil",
                            "plant_proto=", plant_proto and plant_proto.name or "nil")
                    end
                    
                    -- Safely read autoplace/autoplace_specification.tile_restriction (some prototypes may omit keys)
                    local restrictions = nil
                    local tile_buildability_rules = nil
                    if plant_proto then
                        local ok, spec = pcall(function() return plant_proto.autoplace_specification end)
                        if ok and spec and spec.tile_restriction then
                            restrictions = spec.tile_restriction
                        else
                            local ok2, ap = pcall(function() return plant_proto.autoplace end)
                            if ok2 and ap and ap.tile_restriction then
                                restrictions = ap.tile_restriction
                            end
                        end
                        local ok3, tbr = pcall(function() return plant_proto.tile_buildability_rules end)
                        if ok3 and tbr then tile_buildability_rules = tbr end
                    end
                    info[seed_name] = {
                        tile_restriction = restrictions,
                        tile_buildability_rules = tile_buildability_rules,
                        plant_proto = plant_proto
                    }
                end
            end
        end
    end
    
    if write_file_log then
        local count = 0
        for _ in pairs(info) do count = count + 1 end
        write_file_log("Build_virtual_seed_info:complete", "total_seeds=", count)
    end
    
    return info
end

script.on_init(function()
    write_file_log("=== on_init() CALLED ===", "Initializing fresh storage")
    -- Initialize storage with metatable per Factorio data lifecycle
    storage.agricultural_roboports = setmetatable({}, roboport_modes_mt)
    -- Build virtual_seed_info using the latest logic
    if Build_virtual_seed_info then
        storage.virtual_seed_info = Build_virtual_seed_info()
    end
    -- Initialize TDM storage to safe defaults
    storage._tdm = { version = 0, snapshot_version = 0, keys = {}, next_index = 1, registered_interval = nil }
    -- Ensure quality plants storage exists for new games
    storage.quality_plants = storage.quality_plants or {}
    -- Build dynamic quality tables from prototypes
    build_quality_tables()
    -- Make process function globally accessible
    _G.process_agricultural_roboport = process_agricultural_roboport
    -- Re-read TDM settings at runtime and register the handler now that `game` is available
    tdm.reload_settings()
    write_file_log("=== on_init() COMPLETE ===")
end)

script.on_load(function()
    write_file_log("=== on_load() CALLED ===", "Restoring metatables")
    -- Restore metatable for agricultural_roboports (metatables are not persisted)
    -- This is a legitimate use of on_load per Factorio data lifecycle documentation
    if storage.agricultural_roboports then
        local count = 0
        for _ in pairs(storage.agricultural_roboports) do count = count + 1 end
        write_file_log("    storage.agricultural_roboports entries before setmetatable:", count)
        setmetatable(storage.agricultural_roboports, roboport_modes_mt)
    else
        write_file_log("    WARNING: storage.agricultural_roboports is nil!")
    end
    -- Make process function globally accessible
    _G.process_agricultural_roboport = process_agricultural_roboport
    -- Re-read TDM settings and (re)register the nth-tick handler on load
    -- TDM storage already exists from save, don't modify it (on_load must not write to storage)
    tdm.reload_settings()
    
    -- Schedule recreation of quality sprites and virtual_seed_info rebuild on the next tick
    -- Use module-level variable (cannot modify storage in on_load)
    rebuild_on_next_tick = true
    write_file_log("=== on_load() COMPLETE ===")
end)

-- Handle deferred rebuild from on_load (called by main on_tick handler)
local function handle_deferred_rebuild()
    if not rebuild_on_next_tick then return end
    rebuild_on_next_tick = false
    
    -- Check if quality tables need migration (old version used prototype.level instead of tier index)
    -- Version 1: used prototype.level (can be skipped by mods)
    -- Version 2: uses sequential tier index (0, 1, 2, ...)
    if not storage.quality_tables_version or storage.quality_tables_version < 2 then
        if write_file_log then write_file_log("=== QUALITY TABLE MIGRATION: Rebuilding quality tables (old version detected) ===") end
        build_quality_tables()
    end
    
    -- Always rebuild virtual_seed_info on load (deferred from on_load to avoid mutating storage during on_load)
        if Build_virtual_seed_info then
            write_file_log("=== on_load deferred rebuild: Rebuilding virtual_seed_info ===")
            storage.virtual_seed_info = Build_virtual_seed_info()
            write_file_log("=== virtual_seed_info rebuilt with", table_size(storage.virtual_seed_info or {}), "entries ===")
        end
        
        -- Skip quality sprite recreation if disabled
        if not is_quality_enabled() then return end
        
        -- Recreate sprites from persistent quality_plants storage
        -- Sprites use only_in_alt_mode flag, so they automatically show/hide
        if not storage.quality_plants then return end
        
        if write_file_log then write_file_log("[QUALITY] on_load: Recreating sprites for", table_size(storage.quality_plants), "quality plants") end
        
        local old_keys_to_migrate = {}
        
        for key, data in pairs(storage.quality_plants) do
            if data and data.quality then
                -- Try to parse new hash format first (surface:x.xx,y.yy)
                local surface_name, fx, fy = key:match("^([^:]+):([%d%.%-]+),([%d%.%-]+)$")
                local is_old_format = false
                
                -- If that fails, try old format (surface:int,int where coordinates were floor(x/2))
                if not surface_name then
                    surface_name, fx, fy = key:match("^([^:]+):(-?%d+),(-?%d+)$")
                    if surface_name then
                        is_old_format = true
                        if write_file_log then write_file_log("[QUALITY] on_load: Found old hash format key=", key) end
                    else
                        goto continue_end
                    end
                end
                
                local surface = game and game.surfaces and game.surfaces[surface_name]
                if not surface then goto continue_end end
                
                local x_search, y_search, area
                if is_old_format then
                    -- Old format: hash was floor(x/2), so actual coordinates span 2x2 tile area
                    local x_min = tonumber(fx) * 2
                    local y_min = tonumber(fy) * 2
                    area = {{x_min - 0.5, y_min - 0.5}, {x_min + 2.5, y_min + 2.5}}
                else
                    -- New format: exact coordinates
                    x_search = tonumber(fx)
                    y_search = tonumber(fy)
                    area = {{x_search - 0.5, y_search - 0.5}, {x_search + 0.5, y_search + 0.5}}
                end
                
                local ents = surface.find_entities_filtered{ area = area, type = "plant" }
                local plant = ents and ents[1]
                
                if plant and plant.valid then
                    local qname = nil
                    if type(data.quality) == "table" or type(data.quality) == "userdata" then 
                        qname = data.quality.name 
                    elseif type(data.quality) == "string" then 
                        qname = data.quality 
                    end
                    
                    if qname and qname ~= "normal" then
                        local ok, sprite_id = pcall(function()
                            return rendering.draw_sprite{
                                sprite = "quality." .. qname,
                                target = plant,
                                surface = surface,
                                target_offset = {0.0, 0.0},
                                x_scale = 0.5,
                                y_scale = 0.5,
                                render_layer = "light-effect",
                                only_in_alt_mode = true
                            }
                        end)
                        
                        if ok and sprite_id then 
                            quality_plant_sprites[key] = sprite_id
                            if write_file_log then write_file_log("[QUALITY] on_load: Recreated sprite for key=", key, "sprite=", sprite_id) end
                        end
                        
                        -- If this was old format, schedule migration to new format
                        if is_old_format then
                            table.insert(old_keys_to_migrate, {
                                old_key = key,
                                plant = plant,
                                quality = data.quality
                            })
                        end
                    end
                end
                ::continue_end::
            end
        end
        
        -- Migrate old format keys to new format (backward compatibility)
        if #old_keys_to_migrate > 0 then
            if write_file_log then write_file_log("[QUALITY] on_load: Migrating", #old_keys_to_migrate, "old format keys to new format") end
            
            for _, entry in ipairs(old_keys_to_migrate) do
                -- Remove old key
                storage.quality_plants[entry.old_key] = nil
                
                -- Remove old sprite from runtime table
                local old_sprite_id = quality_plant_sprites[entry.old_key]
                if old_sprite_id then
                    quality_plant_sprites[entry.old_key] = nil
                end
                
                -- Re-register with new hash format (exact coordinates)
                local new_key = hash_string(entry.plant.position.x, entry.plant.position.y, entry.plant.surface.name)
                storage.quality_plants[new_key] = { quality = entry.quality }
                
                -- Sprite already created above, just update runtime table key
                if old_sprite_id then
                    quality_plant_sprites[new_key] = old_sprite_id
                end
                
                if write_file_log then 
                    write_file_log("[QUALITY] Migrated:", entry.old_key, "->", new_key) 
                end
            end
            
            if write_file_log then write_file_log("[QUALITY] on_load: Migration complete") end
        end
        
        if write_file_log then write_file_log("[QUALITY] on_load: Sprite recreation complete, total sprites=", table_size(quality_plant_sprites)) end
end

-- =====================
-- Handler functions region
-- =====================

-- Quality-plant runtime registry (inspired by quality-trees mod)
local function hash_string(x, y, surface_name)
    -- Use exact coordinates to avoid collisions in dense mode (9+ plants per tile)
    -- Format: "surface_name:x,y" where x and y preserve decimal precision
    return string.format("%s:%.2f,%.2f", surface_name, x, y)
end

local function register_plant(plant, quality)
    -- Skip quality tracking if disabled
    if not is_quality_enabled() then return end
    
    storage.quality_plants = storage.quality_plants or {}

    -- Don't store 'normal' quality plants (no badge needed)
    -- Quality can be either a table or userdata (LuaQualityPrototype)
    if not quality then 
		if write_file_log then write_file_log("[QUALITY] register_plant: quality is nil, skipping registration for plant=", plant.name, "pos=", serpent and serpent.line and serpent.line(plant.position) or tostring(plant.position)) end
		return 
	end
	
    -- Accept both table and userdata (LuaQualityPrototype is userdata in Factorio)
    local qtype = type(quality)
    if qtype ~= "table" and qtype ~= "userdata" then 
		if write_file_log then write_file_log("[QUALITY] register_plant: quality is neither table nor userdata, skipping registration for plant=", plant.name, "pos=", serpent and serpent.line and serpent.line(plant.position) or tostring(plant.position), "quality=", tostring(quality), "type=", qtype) end
		return 
	end
	
    -- Check quality level (skip normal quality with level 0)
    if not quality.level or quality.level == 0 then 
		if write_file_log then write_file_log("[QUALITY] register_plant: quality level is nil or 0 (normal quality), skipping registration for plant=", plant.name, "pos=", serpent and serpent.line and serpent.line(plant.position) or tostring(plant.position), "quality.level=", tostring(quality.level), "quality.name=", tostring(quality.name)) end
		return 
	end
	
    if not quality.name then 
		if write_file_log then write_file_log("[QUALITY] register_plant: quality name is nil, skipping registration for plant=", plant.name, "pos=", serpent and serpent.line and serpent.line(plant.position) or tostring(plant.position), "quality.level=", tostring(quality.level)) end
		return 
	end

    local key = hash_string(plant.position.x, plant.position.y, plant.surface.name)
    
    -- Store plant quality in persistent storage (without sprite)
    if not storage.quality_plants then storage.quality_plants = {} end
    storage.quality_plants[key] = { quality = quality }
    
    -- Create sprite with only_in_alt_mode flag (automatically handles visibility)
    local ok, sprite_id = pcall(function()
        return rendering.draw_sprite{
            sprite = "quality." .. quality.name,
            target = plant,
            surface = plant.surface,
            target_offset = {0.0, 0.0},
            x_scale = 0.5,
            y_scale = 0.5,
            render_layer = "light-effect",
            only_in_alt_mode = true
        }
    end)
    
    if ok and sprite_id then
        quality_plant_sprites[key] = sprite_id
        if write_file_log then write_file_log("[QUALITY] Registered plant with sprite:", plant.name, "key=", key, "quality=", quality.name, "sprite=", sprite_id) end
    else
        if write_file_log then write_file_log("[QUALITY] Registered plant (sprite creation failed):", plant.name, "key=", key, "quality=", quality.name) end
    end
end

local function harvest_plant(plant, inv_buffer, harvester_force)
    -- Skip quality tracking if disabled
    if not is_quality_enabled() then 
        if write_file_log then write_file_log("[QUALITY] harvest_plant: quality disabled, skipping") end
        return 
    end
    
    -- Use harvester's force for research checks, fallback to plant force (which will be neutral)
    local force_to_use = harvester_force or plant.force
    
    storage.quality_plants = storage.quality_plants or {}
    local key = hash_string(plant.position.x, plant.position.y, plant.surface.name)
    local plant_quality_data = storage.quality_plants[key]
    if write_file_log then write_file_log("[QUALITY] harvest_plant called:", "plant=", plant.name, "pos=", serpent and serpent.line and serpent.line(plant.position) or tostring(plant.position), "key=", key, "has_registry=", tostring(plant_quality_data ~= nil), "inv_buffer=", tostring(inv_buffer ~= nil), "harvester_force=", harvester_force and harvester_force.name or "nil", "force_to_use=", force_to_use.name) end
    
    local harvest_quality = nil
    if plant_quality_data then
        -- Destroy sprite from runtime table if it exists
        local sprite_id = quality_plant_sprites[key]
        if sprite_id then
            pcall(function() rendering.destroy(sprite_id) end)
            quality_plant_sprites[key] = nil
            if write_file_log then write_file_log("[QUALITY] Destroyed sprite for harvest:", "key=", key, "sprite=", sprite_id) end
        end
        
        harvest_quality = plant_quality_data.quality
        storage.quality_plants[key] = nil
        if write_file_log then write_file_log("[QUALITY] Harvesting plant with stored quality:", plant.name, "key=", key, "quality=", harvest_quality and harvest_quality.name or tostring(harvest_quality)) end
    end

    -- If plant had no stored quality, we may still roll a deterministic per-plant proc
    local final_quality = nil
    local had_registry = (plant_quality_data ~= nil)
    if had_registry then
        final_quality = harvest_quality
    else
        -- If plant entity has a runtime quality (rare), use it
        if plant.quality and plant.quality.name and plant.quality.name ~= "normal" then
            final_quality = plant.quality
        end
    end

    -- Get controlled mutation research level (dynamic based on available techs)
    local function get_controlled_mutation_level(force)
        -- Early exit if quality is disabled
        if not is_quality_enabled() then
            return 0
        end
        
        -- Handle neutral/nil force (return 0 = no research bonus)
        if not force or not force.technologies then
            if write_file_log then write_file_log("[QUALITY] get_controlled_mutation_level: force or technologies is nil") end
            return 0
        end
        
        if write_file_log then write_file_log("[QUALITY] Checking research level for force:", force.name) end
        
        -- Find all controlled mutations technologies using API
        -- Scan technology prototypes to find matching pattern and extract levels
        local max_level = 0
        local tech_levels = {}
        
        if prototypes and prototypes.technology then
            for tech_name, tech_proto in pairs(prototypes.technology) do
                local level_str = tech_name:match("^agricultural%-controlled%-mutations%-(%d+)$")
                if level_str then
                    local level = tonumber(level_str)
                    if level then
                        tech_levels[level] = tech_name
                        if level > max_level then
                            max_level = level
                        end
                    end
                end
            end
        end
        
        if max_level == 0 then
            if write_file_log then write_file_log("[QUALITY] No controlled mutation technologies found in prototypes") end
            return 0
        end
        
        if write_file_log then write_file_log("[QUALITY] Found", max_level, "controlled mutation tech levels") end
        
        -- Search backwards from highest discovered level to find highest researched
        for level = max_level, 1, -1 do
            local tech_name = tech_levels[level]
            if tech_name then
                local tech = force.technologies[tech_name]
                if tech and tech.researched then
                    if write_file_log then write_file_log("[QUALITY] Found research level:", level) end
                    return level
                end
            end
        end
        
        if write_file_log then write_file_log("[QUALITY] No controlled mutation research found, returning 0") end
        return 0
    end
    
    -- Get solar intensity multiplier for this surface
    local function get_solar_intensity(surface)
        -- Try surface.solar_power_multiplier first (Factorio 2.0+)
        if surface.solar_power_multiplier then
            return surface.solar_power_multiplier
        end
        -- Fallback: try reading from planet prototype via surface properties
        if surface.planet and surface.planet.prototype and surface.planet.prototype.solar_power_multiplier then
            return surface.planet.prototype.solar_power_multiplier
        end
        -- Default to 1.0 if neither available
        return 1.0
    end
    
    -- Get pollution-based mutation multiplier (scales from 1.0x at pollution 50 to 40.0x at pollution 500)
    -- With solar=1.0 and pollution=500: 0.5% * 1.0 * 40.0 = 20% (clamped)
    local function get_pollution_multiplier(surface, position)
        local pollution = surface.get_pollution(position)
        
        -- No pollution bonus below threshold of 50
        if pollution < 50 then
            return 1.0
        end
        
        -- Linear scaling from 1.0x to 40.0x between pollution 50 and 500
        -- At pollution = 50: multiplier = 1.0
        -- At pollution = 500: multiplier = 40.0
        local multiplier = 1.0 + (pollution - 50) / (500 - 50) * 39.0
        
        -- Clamp to max 40x multiplier
        return math.min(40.0, multiplier)
    end

    local mutated = false
    local qname = (type(final_quality) == "table" or type(final_quality) == "userdata") and final_quality.name or (type(final_quality) == "string" and final_quality or "normal")

    if write_file_log then write_file_log("[QUALITY] About to calculate mutation chance:", "final_quality=", tostring(final_quality), "qname=", qname) end

    -- Calculate mutation chance: clamp((base * solar) * pollution, 0.5%, 20%)
    -- Base chance: 0.5% (0.005)
    -- Solar multiplier: varies by surface (0.5 Gleba, 1.0 Nauvis, 3.0 Vulcanus, etc.)
    -- Pollution multiplier: 1.0x to 40.0x (pollution 50-500)
    -- Final range: 0.5% to 20% (clamped)
    -- Examples:
    --   Nauvis (solar=1.0), pollution=500: 0.5% * 1.0 * 40 = 20% (clamped)
    --   Gleba (solar=0.5), pollution=500: 0.5% * 0.5 * 40 = 10%
    --   Vulcanus (solar=3.0), pollution=500: 0.5% * 3.0 * 40 = 60% → 20% (clamped)
    local base_chance = 0.005 -- 0.5%
    
    local solar_multiplier = 1.0
    local ok2, result2 = pcall(get_solar_intensity, plant.surface)
    if ok2 then 
        solar_multiplier = result2
        if write_file_log then write_file_log("[QUALITY] solar_multiplier:", solar_multiplier) end
    else
        if write_file_log then write_file_log("[QUALITY] ERROR getting solar_multiplier:", tostring(result2)) end
    end
    
    local pollution_multiplier = 1.0
    local ok3, result3 = pcall(get_pollution_multiplier, plant.surface, plant.position)
    if ok3 then 
        pollution_multiplier = result3
        if write_file_log then write_file_log("[QUALITY] pollution_multiplier:", pollution_multiplier) end
    else
        if write_file_log then write_file_log("[QUALITY] ERROR getting pollution_multiplier:", tostring(result3)) end
    end
    
    -- Formula: clamp((base * solar) * pollution, 0.5%, 20%)
    local base_with_solar = base_chance * solar_multiplier
    local chance = base_with_solar * pollution_multiplier
    chance = math.max(0.005, math.min(0.20, chance))  -- Clamp between 0.5% and 20%
    
    -- Calculate pollution bonus for improvement penalty
    local pollution_bonus = (chance - base_with_solar) * 0.5
    
    if write_file_log then 
        write_file_log("[QUALITY] Mutation chance calculation:", 
            "base=", base_chance, 
            "solar_mult=", solar_multiplier,
            "pollution_mult=", pollution_multiplier,
            "final_chance=", chance, 
            "current_quality=", qname) 
    end
    if chance > 0 then
        if write_file_log then write_file_log("[QUALITY] Rolling for quality mutation (math.random):", "chance=", chance, "current quality=", qname) end
        -- Use math.random for sampling (simpler, server-controlled in multiplayer)
        local sample = math.random()
        if write_file_log then write_file_log("[QUALITY] Proc roll (math.random): chance=", chance, "sample=", sample, "current=", qname) end
        if sample < chance then
            local dir_sample = math.random()
            -- Use sequential quality tier index instead of potentially-skipped level number
            -- (Some mods like ic-more-qualities skip levels to inflate stat bonuses)
            local quality_tier = storage.quality_level[qname] or 0
            
            -- Get controlled mutation research level and calculate improvement chance
            local research_level = get_controlled_mutation_level(force_to_use)
            local base_improvement_chance = research_level * 0.20  -- 0%, 20%, 40%, 60%, 80%, 100%
            -- Pollution reduces improvement chance (high pollution = more chaotic mutations)
            local adjusted_improvement_chance = base_improvement_chance - (quality_tier * 0.20) - pollution_bonus
            
            if write_file_log then 
                write_file_log("[QUALITY] Improvement calculation:", 
                    "research_level=", research_level,
                    "base_improvement=", base_improvement_chance,
                    "quality_tier=", quality_tier,
                    "pollution_bonus=", pollution_bonus,
                    "adjusted_improvement=", adjusted_improvement_chance,
                    "dir_sample=", dir_sample)
            end
            
            local dir = (dir_sample < adjusted_improvement_chance) and 1 or -1
            if write_file_log then write_file_log("[QUALITY] Direction roll (math.random): sample=", dir_sample, "dir=", dir) end
            local cur = qname
            local new_q = adjacent_quality_name(cur, dir)
            if new_q ~= cur then
                final_quality = new_q
                mutated = true
            end
            if write_file_log then 
                write_file_log("[QUALITY] RNG SUMMARY (math.random):", 
                    "chance=", chance, 
                    "sample=", sample, 
                    "dir_sample=", dir_sample, 
                    "dir=", dir, 
                    "current=", cur, 
                    "new=", new_q, 
                    "mutated=", tostring(mutated)) 
            end
            
            -- Flying text for mutation events (per-player setting)
            if game and game.players then
                local arrow = ""
                local color = {r = 0.5, g = 0.5, b = 0.5} -- Gray for no change
                
                if new_q ~= cur then
                    if dir > 0 then
                        arrow = "↑"
                        color = {r = 0.0, g = 1.0, b = 0.0} -- Green for improvement
                    else
                        arrow = "↓"
                        color = {r = 1.0, g = 0.0, b = 0.0} -- Red for degradation
                    end
                else
                    -- Clamped (tried to go beyond bounds)
                    if dir > 0 then
                        arrow = "↑≡" -- Up but clamped
                    else
                        arrow = "↓≡" -- Down but clamped
                    end
                end
                
                local text = {"agricultural-roboport.mutation-flying-text", 
                    arrow, 
                    string.format("%.2f", chance * 100), 
                    string.format("%.0f", adjusted_improvement_chance * 100)}
                
                -- Create flying text for players who have visualization enabled
                for _, player in pairs(game.players) do
                    if player and player.valid then
                        local show_visualization = false
                        if player.mod_settings and player.mod_settings["agricultural-roboport-mutation-visualization"] then
                            show_visualization = player.mod_settings["agricultural-roboport-mutation-visualization"].value
                        end
                        
                        if show_visualization then
                            player.create_local_flying_text{
                                text = text,
                                position = plant.position,
								surface = plant.surface,
                                create_at_cursor = false,
                                color = color,
                                time_to_live = 180, -- 3 seconds
                                speed = 0.5
                            }
                        end
                    end
                end
            end
        end
    end

    -- If there's no resulting quality to apply, do nothing
    local final_qname = (type(final_quality) == "table" and final_quality.name) or final_quality
    if (not final_qname) or final_qname == "normal" then
        return
    end

    -- Proceed to swap inventory stacks to final_qname
    harvest_quality = final_qname
    if write_file_log then write_file_log("[QUALITY] Applying final quality for harvest:", harvest_quality, "mutated=", mutated, "had_registry=", tostring(had_registry)) end

    if inv_buffer then
        -- (inventory swap logic follows; reuse earlier code path)
        local ok_list, size = pcall(function() return #inv_buffer end)
        if write_file_log then write_file_log("[QUALITY] Inventory size (read attempt):", ok_list and size or "err") end
        local to_replace = {}
        local ok_iter = pcall(function()
            for i = 1, #inv_buffer do
                local stack = inv_buffer[i]
                if stack and stack.valid_for_read then
                    to_replace[#to_replace+1] = { name = stack.name, count = stack.count }
                    if write_file_log then write_file_log("[QUALITY] Buffer before: idx=", i, "name=", stack.name, "count=", stack.count, "quality=", stack.quality and stack.quality.name or "nil") end
                end
            end
        end)
        if not ok_iter and write_file_log then write_file_log("[QUALITY] Failed to iterate inv_buffer") end
        for _, entry in ipairs(to_replace) do
            pcall(function()
                local removed = inv_buffer.remove{ name = entry.name, count = entry.count }
                if write_file_log then write_file_log("[QUALITY] Removed from buffer:", entry.name, "requested=", entry.count, "removed=", removed) end
                if removed and removed > 0 then
                    local qval = harvest_quality
                    local insert_ok, inserted_or_err = pcall(function()
                        return inv_buffer.insert{ name = entry.name, count = removed, quality = qval }
                    end)
                    if write_file_log then
                        if insert_ok then
                            write_file_log("[QUALITY] Inserted into buffer with quality:", entry.name, "count=", inserted_or_err, "quality=", qval or "nil")
                        else
                            write_file_log("[QUALITY] Insert FAILED for:", entry.name, "error=", tostring(inserted_or_err), "quality=", tostring(qval))
                        end
                    end
                end
            end)
        end
    else
        if write_file_log then write_file_log("[QUALITY] No inv_buffer provided for plant harvest at key=", key) end
    end
end


local function on_robot_built_virtual_seed(event)
    local entity = event.entity
    if entity.name:match("^virtual%-.+%-seed$") then
        local surface = entity.surface
        local position = entity.position
        
        -- Get the actual seed item name from the virtual entity's prototype
        local virtual_proto = prototypes.entity[entity.name]
        local seed_name = nil
        
        if virtual_proto and virtual_proto.items_to_place_this and #virtual_proto.items_to_place_this > 0 then
            seed_name = virtual_proto.items_to_place_this[1].name
        end
        
        -- Debug: Log all event properties
        if write_file_log then
            write_file_log("[ROBOT DEBUG] Event properties:")
            write_file_log("  entity.name:", entity.name)
            write_file_log("  extracted seed_name:", seed_name or "nil")
            write_file_log("  entity.quality:", entity.quality and entity.quality.name or "nil")
            write_file_log("  event.item:", event.item and (event.item.name or "has item object") or "nil")
            if event.item then
                write_file_log("  event.item.name:", event.item.name or "nil")
                write_file_log("  event.item.quality:", event.item.quality or "nil")
            end
            write_file_log("  event.stack:", event.stack and "has stack" or "nil")
            if event.stack then
                write_file_log("  event.stack.name:", event.stack.name or "nil")
                write_file_log("  event.stack.quality:", event.stack.quality and event.stack.quality.name or "nil")
            end
            write_file_log("  event.tags:", event.tags and serpent.block(event.tags) or "nil")
        end
        
        local plant_result = nil
        if seed_name and prototypes.item[seed_name] then
            plant_result = prototypes.item[seed_name].place_result or prototypes.item[seed_name].plant_result
            if write_file_log then
                write_file_log("[ROBOT DEBUG] Found seed item:", seed_name, "plant_result:", plant_result and (type(plant_result) == "table" or type(plant_result) == "userdata") and plant_result.name or plant_result or "nil")
            end
        else
            if write_file_log then
                write_file_log("[ROBOT DEBUG] Seed item not found:", seed_name or "nil")
            end
        end
        local plant_result_name = plant_result
        if (type(plant_result) == "table" or type(plant_result) == "userdata") and plant_result.name then
            plant_result_name = plant_result.name
        end
        if plant_result_name and prototypes.entity[plant_result_name] then
            -- Get quality from the item that was consumed by the robot (keep as object)
            local quality = nil
            if event.stack and event.stack.quality then
                quality = event.stack.quality
            elseif event.item and event.item.quality then
                quality = event.item.quality
            end
            
            if write_file_log then
                write_file_log("[ROBOT] Building tree:", plant_result_name, "quality:", quality and quality.name or "normal", "from virtual:", entity.name)
            end
            
            local created_tree = surface.create_entity{
                name = plant_result_name,
                position = position,
                force = entity.force,
                quality = quality
            }
            
            if write_file_log and created_tree then
                write_file_log("[ROBOT] Created tree:", created_tree.name, "actual quality:", created_tree.quality and created_tree.quality.name or "nil", "valid:", tostring(created_tree.valid))
            end
            -- Register plant quality in runtime registry (so we can preserve quality on harvest)
            if created_tree and created_tree.valid then
                pcall(function() register_plant(created_tree, quality) end)
            end
            
            entity.destroy()
        end
    end
end

-- Helper: Check if surface matches plant's surface_conditions
local function surface_matches_conditions(surface, surface_conditions)
    if not surface_conditions then return true end
    if type(surface_conditions) == "table" then
        -- If array: check if surface.name matches any entry
        if #surface_conditions > 0 then
            for _, v in ipairs(surface_conditions) do
                if surface.name == v then
                    return true
                end
            end
            return false
        else
            -- Dictionary: check key-value pairs
            for k, v in pairs(surface_conditions) do
                if surface[k] ~= v then
                    return false
                end
            end
            return true
        end
    end
    return false
end

local function on_built_virtual_seed_ghost(entity, event)
    if entity.name == "entity-ghost" and entity.ghost_name and entity.ghost_name:match("^virtual%-.+%-seed$") then
        local surface = entity.surface
        local position = entity.position
        -- Instead of using the virtual seed's autoplace, use the underlying plant's autoplace_specification
        local seed_name = entity.ghost_name:match("^virtual%-(.+%-seed)$")
        local seed_item = seed_name and prototypes.item[seed_name]
        local plant_result = seed_item and (seed_item.place_result or seed_item.plant_result)
        local plant_name = (type(plant_result) == "table" or type(plant_result) == "userdata") and plant_result.name or plant_result
        local plant_proto = plant_name and prototypes.entity[plant_name]
        local restrictions = nil
        local tile_buildability_rules = nil
        if plant_proto then
            local ok, spec = pcall(function() return plant_proto.autoplace_specification end)
            if ok and spec and spec.tile_restriction then
                restrictions = spec.tile_restriction
            else
                local ok2, ap = pcall(function() return plant_proto.autoplace end)
                if ok2 and ap and ap.tile_restriction then
                    restrictions = ap.tile_restriction
                end
            end
            local ok3, tbr = pcall(function() return plant_proto.tile_buildability_rules end)
            if ok3 and tbr then tile_buildability_rules = tbr end
        end
        local tile = surface.get_tile(position)
        local allowed = false
        if restrictions then
            for _, allowed_tile in pairs(restrictions) do
                if tile.name == (allowed_tile.first or allowed_tile) then
                    allowed = true
                    break
                end
            end
        elseif tile_buildability_rules then
            local info = { tile_buildability_rules = tile_buildability_rules }
            local allowed_tbr, dbg = tile_buildability.evaluate_tile_buildability(surface, position, seed_name, info, plant_proto)
            if write_file_log then
                write_file_log("ghost:tile_check", seed_name, dbg.center_tile or "<nil>", allowed_tbr and "allowed" or "blocked", serpent and serpent.block and serpent.block(dbg) or tostring(dbg))
            end
            allowed = allowed_tbr
        else
            allowed = true -- No restrictions, allow by default
        end
        if allowed and plant_proto and type(plant_proto.surface_conditions) == "table" then
            allowed = surface_matches_conditions(surface, plant_proto.surface_conditions)
        end
        if not allowed then
            entity.destroy()
            local player = game.get_player(event.player_index)
            if player then
                player.create_local_flying_text({
                    text = {"cant-build-reason.cant-build-on-tile", tile.name},
                    create_at_cursor = true,
                })
            end
        end
    end
end

local function copy_roboport_settings(source_key, dest_key)
    local src = storage.agricultural_roboports[source_key] or {}
    local dest = {}
    dest.mode = src.mode or 0
    dest.seed_logistic_only = src.seed_logistic_only or false
    dest.use_filter = src.use_filter or false
    dest.filter_invert = src.filter_invert or false
    dest.circuit_mode_enabled = src.circuit_mode_enabled or false
    dest.circuit_mode_signal = src.circuit_mode_signal
    dest.circuit_filter_enabled = src.circuit_filter_enabled or false
    if type(src.filters) == "table" then
        local new_filters = {}
        for i = 1, 5 do new_filters[i] = src.filters[i] end
        dest.filters = new_filters
    else
        dest.filters = nil
    end
    storage.agricultural_roboports[dest_key] = dest
end

local function on_built_event_handler(event)
	
    local entity = event.created_entity or event.entity
    if not entity then return end
    
    -- CRITICAL DEBUG: Check if storage table exists and has metatable
    if not storage.agricultural_roboports then
        write_file_log("[CRITICAL] storage.agricultural_roboports is NIL! Reinitializing...")
        storage.agricultural_roboports = setmetatable({}, roboport_modes_mt)
    end
    
    local mt = getmetatable(storage.agricultural_roboports)
    if not mt then
        write_file_log("[CRITICAL] Metatable is missing! Restoring...")
        setmetatable(storage.agricultural_roboports, roboport_modes_mt)
    end
    
    -- Extended logging to diagnose quality roboport issues
    local entity_type = entity.type or "unknown"
	
    local entity_quality = entity.quality and entity.quality.name or "nil"
    local has_tags = event.tags ~= nil
    local entity_tags = entity.tags
    local unit_number = entity.unit_number or "nil"
    
    write_file_log("[Event] Built entity", 
        "name=", tostring(entity.name),
        "type=", entity_type,
        "quality=", entity_quality,
        "unit_number=", tostring(unit_number),
        "pos=", serpent and serpent.block and serpent.block(entity.position) or tostring(entity.position))
    
    if entity.name == "entity-ghost" then
        local ghost_name = entity.ghost_name or "nil"
        write_file_log("    ghost_name=", tostring(ghost_name), "ghost_quality=", entity.quality and entity.quality.name or "nil")
    end
    
    if has_tags then
        write_file_log("    event.tags=", serpent and serpent.block and serpent.block(event.tags) or tostring(event.tags))
    end
    
    if entity_tags then
        write_file_log("    entity.tags=", serpent and serpent.block and serpent.block(entity_tags) or tostring(entity_tags))
    end
    if entity.name == "entity-ghost" and entity.ghost_name == "agricultural-roboport" then
        local ghost_key = string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
        if entity.tags then
			-- Handle agricultural roboport ghosts with tags
            local settings = create_default_roboport_settings()
            settings.mode = entity.tags.mode or 0
            settings.seed_logistic_only = entity.tags.seed_logistic_only or false
            settings.use_filter = entity.tags.use_filter or false
            settings.filter_invert = entity.tags.filter_invert or false
            settings.filters = (type(entity.tags.filters) == "table" and (function() local f = {}; for i=1,5 do f[i]=entity.tags.filters[i] end; return f end)()) or nil
            settings.circuit_mode_enabled = entity.tags.circuit_mode_enabled or false
            settings.circuit_mode_signal = entity.tags.circuit_mode_signal
            settings.circuit_filter_enabled = entity.tags.circuit_filter_enabled or false
            settings.surface = entity.surface.name
            settings.position = {x = entity.position.x, y = entity.position.y}
            storage.agricultural_roboports[ghost_key] = settings
			write_file_log("[Event] Ghost built with tags", "ghost_key=", ghost_key)
            tdm.mark_dirty()
        else
            -- Always create a default settings table for manually placed ghosts
            local settings = create_default_roboport_settings()
            settings.surface = entity.surface.name
            settings.position = {x = entity.position.x, y = entity.position.y}
            storage.agricultural_roboports[ghost_key] = settings
			write_file_log("[Event] Ghost built without tags", "ghost_key=", ghost_key)
            tdm.mark_dirty()
        end
        return
    end

    -- If a real plant was placed (player/script/tower), register its quality
    if entity.type == "plant" then
        local plant_quality = nil
        -- Check consumed_items first (manual planting with quality items)
        
		if event and event.consumed_items and not event.consumed_items.is_empty() then
            local consumed_item = event.consumed_items[1]
            if consumed_item and consumed_item.quality then
                plant_quality = consumed_item.quality
                if write_file_log then 
                    write_file_log("[QUALITY] Using quality from consumed_item:", consumed_item.name, "quality=", consumed_item.quality.name) 
                end
            end
        end
        -- Fallback to other sources if consumed_items didn't have quality
        if not plant_quality then
            if event and event.stack and event.stack.quality then
                plant_quality = event.stack.quality
            elseif event and event.item and event.item.quality then
                plant_quality = event.item.quality
            elseif entity.quality and entity.quality.name and entity.quality.name ~= "normal" then
                plant_quality = entity.quality
            end
        end
        pcall(function() register_plant(entity, plant_quality) end)
    end
    
    -- Handle agricultural roboport entities
    if entity.name == "agricultural-roboport" then
        -- Log storage state BEFORE modification
        local count_before = 0
        for _ in pairs(storage.agricultural_roboports) do count_before = count_before + 1 end
        write_file_log("[Event] BEFORE storage modification", "entries=", count_before, "metatable=", tostring(getmetatable(storage.agricultural_roboports) ~= nil))
        
        if event.tags then
            local settings = create_default_roboport_settings()
            settings.mode = event.tags.mode or 0
            settings.seed_logistic_only = event.tags.seed_logistic_only or false
            settings.use_filter = event.tags.use_filter or false
            settings.filter_invert = event.tags.filter_invert or false
            settings.filters = (type(event.tags.filters) == "table" and (function() local f = {}; for i=1,5 do f[i]=event.tags.filters[i] end; return f end)()) or nil
            settings.circuit_mode_enabled = event.tags.circuit_mode_enabled or false
            settings.circuit_mode_signal = event.tags.circuit_mode_signal
            settings.circuit_filter_enabled = event.tags.circuit_filter_enabled or false
            settings.surface = entity.surface.name
            settings.position = {x = entity.position.x, y = entity.position.y}
            write_file_log("[Event] About to assign to storage", "unit_number=", entity.unit_number, "type=", type(entity.unit_number))
            storage.agricultural_roboports[entity.unit_number] = settings
            -- Verify assignment succeeded
            local count_after = 0
            for _ in pairs(storage.agricultural_roboports) do count_after = count_after + 1 end
            local verify = storage.agricultural_roboports[entity.unit_number]
            write_file_log("[Event] AFTER storage assignment", "entries=", count_after, "verified=", tostring(verify ~= nil))
			write_file_log("[Event] Roboport built with tags", "unit=", entity.unit_number)
            tdm.mark_dirty()
        else
            local ghost_key = string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
            local ghost_settings = storage.agricultural_roboports[ghost_key]
            if ghost_settings ~= nil then
				write_file_log("[Event] We think this is a ghost, found settings", "unit=", entity.unit_number, "ghost_key=", ghost_key, ghost_settings)
                ghost_settings.surface = entity.surface.name
                ghost_settings.position = {x = entity.position.x, y = entity.position.y}
                write_file_log("[Event] About to assign to storage", "unit_number=", entity.unit_number, "type=", type(entity.unit_number))
                storage.agricultural_roboports[entity.unit_number] = ghost_settings
                storage.agricultural_roboports[ghost_key] = nil
                -- Verify assignment succeeded
                local count_after = 0
                for _ in pairs(storage.agricultural_roboports) do count_after = count_after + 1 end
                local verify = storage.agricultural_roboports[entity.unit_number]
                write_file_log("[Event] AFTER storage assignment", "entries=", count_after, "verified=", tostring(verify ~= nil))
				write_file_log("[Event] Roboport built over ghost, copied settings", "unit=", entity.unit_number, "ghost_key=", ghost_key)
                tdm.mark_dirty()
            else
                local settings = create_default_roboport_settings()
                settings.surface = entity.surface.name
                settings.position = {x = entity.position.x, y = entity.position.y}
                write_file_log("[Event] About to assign to storage", "unit_number=", entity.unit_number, "type=", type(entity.unit_number))
                storage.agricultural_roboports[entity.unit_number] = settings
                -- Verify assignment succeeded
                local count_after = 0
                for _ in pairs(storage.agricultural_roboports) do count_after = count_after + 1 end
                local verify = storage.agricultural_roboports[entity.unit_number]
                write_file_log("[Event] AFTER storage assignment", "entries=", count_after, "verified=", tostring(verify ~= nil))
				write_file_log("[Event] Roboport built without tags and ghost", "unit=", entity.unit_number)
                tdm.mark_dirty()
            end
        end
        return
    end
    
    -- Handle virtual seed ghosts
    if entity.name == "entity-ghost" and entity.ghost_name and entity.ghost_name:match("^virtual%-.+%-seed$") then
        on_built_virtual_seed_ghost(entity, event)
        return
    end
end

local function on_remove_agricultural_roboport(event)
    local entity = event.entity
    if entity and entity.name == "agricultural-roboport" then
        local settings = storage.agricultural_roboports[entity.unit_number]
        
        if settings then
            -- Check if this is a death (not deconstruction) by checking event name
            -- on_entity_died = entity was destroyed (will be auto-ghosted if configured)
            -- on_player_mined_entity or on_robot_mined_entity = intentional removal
            local is_death = (event.name == defines.events.on_entity_died)
            
            if is_death then
                -- Entity died (not deconstructed) - it will likely be auto-ghosted
                -- Convert settings to ghost_key format so they can be retrieved when revived
                local ghost_key = string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
                storage.agricultural_roboports[ghost_key] = settings
                write_file_log("[Event] Roboport died, saved settings for ghost revival", "unit=", entity.unit_number, "ghost_key=", ghost_key)
            else
                -- Entity was mined/deconstructed intentionally - don't preserve settings
                write_file_log("[Event] Roboport mined/deconstructed", "unit=", entity.unit_number)
            end
            
            -- Always remove the unit_number entry
            storage.agricultural_roboports[entity.unit_number] = nil
            tdm.mark_dirty()
        end
    end
end

local function on_entity_settings_pasted(event)
    local source = event.source
    local destination = event.destination
    if source and destination and source.valid and destination.valid then
        local is_source_roboport = (source.name == "agricultural-roboport")
        local is_source_ghost = (source.name == "entity-ghost" and source.ghost_name == "agricultural-roboport")
        local is_dest_roboport = (destination.name == "agricultural-roboport")
        local is_dest_ghost = (destination.name == "entity-ghost" and destination.ghost_name == "agricultural-roboport")
        if (is_source_roboport or is_source_ghost) and (is_dest_roboport or is_dest_ghost) then
            local function get_key(entity)
                if entity.name == "agricultural-roboport" then
                    return entity.unit_number
                else
                    return string.format("ghost_%d_%d_%s", entity.position.x, entity.position.y, entity.surface.name)
                end
            end
            local source_key = get_key(source)
            local dest_key = get_key(destination)
            write_file_log("[Event] Settings pasted", "source=", tostring(source_key), "dest=", tostring(dest_key))
            copy_roboport_settings(source_key, dest_key)
        end
    end
end

local function on_player_setup_blueprint(event)
    local player = game.get_player(event.player_index)
    local bp
    if player.is_cursor_blueprint() then
        bp = player.cursor_stack
    else
        bp = event.item
    end
    if not (bp and bp.valid_for_read and bp.is_blueprint) then
        return
    end
    local entities = bp.get_blueprint_entities()
    if not entities then
        return
    end
    for i, ent in ipairs(entities) do
        if ent.name == "agricultural-roboport" then
            local surface = player.surface
            local real = surface.find_entity("agricultural-roboport", ent.position)
            if real then
                local settings = storage.agricultural_roboports[real.unit_number] or {}
                local tags = {
                    mode = settings.mode or 0,
                    seed_logistic_only = settings.seed_logistic_only or false,
                    use_filter = settings.use_filter or false,
                    filter_invert = settings.filter_invert or false,
                    circuit_mode_enabled = settings.circuit_mode_enabled or false,
                    circuit_mode_signal = settings.circuit_mode_signal,
                    circuit_filter_enabled = settings.circuit_filter_enabled or false,
                }
                if type(settings.filters) == "table" then
                    tags.filters = {}
                    for j = 1, 5 do tags.filters[j] = settings.filters[j] end
                end
                bp.set_blueprint_entity_tags(i, tags)
            else
                -- Check for ghost at this position
                local ghost = surface.find_entity("entity-ghost", ent.position)
                if ghost and ghost.ghost_name == "agricultural-roboport" then
                    local ghost_key = string.format("ghost_%d_%d_%s", ghost.position.x, ghost.position.y, ghost.surface.name)
                    local settings = storage.agricultural_roboports[ghost_key] or {}
                    local tags = {
                        mode = settings.mode or 0,
                        seed_logistic_only = settings.seed_logistic_only or false,
                        use_filter = settings.use_filter or false,
                        filter_invert = settings.filter_invert or false,
                        circuit_mode_enabled = settings.circuit_mode_enabled or false,
                        circuit_mode_signal = settings.circuit_mode_signal,
                        circuit_filter_enabled = settings.circuit_filter_enabled or false,
                    }
                    if type(settings.filters) == "table" then
                        tags.filters = {}
                        for j = 1, 5 do tags.filters[j] = settings.filters[j] end
                    end
                    bp.set_blueprint_entity_tags(i, tags)
                end
            end
        end
    end
end

-- Unified handler for on_robot_built_entity
local function on_robot_built_entity_dispatch(event)
    local entity = event.entity
    if entity.name:match("^virtual%-.+%-seed$") then
        on_robot_built_virtual_seed(event)
    else
        on_built_event_handler(event)
    end
end

local function on_script_raised_built_entity_dispatch(event)
	local entity = event.entity
	if entity.name:match("^virtual%-.+%-seed$") then
		on_robot_built_virtual_seed(event)
	end
end

-- Helper: Decide and perform actions based on operating mode
process_agricultural_roboport = function(entity, tick)
    if not (entity.energy and entity.energy > 0) then
        return
    end
    if entity.to_be_deconstructed() then
        return
    end
    local settings = storage.agricultural_roboports[entity.unit_number] or {}
    local mode = settings.mode or 0
    local seed_logistic_only = settings.seed_logistic_only or false
    
    -- Circuit network: check if "set operating mode" is enabled in settings
    -- If enabled, read the configured signal value and override mode
    if settings.circuit_mode_enabled and entity.get_control_behavior then
        local control_behavior = entity.get_control_behavior()
        
        if control_behavior then
            -- Get the configured signal to monitor for mode control
            local mode_signal = settings.circuit_mode_signal or {type = "virtual", name = "signal-M"}
            
            if mode_signal and mode_signal.name then
                -- Read signal value from circuit network
                local red_network = entity.get_circuit_network(defines.wire_connector_id.circuit_red)
                local green_network = entity.get_circuit_network(defines.wire_connector_id.circuit_green)
                
                local signal_value = 0
                
                -- Check red network
                if red_network then
                    local signal = red_network.get_signal(mode_signal)
                    if signal then
                        signal_value = signal_value + signal
                    end
                end
                
                -- Check green network
                if green_network then
                    local signal = green_network.get_signal(mode_signal)
                    if signal then
                        signal_value = signal_value + signal
                    end
                end
                
                -- Interpret signal value to determine mode:
                -- negative = harvest only (-1)
                -- zero = both (0)
                -- positive = seed only (1)
                if signal_value < 0 then
                    mode = -1 -- Harvest only
                elseif signal_value > 0 then
                    mode = 1 -- Seed only
                else
                    mode = 0 -- Both
                end
                
                if write_file_log then
                    write_file_log("[CIRCUIT] Operating mode from circuit:", "signal=", mode_signal.name, "value=", signal_value, "mode=", mode)
                end
            end
        end
    end
    
    if entity.status == defines.entity_status.working then
        entity.custom_status = {diode = defines.entity_status_diode.green, label = get_operating_mode_name and get_operating_mode_name(mode) or ""}
    end
    if mode <= 0 then
        if harvest then harvest(entity, tick) end
    end
    if mode >= 0 then
        if seed then seed(entity, seed_logistic_only) end
    end
end

-- =====================
-- Event subscriptions region
-- =====================

-- (TDM handler is implemented in `tdm_tick_handler` above and registered via register_tdm_handler)

-- Note: handler registration occurs during `on_init` to ensure `game` is available for logging

-- Combined dispatch: handle roboport removal and plant harvests without overwriting other handlers
local function on_entity_removed_dispatch(event)
    -- Keep existing roboport removal behavior
    pcall(function() on_remove_agricultural_roboport(event) end)
    
    -- If a plant was removed/mined, attempt to apply stored quality to the harvest buffer
    if event and event.entity and event.entity.valid and event.entity.type == "plant" then
        local inv_buffer = event.buffer
        local harvester_force = nil
        
        -- Try to determine who is harvesting to get their force
        if event.player_index then
            harvester_force = game.players[event.player_index].force
        elseif event.robot and event.robot.valid then
            harvester_force = event.robot.force
        end
        
		if write_file_log then
			write_file_log("[QUALITY] on_entity_removed_dispatch: entity=", event.entity.name, " buffer=", tostring(inv_buffer ~= nil), "robot=", tostring(event.robot ~= nil), "player_index=", tostring(event.player_index), "harvester_force=", harvester_force and harvester_force.name or "nil")
		end
        -- Robots may not provide `event.buffer`; if a robot did the mining, use its cargo inventory
        if (not inv_buffer) and event.robot and event.robot.valid then
            local ok, inv = pcall(function() return event.robot.get_inventory(defines.inventory.robot_cargo) end)
            if ok then inv_buffer = inv end
        end
        pcall(function() harvest_plant(event.entity, inv_buffer, harvester_force) end)
    end
end

-- ========================================================================
-- EVENT SUBSCRIPTIONS (Centralized)
-- ========================================================================

event_subscriptions.register_all({
    tdm = {
        on_runtime_mod_setting_changed = function(event)
            if not event or not event.setting then return end
            if event.setting == "agricultural-roboport-tdm-period" or 
               event.setting == "agricultural-roboport-tdm-tick-interval" then
                tdm.reload_settings()
            end
        end
    },
    roboport = {
        on_script_raised_built = on_script_raised_built_entity_dispatch,
        on_built_entity = on_built_event_handler,
        on_robot_built_entity = on_robot_built_entity_dispatch,
        on_entity_removed = on_entity_removed_dispatch,
        on_entity_settings_pasted = on_entity_settings_pasted,
        on_player_setup_blueprint = on_player_setup_blueprint,
        on_tower_planted_seed = function(event)
            if event and event.plant and event.seed then
                if write_file_log then
                    write_file_log("[QUALITY] on_tower_planted_seed: plant=", event.plant.name, "seed quality=", event.seed.quality and event.seed.quality.name or "nil", "quality level=", event.seed.quality and event.seed.quality.level or "nil")
                end
                pcall(function() register_plant(event.plant, event.seed.quality) end)
            end
        end,
        on_tower_mined_plant = function(event)
            if event and event.plant then
                -- For agricultural towers, the tower's force is the harvester force
                local harvester_force = nil
                if event.tower and event.tower.valid then
                    harvester_force = event.tower.force
                elseif event.robot and event.robot.valid then
                    harvester_force = event.robot.force
                end
                if write_file_log then
                    write_file_log("[QUALITY] on_tower_mined_plant: plant=", event.plant.name, 
                        "has_tower=", tostring(event.tower ~= nil),
                        "has_robot=", tostring(event.robot ~= nil),
                        "harvester_force=", harvester_force and harvester_force.name or "nil")
                end
                pcall(function() harvest_plant(event.plant, event.buffer, harvester_force) end)
            end
        end
    },
    vegetation_planner = vegetation_planner,
    ui = UI,
    deferred_rebuild = handle_deferred_rebuild
})

script.on_configuration_changed(function()
    -- Always rebuild virtual_seed_info on configuration change to pick up new seeds or mod changes
    write_file_log("=== on_configuration_changed() CALLED ===", "Rebuilding virtual_seed_info")
    if Build_virtual_seed_info then
        storage.virtual_seed_info = Build_virtual_seed_info()
        write_file_log("=== on_configuration_changed() COMPLETE ===", "virtual_seed_info rebuilt")
    else
        write_file_log("[ERROR] Build_virtual_seed_info function not available")
    end
    -- Rebuild quality tables to account for mods that add/remove quality tiers
    build_quality_tables()
end)

