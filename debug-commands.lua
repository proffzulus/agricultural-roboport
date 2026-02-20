-- Debug console commands for agricultural-roboport mod
-- These commands can be run in the Factorio console to inspect entities and debug issues
commands.add_command("agro-roboports-dump", "Dump agricultural_roboports storage table", function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    
    if not storage or not storage.agricultural_roboports then
        player.print("[color=red]No agricultural_roboports in storage![/color]")
        return
    end
    
    player.print("=== Storage.agricultural_roboports ===")
    
    -- Check metatable
    local mt = getmetatable(storage.agricultural_roboports)
    if mt then
        player.print("Metatable: EXISTS")
        if mt.__index then
            player.print("  __index: " .. type(mt.__index))
        end
    else
        player.print("Metatable: [color=yellow]nil[/color]")
    end
    
    -- Count entries by type
    local numeric_count = 0
    local ghost_count = 0
    local other_count = 0
    
    local numeric_keys = {}
    local ghost_keys = {}
    local other_keys = {}
    
    for key, value in pairs(storage.agricultural_roboports) do
        if type(key) == "number" then
            numeric_count = numeric_count + 1
            table.insert(numeric_keys, key)
        elseif type(key) == "string" and key:match("^ghost_") then
            ghost_count = ghost_count + 1
            table.insert(ghost_keys, key)
        else
            other_count = other_count + 1
            table.insert(other_keys, key)
        end
    end
    
    player.print(string.format("\nTotal entries: %d", numeric_count + ghost_count + other_count))
    player.print(string.format("  Numeric keys (roboports): %d", numeric_count))
    player.print(string.format("  Ghost keys: %d", ghost_count))
    player.print(string.format("  Other keys: %d", other_count))
    
    -- Show numeric entries (roboports)
    if numeric_count > 0 then
        player.print("\n=== Roboport Entries (unit_number) ===")
        table.sort(numeric_keys)
        for i, key in ipairs(numeric_keys) do
            if i <= 10 then -- Show first 10
                local settings = storage.agricultural_roboports[key]
                player.print(string.format("[%d] unit=%d mode=%s surface=%s pos={%.1f,%.1f}",
                    i, key,
                    tostring(settings.mode or "nil"),
                    tostring(settings.surface or "nil"),
                    settings.position and settings.position.x or 0,
                    settings.position and settings.position.y or 0))
            end
        end
        if numeric_count > 10 then
            player.print(string.format("  ... and %d more", numeric_count - 10))
        end
    end
    
    -- Show ghost entries
    if ghost_count > 0 then
        player.print("\n=== Ghost Entries ===")
        table.sort(ghost_keys)
        for i, key in ipairs(ghost_keys) do
            if i <= 10 then -- Show first 10
                local settings = storage.agricultural_roboports[key]
                player.print(string.format("[%d] key=%s mode=%s",
                    i, key, tostring(settings.mode or "nil")))
            end
        end
        if ghost_count > 10 then
            player.print(string.format("  ... and %d more", ghost_count - 10))
        end
    end
    
    -- Show other entries
    if other_count > 0 then
        player.print("\n=== Other Entries ===")
        for i, key in ipairs(other_keys) do
            local settings = storage.agricultural_roboports[key]
            player.print(string.format("[%d] key=%s (%s) value=%s",
                i, tostring(key), type(key), serpent.line(settings)))
        end
    end
    
    -- Test metatable behavior
    player.print("\n=== Metatable Test ===")
    local test_key = "test_nonexistent_key_12345"
    local test_value = storage.agricultural_roboports[test_key]
    if test_value then
        player.print("Accessing nonexistent key returns: " .. serpent.line(test_value))
        player.print("[color=yellow]WARNING: Metatable __index is creating default values![/color]")
    else
        player.print("Accessing nonexistent key returns: nil (correct)")
    end
end)

commands.add_command("agro-rebuild-seed-info", "Rebuild virtual_seed_info storage", function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    
    player.print("[color=yellow]Rebuilding virtual_seed_info...[/color]")
    
    -- Clear existing info
    storage.virtual_seed_info = nil
    
    -- Rebuild using the Build_virtual_seed_info function
    if Build_virtual_seed_info then
        storage.virtual_seed_info = Build_virtual_seed_info()
        
        -- Count entries
        local count = 0
        if storage.virtual_seed_info then
            for _ in pairs(storage.virtual_seed_info) do
                count = count + 1
            end
        end
        
        player.print(string.format("[color=green]Rebuilt virtual_seed_info with %d entries[/color]", count))
        
        -- Show sample entries
        if count > 0 then
            player.print("\n=== Sample Entries ===")
            local shown = 0
            for seed_name, info in pairs(storage.virtual_seed_info) do
                if shown < 5 then
                    player.print(string.format("  %s: plant=%s has_tile_restriction=%s",
                        seed_name,
                        info.plant_proto and info.plant_proto.name or "nil",
                        tostring(info.tile_restriction ~= nil)))
                    shown = shown + 1
                end
            end
            if count > 5 then
                player.print(string.format("  ... and %d more", count - 5))
            end
        end
    else
        player.print("[color=red]Build_virtual_seed_info function not found![/color]")
    end
end)

commands.add_command("agro-seed-info", "Show detailed plant info for the seed item in hand", function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    
    local cursor_stack = player.cursor_stack
    if not cursor_stack or not cursor_stack.valid_for_read then
        player.print("[color=yellow]No item in hand! Hold a seed item and run this command.[/color]")
        return
    end
    
    local seed_item = cursor_stack.name
    local seed_proto = prototypes.item[seed_item]
    
    if not seed_proto or not seed_proto.plant_result then
        player.print("[color=yellow]Item '" .. seed_item .. "' is not a seed (no plant_result)![/color]")
        return
    end
    
    -- Get plant prototype
    local plant_ref = seed_proto.plant_result
    local plant_name = type(plant_ref) == "string" and plant_ref or (plant_ref.name or "unknown")
    local plant_proto = prototypes.entity[plant_name]
    
    if not plant_proto then
        player.print("[color=red]Plant entity '" .. tostring(plant_name) .. "' not found![/color]")
        return
    end
    
    -- Output to screen
    player.print("=== SEED INFO: " .. seed_item .. " ===")
    player.print("Plant: " .. plant_name)
    player.print("")
    
    -- Collision boxes
    player.print("=== Collision Info ===")
    local ok_cb, cb = pcall(function() return plant_proto.collision_box end)
    if ok_cb and cb then
        if type(cb) == "table" and cb[1] and cb[2] and type(cb[1]) == "table" and type(cb[2]) == "table" then
            player.print(string.format("  collision_box: {{%.2f, %.2f}, {%.2f, %.2f}}", 
                cb[1][1] or 0, cb[1][2] or 0, cb[2][1] or 0, cb[2][2] or 0))
            local width = (cb[2][1] or 0) - (cb[1][1] or 0)
            local height = (cb[2][2] or 0) - (cb[1][2] or 0)
            player.print(string.format("  size: %.2f x %.2f tiles", width, height))
        else
            player.print("  collision_box: " .. serpent.line(cb))
        end
    else
        player.print("  collision_box: [color=yellow]nil[/color]")
    end
    
    local ok_sb, sb = pcall(function() return plant_proto.selection_box end)
    if ok_sb and sb then
        if type(sb) == "table" and sb[1] and sb[2] and type(sb[1]) == "table" and type(sb[2]) == "table" then
            player.print(string.format("  selection_box: {{%.2f, %.2f}, {%.2f, %.2f}}", 
                sb[1][1] or 0, sb[1][2] or 0, sb[2][1] or 0, sb[2][2] or 0))
        else
            player.print("  selection_box: " .. serpent.line(sb))
        end
    else
        player.print("  selection_box: [color=yellow]nil[/color]")
    end
    
    local ok_mgb, mgb = pcall(function() return plant_proto.map_generator_bounding_box end)
    if ok_mgb and mgb then
        if type(mgb) == "table" and mgb[1] and mgb[2] and type(mgb[1]) == "table" and type(mgb[2]) == "table" then
            player.print(string.format("  map_generator_bounding_box: {{%.2f, %.2f}, {%.2f, %.2f}}", 
                mgb[1][1] or 0, mgb[1][2] or 0, mgb[2][1] or 0, mgb[2][2] or 0))
        else
            player.print("  map_generator_bounding_box: " .. serpent.line(mgb))
        end
    end
    
    -- Collision mask
    player.print("")
    player.print("=== Collision Mask ===")
    local ok_cm, cm = pcall(function() return plant_proto.collision_mask end)
    if ok_cm and cm and cm.layers then
        local layers = cm.layers
        local layer_list = {}
        for layer_name, enabled in pairs(layers) do
            if enabled then
                table.insert(layer_list, layer_name)
            end
        end
        if #layer_list > 0 then
            table.sort(layer_list)
            player.print("  Layers: " .. table.concat(layer_list, ", "))
        else
            player.print("  Layers: [color=yellow]none[/color]")
        end
    else
        player.print("  [color=yellow]No collision mask[/color]")
    end
    
    -- Tile restrictions (autoplace)
    player.print("")
    player.print("=== Tile Restrictions ===")
    local ok_ap, ap = pcall(function() return plant_proto.autoplace end)
    if ok_ap and ap and ap.tile_restriction then
        local restrictions = ap.tile_restriction
        local tile_list = {}
        for _, tile in pairs(restrictions) do
            if type(tile) == "table" and tile.first then
                table.insert(tile_list, tile.first)
            elseif type(tile) == "string" then
                table.insert(tile_list, tile)
            end
        end
        if #tile_list > 0 then
            player.print("  Allowed tiles: " .. table.concat(tile_list, ", "))
        else
            player.print("  [color=yellow]Empty tile restriction list[/color]")
        end
    else
        player.print("  [color=green]No tile restrictions (can plant anywhere)[/color]")
    end
    
    -- Tile buildability rules
    local ok_tbr, tbr = pcall(function() return plant_proto.tile_buildability_rules end)
    if ok_tbr and tbr then
        player.print("")
        player.print("=== Tile Buildability Rules ===")
        local ok_count, count = pcall(function() return #tbr end)
        player.print("  Rule count: " .. (ok_count and count or "unknown"))
        for idx, rule in pairs(tbr) do
            player.print("  Rule " .. idx .. ":")
            if rule.required_tiles then
                if rule.required_tiles.tiles then
                    local tiles = {}
                    for _, t in pairs(rule.required_tiles.tiles) do
                        local tile_name = type(t) == "table" and t.first or t
                        table.insert(tiles, tile_name)
                    end
                    player.print("    required_tiles: " .. table.concat(tiles, ", "))
                end
                if rule.required_tiles.layers then
                    local layers = {}
                    for layer, enabled in pairs(rule.required_tiles.layers) do
                        if enabled then table.insert(layers, layer) end
                    end
                    if #layers > 0 then
                        player.print("    required_layers: " .. table.concat(layers, ", "))
                    end
                end
            end
            if rule.colliding_tiles then
                if rule.colliding_tiles.tiles then
                    local tiles = {}
                    for _, t in pairs(rule.colliding_tiles.tiles) do
                        local tile_name = type(t) == "table" and t.first or t
                        table.insert(tiles, tile_name)
                    end
                    player.print("    colliding_tiles: " .. table.concat(tiles, ", "))
                end
                if rule.colliding_tiles.layers then
                    local layers = {}
                    for layer, enabled in pairs(rule.colliding_tiles.layers) do
                        if enabled then table.insert(layers, layer) end
                    end
                    if #layers > 0 then
                        player.print("    colliding_layers: " .. table.concat(layers, ", "))
                    end
                end
            end
            if rule.remove_on_collision ~= nil then
                player.print("    remove_on_collision: " .. tostring(rule.remove_on_collision))
            end
        end
    end
    
    -- Surface conditions
    local ok_sc, sc = pcall(function() return plant_proto.surface_conditions end)
    if ok_sc and sc then
        player.print("")
        player.print("=== Surface Conditions ===")
        for idx, condition in pairs(sc) do
            local min_str = condition.min and string.format("%.2f", condition.min) or "unbounded"
            local max_str = condition.max and string.format("%.2f", condition.max) or "unbounded"
            player.print(string.format("  %s: [%s, %s]", condition.property, min_str, max_str))
        end
    end
    
    -- Other relevant properties
    player.print("")
    player.print("=== Other Properties ===")
    local ok_type, ptype = pcall(function() return plant_proto.type end)
    player.print("  Type: " .. (ok_type and ptype or "unknown"))
    local ok_gt, growth_ticks = pcall(function() return plant_proto.growth_ticks end)
    if ok_gt and growth_ticks then
        player.print("  Growth ticks: " .. growth_ticks)
    end
    local ok_flags, flags_data = pcall(function() return plant_proto.flags end)
    if ok_flags and flags_data then
        local flags = {}
        for flag_name, flag_value in pairs(flags_data) do
            if flag_value then
                table.insert(flags, flag_name)
            end
        end
        if #flags > 0 then
            player.print("  Flags: " .. table.concat(flags, ", "))
        end
    end
    
    -- Output to file log if enabled
    if write_file_log then
        write_file_log("=== SEED INFO: " .. seed_item .. " ===")
        write_file_log("Plant:", plant_name)
        local ok_cb_log, cb_log = pcall(function() return plant_proto.collision_box end)
        if ok_cb_log and cb_log then
            write_file_log("collision_box:", serpent.line(cb_log))
        end
        local ok_sb_log, sb_log = pcall(function() return plant_proto.selection_box end)
        if ok_sb_log and sb_log then
            write_file_log("selection_box:", serpent.line(sb_log))
        end
        local ok_cm_log, cm_log = pcall(function() return plant_proto.collision_mask end)
        if ok_cm_log and cm_log then
            write_file_log("collision_mask:", serpent.line(cm_log))
        end
        local ok_ap_log, ap_log = pcall(function() return plant_proto.autoplace end)
        if ok_ap_log and ap_log and ap_log.tile_restriction then
            write_file_log("tile_restriction:", serpent.line(ap_log.tile_restriction))
        end
        local ok_tbr_log, tbr_log = pcall(function() return plant_proto.tile_buildability_rules end)
        if ok_tbr_log and tbr_log then
            write_file_log("tile_buildability_rules:", serpent.block(tbr_log))
        end
        local ok_sc_log, sc_log = pcall(function() return plant_proto.surface_conditions end)
        if ok_sc_log and sc_log then
            write_file_log("surface_conditions:", serpent.block(sc_log))
        end
        write_file_log("=== END SEED INFO ===")
    end
end)
commands.add_command("agro-quality-table-dump", "Dump quality tables (storage.quality_by_level, quality_level, etc.)", function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    
    player.print("=== QUALITY TABLE DUMP ===")
    
    -- Basic info
    if not storage then
        player.print("[color=red]storage is nil![/color]")
        if write_file_log then write_file_log("[QUALITY DUMP] storage is nil!") end
        return
    end
    
    player.print("storage.quality_tables_version: " .. tostring(storage.quality_tables_version or "nil"))
    player.print("storage.max_quality_level: " .. tostring(storage.max_quality_level or "nil"))
    
    if write_file_log then
        write_file_log("=== QUALITY TABLE DUMP ===")
        write_file_log("storage.quality_tables_version:", tostring(storage.quality_tables_version or "nil"))
        write_file_log("storage.max_quality_level:", tostring(storage.max_quality_level or "nil"))
    end
    
    -- Dump quality_by_level table (tier -> name)
    player.print("\n=== storage.quality_by_level (tier -> name) ===")
    if write_file_log then write_file_log("\n=== storage.quality_by_level (tier -> name) ===") end
    
    if not storage.quality_by_level then
        player.print("[color=yellow]quality_by_level is nil![/color]")
        if write_file_log then write_file_log("quality_by_level is nil!") end
    else
        -- Count entries
        local count = 0
        for _ in pairs(storage.quality_by_level) do count = count + 1 end
        player.print("Entries: " .. count)
        if write_file_log then write_file_log("Entries:", count) end
        
        -- Sort keys numerically
        local keys = {}
        for k in pairs(storage.quality_by_level) do
            table.insert(keys, k)
        end
        table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
        
        -- Display all entries
        for _, tier in ipairs(keys) do
            local name = storage.quality_by_level[tier]
            local line = string.format("  [%s] -> %s", tostring(tier), tostring(name))
            player.print(line)
            if write_file_log then write_file_log(line) end
        end
    end
    
    -- Dump quality_level table (name -> tier)
    player.print("\n=== storage.quality_level (name -> tier) ===")
    if write_file_log then write_file_log("\n=== storage.quality_level (name -> tier) ===") end
    
    if not storage.quality_level then
        player.print("[color=yellow]quality_level is nil![/color]")
        if write_file_log then write_file_log("quality_level is nil!") end
    else
        -- Count entries
        local count = 0
        for _ in pairs(storage.quality_level) do count = count + 1 end
        player.print("Entries: " .. count)
        if write_file_log then write_file_log("Entries:", count) end
        
        -- Sort keys alphabetically
        local keys = {}
        for k in pairs(storage.quality_level) do
            table.insert(keys, k)
        end
        table.sort(keys)
        
        -- Display all entries
        for _, name in ipairs(keys) do
            local tier = storage.quality_level[name]
            local line = string.format("  '%s' -> %s", name, tostring(tier))
            player.print(line)
            if write_file_log then write_file_log(line) end
        end
    end
    
    -- Check prototypes.quality for comparison
    player.print("\n=== prototypes.quality (for comparison) ===")
    if write_file_log then write_file_log("\n=== prototypes.quality (for comparison) ===") end
    
    if prototypes and prototypes.quality then
        -- Build sorted list
        local qualities = {}
        for name, quality_proto in pairs(prototypes.quality) do
            table.insert(qualities, {
                name = name,
                level = quality_proto.level
            })
        end
        table.sort(qualities, function(a, b) return a.level < b.level end)
        
        player.print("Total quality prototypes: " .. #qualities)
        if write_file_log then write_file_log("Total quality prototypes:", #qualities) end
        
        for i, q in ipairs(qualities) do
            local line = string.format("  [%d] level=%s name='%s'", i-1, tostring(q.level), q.name)
            player.print(line)
            if write_file_log then write_file_log(line) end
        end
    else
        player.print("[color=red]prototypes.quality not available![/color]")
        if write_file_log then write_file_log("prototypes.quality not available!") end
    end
    
    player.print("\n=== END QUALITY TABLE DUMP ===")
    if write_file_log then write_file_log("=== END QUALITY TABLE DUMP ===") end
end)