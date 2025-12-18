-- Time-Division Multiplexing (TDM) system for agricultural roboports
-- Distributes processing across multiple ticks to avoid lag spikes

local tdm = {}

-- TDM configuration: read from runtime-global settings (fall back to defaults)
local DEFAULT_TDM_PERIOD = 300 -- ticks (5 seconds)
local DEFAULT_TDM_TICK_INTERVAL = 10 -- how often (in ticks) we wake to process a batch

local function read_tdm_settings()
    -- Use the Factorio 2.0+ `settings` global directly
    if settings and settings.global then
        local p = settings.global["agricultural-roboport-tdm-period"]
        local ti = settings.global["agricultural-roboport-tdm-tick-interval"]
        return (p and p.value) or DEFAULT_TDM_PERIOD, (ti and ti.value) or DEFAULT_TDM_TICK_INTERVAL
    end
    return DEFAULT_TDM_PERIOD, DEFAULT_TDM_TICK_INTERVAL
end

tdm.TDM_PERIOD, tdm.TDM_TICK_INTERVAL = read_tdm_settings()

-- TDM runtime state is stored under storage._tdm. Fields:
--   version: increments whenever the roboport list changes
--   snapshot_version: version when keys snapshot was built
--   keys: immutable snapshot array of numeric keys used for current processing
--   next_index: 1-based index in keys for the next batch start
--   registered_interval: interval currently registered with script.on_nth_tick
function tdm.mark_dirty()
    storage._tdm = storage._tdm or {}
    storage._tdm.version = (storage._tdm.version or 0) + 1
end

-- The actual TDM tick handler
function tdm.tick_handler(event, process_fn)
    local process_agricultural_roboport = process_fn
    
    -- Ensure required _tdm fields exist (some code paths may have created an empty table)
    storage._tdm = storage._tdm or {}
    storage._tdm.version = storage._tdm.version or 0
    storage._tdm.snapshot_version = storage._tdm.snapshot_version or 0
    storage._tdm.keys = storage._tdm.keys or {}
    storage._tdm.next_index = storage._tdm.next_index or 1

    -- Rebuild immutable snapshot of numeric keys if storage changed since last snapshot
    if storage._tdm.snapshot_version ~= storage._tdm.version then
        local keys = {}
        for k, _ in pairs(storage.agricultural_roboports) do
            if type(k) == "number" then table.insert(keys, k) end
        end
        table.sort(keys)
        storage._tdm.keys = keys
        storage._tdm.snapshot_version = storage._tdm.version
        -- clamp next_index
        if storage._tdm.next_index < 1 then storage._tdm.next_index = 1 end
        if storage._tdm.next_index > #keys then storage._tdm.next_index = 1 end
        if write_file_log then
            write_file_log("[TDM] Snapshot rebuilt", "total_keys=", #keys, "keys=", serpent and serpent.line and serpent.line(keys) or tostring(keys))
        end
    end

    local keys = storage._tdm.keys or {}
    local total = #keys
    if total == 0 then
        return
    end

    local calls_per_period = math.max(1, math.floor(tdm.TDM_PERIOD / tdm.TDM_TICK_INTERVAL))
    local batch_size = math.max(1, math.ceil(total / calls_per_period))

    local processed = 0
    local idx = storage._tdm.next_index or 1
    for i = 1, batch_size do
        local key = keys[idx]
        idx = idx + 1
        if key ~= nil then
            -- Resolve entity by stored surface/position if present, otherwise try unit_number lookup
            local settings = storage.agricultural_roboports[key]
            if type(key) == "number" and settings then
                local entity = nil
                -- ALWAYS try to resolve by unit_number first (most reliable for quality entities)
                if game.get_entity_by_unit_number then
                    entity = game.get_entity_by_unit_number(key)
                    if write_file_log and entity then
                        write_file_log("[TDM] Found entity by unit_number", "key=", key, "name=", entity.name, "quality=", entity.quality and entity.quality.name or "normal")
                    elseif write_file_log then
                        write_file_log("[TDM] Unit_number lookup failed", "key=", key, "has_position=", tostring(settings.position ~= nil))
                    end
                end
                
                -- Validate that it's actually an agricultural roboport and update position if needed
                if entity and entity.valid and entity.name == "agricultural-roboport" then
                    -- Update stored position if it's missing or changed
                    if not settings.surface or not settings.position then
                        settings.surface = entity.surface.name
                        settings.position = { x = entity.position.x, y = entity.position.y }
                        if write_file_log then
                            write_file_log("[TDM] Updated missing position", "key=", key)
                        end
                    end
                    -- Process the roboport
                    if process_agricultural_roboport then
                        process_agricultural_roboport(entity, event.tick)
                    end
                    processed = processed + 1
                else
                    -- Entity not found by unit_number, try position-based lookup as fallback
                    if settings.surface and settings.position then
                        local surface = game.surfaces and game.surfaces[settings.surface]
                        if surface then
                            -- Use find_entities_filtered with radius to find entities at this position (any quality)
                            local entities = surface.find_entities_filtered{
                                name = "agricultural-roboport",
                                position = settings.position,
                                radius = 0.5
                            }
                            
                            -- Look for entity with matching unit_number
                            local found = false
                            for _, e in ipairs(entities) do
                                if e.unit_number == key then
                                    entity = e
                                    found = true
                                    if write_file_log then
                                        write_file_log("[TDM] Found by position (quality-aware)", "key=", key, "quality=", e.quality and e.quality.name or "normal")
                                    end
                                    if process_agricultural_roboport then
                                        process_agricultural_roboport(entity, event.tick)
                                    end
                                    processed = processed + 1
                                    break
                                end
                            end
                            
                            if not found then
                                -- Couldn't locate entity; remove stale entry
                                if write_file_log then
                                    write_file_log("[TDM] REMOVING: not found by position", "key=", key, "pos=", serpent and serpent.line and serpent.line(settings.position) or "?", "entities_at_pos=", #entities)
                                end
                                storage.agricultural_roboports[key] = nil
                                storage._tdm.version = (storage._tdm.version or 0) + 1
                            end
                        else
                            -- Surface doesn't exist, remove stale entry
                            if write_file_log then
                                write_file_log("[TDM] REMOVING: surface not found", "key=", key, "surface=", settings.surface or "nil")
                            end
                            storage.agricultural_roboports[key] = nil
                            storage._tdm.version = (storage._tdm.version or 0) + 1
                        end
                    else
                        -- No position info and entity not found, remove stale entry
                        if write_file_log then
                            write_file_log("[TDM] REMOVING: no position and unit_number failed", "key=", key)
                        end
                        storage.agricultural_roboports[key] = nil
                        storage._tdm.version = (storage._tdm.version or 0) + 1
                    end
                end
            end
        end
        if idx > total then idx = 1 end
    end
    storage._tdm.next_index = idx
end

-- Helper to (re)register the nth-tick handler when the desired tick interval changes.
function tdm.register_handler(interval, process_fn)
    storage._tdm = storage._tdm or {}
    -- Unregister previous interval handler (if any)
    if storage._tdm.registered_interval and storage._tdm.registered_interval ~= interval then
        script.on_nth_tick(storage._tdm.registered_interval, nil)
    end
    
    -- Store process function globally so it can be accessed by the handler
    if not _G.process_agricultural_roboport and process_fn then
        _G.process_agricultural_roboport = process_fn
    end
    
    -- Register the handler for the new interval
    script.on_nth_tick(interval, function(event)
        -- Use global process function
        tdm.tick_handler(event, _G.process_agricultural_roboport)
    end)
    storage._tdm.registered_interval = interval
end

-- Re-read settings and re-register handler
function tdm.reload_settings()
    tdm.TDM_PERIOD, tdm.TDM_TICK_INTERVAL = read_tdm_settings()
    tdm.register_handler(tdm.TDM_TICK_INTERVAL)
end

return tdm
