local p = plugin.register({
    name = "cliamp-dms-bridge",
    type = "hook",
    version = "0.3.0",
    description = "Owner-only queue controls for the DankMaterialShell CLIAMP widget",
    permissions = {"control"},
})

p:command("snapshot", function()
    return cliamp.json.encode({
        state = cliamp.player.state(),
        position = cliamp.player.position(),
        duration = cliamp.player.duration(),
        volume = cliamp.player.volume(),
        speed = cliamp.player.speed(),
        eq_bands = cliamp.player.eq_bands(),
        mono = cliamp.player.mono(),
        repeat_mode = cliamp.player.repeat_mode(),
        shuffle = cliamp.player.shuffle(),
        current = cliamp.queue.current(),
        queue = cliamp.queue.list(),
    })
end)

p:command("jump", function(args)
    local index = tonumber(args[1])
    if not index then
        return cliamp.json.encode({ok = false, error = "index required"})
    end
    cliamp.queue.jump(index)
    return cliamp.json.encode({ok = true})
end)

p:command("play-radio", function(args)
    local url = args[1]
    if not url or not url:match("^https?://") then
        return cliamp.json.encode({ok = false, error = "http(s) stream URL required"})
    end
    cliamp.queue.add(url)
    -- Queue counts can be stale in either direction. The DMS client resolves
    -- the appended item by its exact URL from a fresh snapshot, then jumps.
    return cliamp.json.encode({ok = true, url = url, selection_version = 3})
end)
