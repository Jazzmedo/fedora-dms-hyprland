.pragma library

function safeJson(text, fallback) {
    try {
        return JSON.parse(text)
    } catch (error) {
        return fallback
    }
}

function normalizedStatus(value) {
    var data = typeof value === "string" ? safeJson(value, null) : value
    if (!data || data.ok === false)
        return null
    var track = data.track || {}
    return {
        state: data.state || "stopped",
        title: track.title || "Nothing playing",
        artist: track.artist || "",
        album: track.album || "",
        path: track.path || "",
        artUrl: track.album_art_url || track.albumArtUrl || track.art_url || track.artUrl || "",
        position: Number(data.position || 0),
        duration: Number(data.duration || 0),
        volume: Number(data.volume || 0),
        index: Number(data.index || 0),
        total: Number(data.total || 0),
        playlist: data.playlist || "",
        shuffle: Boolean(data.shuffle),
        repeat: String(data.repeat || "off").toLowerCase(),
        mono: Boolean(data.mono),
        speed: Number(data.speed || 1),
        eqPreset: data.eq_preset || data.eqPreset || "Flat",
        eqBands: Array.isArray(data.eq_bands) ? data.eq_bands.slice(0, 10).map(function(value) { return Number(value || 0) }) : [],
        visualizer: data.visualizer || "",
        device: data.device || ""
    }
}

function parseEqPresets(value) {
    var parsed = typeof value === "string" ? safeJson(value, []) : value
    if (!Array.isArray(parsed))
        return []
    return parsed.map(function(item) {
        if (!item || typeof item.name !== "string" || !Array.isArray(item.bands) || item.bands.length !== 10)
            return null
        var name = item.name.trim().slice(0, 24)
        if (!name)
            return null
        return {
            name: name,
            builtin: false,
            bands: item.bands.map(function(value) {
                return Math.max(-12, Math.min(12, Number(value || 0)))
            })
        }
    }).filter(function(item) { return item !== null })
}

function lines(text) {
    return String(text || "").split(/\r?\n/).map(function(line) {
        return line.replace(/^\s*[>*]?\s*/, "").trim()
    }).filter(function(line) {
        return line.length > 0 && line.indexOf("cliamp not running") < 0
    })
}

function providerLines(text) {
    return lines(text).map(function(line) {
        var parts = line.split("|")
        return { id: parts[0], configured: parts[1] === "1" }
    })
}

function playlistLines(text) {
    return lines(text).filter(function(line) {
        return line.indexOf("No playlists found") < 0
    }).map(function(line) {
        var parenthesized = line.match(/^(.*?)\s+\((?:\d+\s+)?tracks?\)$/i)
        if (parenthesized)
            return parenthesized[1].trim()
        var columns = line.match(/^(.*?)\s+\d+\s+tracks?$/i)
        return columns ? columns[1].trim() : line
    })
}

function deviceLines(text) {
    return String(text || "").split(/\r?\n/).map(function(line) {
        var trimmed = line.trim()
        if (!trimmed || trimmed === "No audio output devices found.")
            return null
        var active = /^\*/.test(trimmed)
        trimmed = trimmed.replace(/^\*\s*/, "")
        var fields = trimmed.split(/\s{2,}/)
        return {
            label: fields.length > 1 ? fields.slice(0, -1).join(" ") : trimmed,
            name: fields.length > 1 ? fields[fields.length - 1] : trimmed,
            active: active
        }
    }).filter(function(item) { return item !== null })
}

function normalizeStation(raw) {
    if (!raw)
        return null
    var url = raw.url_resolved || raw.url || ""
    if (!url)
        return null
    return {
        uuid: raw.stationuuid || url,
        name: raw.name || "Unknown station",
        url: url,
        favicon: raw.favicon || "",
        country: raw.country || "",
        language: raw.language || "",
        codec: raw.codec || "",
        bitrate: Number(raw.bitrate || 0),
        tags: raw.tags || ""
    }
}

function normalizeStations(text) {
    var raw = safeJson(text, [])
    if (!Array.isArray(raw))
        return []
    var seen = {}
    return raw.map(normalizeStation).filter(function(station) {
        if (!station || seen[station.uuid])
            return false
        seen[station.uuid] = true
        return true
    })
}

function mergeStations(primary, secondary) {
    var seen = {}
    return (primary || []).concat(secondary || []).filter(function(station) {
        if (!station)
            return false
        var key = String(station.uuid || station.url || "")
        if (!key || seen[key])
            return false
        seen[key] = true
        return true
    })
}

function upsertRecent(items, station, limit) {
    var result = [station]
    ;(items || []).forEach(function(item) {
        if (item.uuid !== station.uuid && result.length < limit)
            result.push(item)
    })
    return result
}

function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds || 0)))
    var mins = Math.floor(value / 60)
    var secs = value % 60
    return mins + ":" + (secs < 10 ? "0" : "") + secs
}
