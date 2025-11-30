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

