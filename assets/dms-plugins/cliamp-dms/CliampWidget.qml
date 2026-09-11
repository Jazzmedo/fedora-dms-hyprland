import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets
import "./components"
import "Logic.js" as Logic

PluginComponent {
    id: root

    property bool online: false
    property bool launching: false
    property int launchProbeAttempts: 0
    property bool polling: false
    property bool bridgeReady: false
    // Assume a bridge from a previous widget instance may still own the bus name.
    property bool mprisBridgeActive: true
    property bool popoutVisible: false
    property string selectedTab: "playing"
    property string lastError: ""
    property var player: ({
        state: "stopped", title: "CLIAMP is offline", artist: "", album: "", path: "", artUrl: "",
        position: 0, duration: 0, volume: 0, index: 0, total: 0, playlist: "", shuffle: false,
        repeat: "off", mono: false, speed: 1, eqPreset: "Flat", eqBands: [], visualizer: "", device: ""
    })
    property var queueItems: []
    property var playlists: []
    property var devices: []
    property var visualizers: []
    property var providers: []
    property var trackSearchProviders: []
    property string trackSearchProvider: "youtube-fallback"
    property var trackSearchResults: []
    property bool trackSearchLoading: false
    property string trackSearchError: ""
    property var eqBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property var spectrumBands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string activeEqPreset: "Flat"
    property var radioResults: []
    property var radioFavorites: []
    property var radioRecents: []
    property string radioMode: "results"
    property bool radioLoading: false
    property string radioError: ""
    property var pendingRadioStation: null
    property int radioSelectionAttempts: 0
    property string metadataKey: ""
    property var enrichedMetadata: ({})
    property string streamMetadataPath: ""
    property var streamMetadata: ({})
    property string stationMetadataKey: ""
    property string detectedStationName: ""
    property string radioTimingPath: ""
    property string radioTimingKey: ""
    property double radioSongStartedMs: 0
    property bool radioSongTimingActive: false
    property bool radioPositionResetPending: false
    property int mprisTrackSerial: 1
    property var playbackPreferences: ({})
    property bool preferencesApplied: false
    property real pendingVolumeDb: -12
    property int requestSerial: 0
    readonly property string processNamespace: "cliampDms." + Date.now() + "." + Math.floor(Math.random() * 1000000000)
    property string lastMprisPayload: ""

    readonly property string helperPath: localPath(Qt.resolvedUrl("scripts/cliamp-dms-helper"))
    readonly property string cliampPath: localPath(Qt.resolvedUrl("scripts/cliamp-dms-cli"))
    readonly property string bridgePath: localPath(Qt.resolvedUrl("cliamp/cliamp-dms-bridge.lua"))
    readonly property string mprisBridgePath: localPath(Qt.resolvedUrl("scripts/cliamp-dms-mpris"))
    readonly property var cliampMprisPlayer: Mpris.players.values.find(candidate => String(candidate.identity || "").toLowerCase() === "cliamp" && String(candidate.desktopEntry || "").toLowerCase() !== "cliamp-dms") || null
    readonly property bool isPlaying: online && player.state === "playing"
    readonly property int closedPollMs: Math.max(1000, Number(pluginData.closedPollMs || 3000))
    readonly property int openPollMs: Math.max(500, Number(pluginData.openPollMs || 1000))
    readonly property real mprisLatencyCompensation: Math.max(0, Math.min(10,
        Number(pluginData.mprisLatencyCompensationMs ?? (Number(pluginData.mprisLatencyCompensation ?? 2.5) * 1000)) / 1000))
    readonly property int maxTitleWidth: Math.max(80, Number(pluginData.maxTitleWidth || 180))
    readonly property string barPreviewMode: ["icon", "track", "stationTrack"].indexOf(String(pluginData.barPreviewMode || "icon")) >= 0 ? String(pluginData.barPreviewMode || "icon") : "icon"
    readonly property int compactControlSize: 36
    readonly property real volumeMinDb: -50
    readonly property real volumeMaxDb: 6
    readonly property bool percentageVolume: String(pluginData.volumeDisplayMode || "db") === "percent"
    readonly property bool visualizerEnabled: pluginData.showVisualizer !== false
    readonly property int visualizerHeight: Math.max(48, Math.min(140, Number(pluginData.visualizerHeight || 88)))
    readonly property int visualizerFps: Math.max(5, Math.min(30, Number(pluginData.visualizerFps || 20)))
    readonly property bool visualizerShouldRun: visualizerEnabled && popoutVisible && selectedTab === "playing" && online
    readonly property var builtInVisualizers: ["Bars", "BarsDot", "Rain", "BarsOutline", "Bricks", "Columns", "ClassicPeak", "Wave", "Scatter", "Flame", "Retro", "Pulse"]
    readonly property var cliampStations: [
        {uuid: "cliamp-lofi", name: "Lofi Stream", url: "https://radio.cliamp.stream/lofi/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "lofi chill"},
        {uuid: "cliamp-synthwave", name: "Synthwave Stream", url: "https://radio.cliamp.stream/synthwave/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "synthwave"},
        {uuid: "cliamp-edm", name: "EDM Stream", url: "https://radio.cliamp.stream/edm/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "edm electronic"},
        {uuid: "cliamp-ncs", name: "NCS Stream", url: "https://radio.cliamp.stream/ncs/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "ncs"},
        {uuid: "cliamp-ncs-house", name: "NCS House Stream", url: "https://radio.cliamp.stream/ncs-house/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "ncs house"},
        {uuid: "cliamp-ncs-dubstep", name: "NCS Dubstep Stream", url: "https://radio.cliamp.stream/ncs-dubstep/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "ncs dubstep"},
        {uuid: "cliamp-ncs-dnb", name: "NCS Drum & Bass Stream", url: "https://radio.cliamp.stream/ncs-dnb/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "ncs drum bass dnb"},
        {uuid: "cliamp-ncs-trap", name: "NCS Trap Stream", url: "https://radio.cliamp.stream/ncs-trap/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "ncs trap"},
        {uuid: "cliamp-ncs-phonk", name: "NCS Phonk Stream", url: "https://radio.cliamp.stream/ncs-phonk/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "ncs phonk"},
        {uuid: "cliamp-ncs-pop", name: "NCS Pop Stream", url: "https://radio.cliamp.stream/ncs-pop/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "ncs pop"},
        {uuid: "cliamp-ncs-chill", name: "NCS Chill Stream", url: "https://radio.cliamp.stream/ncs-chill/stream", favicon: "", country: "CLIAMP", language: "", codec: "MP3", bitrate: 0, tags: "ncs chill"}
    ]
    readonly property string effectiveVisualizer: pluginData.launchInBackground === true
        ? String(playbackPreferences.visualizer || pluginData.defaultVisualizer || "Bars")
        : String(player.visualizer || playbackPreferences.visualizer || pluginData.defaultVisualizer || "Bars")
    readonly property var builtInEqPresets: [
        {name: "Flat", builtin: true, bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]},
        {name: "Rock", builtin: true, bands: []},
        {name: "Pop", builtin: true, bands: []},
        {name: "Jazz", builtin: true, bands: []},
        {name: "Bass Boost", builtin: false, bands: [7, 6, 5, 3, 1, 0, -1, -2, -2, -2]},
        {name: "Vocal", builtin: false, bands: [-3, -2, -1, 1, 4, 5, 4, 2, 0, -1]},
        {name: "Electronic", builtin: false, bands: [5, 4, 1, 0, -2, 2, 1, 4, 5, 5]},
        {name: "Classical", builtin: false, bands: [3, 2, 1, 0, -1, -1, 0, 2, 3, 4]},
        {name: "Treble", builtin: false, bands: [-3, -3, -2, -1, 0, 2, 4, 6, 7, 7]}
    ]
    readonly property var customEqPresets: Logic.parseEqPresets(pluginData.customEqPresets || "[]")
    readonly property var allEqPresets: builtInEqPresets.concat(customEqPresets)

    function localPath(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
    }

    function toastError(title, details) {
        lastError = details || title
        ToastService.showError(title, details || "")
    }

    function processKey(key) {
        return processNamespace + "." + key + "." + (++requestSerial)
    }

    function runCliamp(key, args, callback, quiet) {
        var command = [cliampPath].concat(args)
        Proc.runCommand(processKey(key), command, (stdout, exitCode) => {
            if (exitCode !== 0 && !quiet)
                toastError("CLIAMP command failed", String(stdout || "CLIAMP is not available").trim())
            if (callback)
                callback(stdout, exitCode)
        })
    }

    function command(key, args) {
        if (!online) {
            toastError(launching ? "CLIAMP is starting" : "CLIAMP is offline", launching ? "Wait a moment for the background service to become ready." : "Launch CLIAMP before using playback controls.")
            return
        }
        runCliamp(key, args, (stdout, exitCode) => {
            if (exitCode === 0)
                refreshStatus()
        }, false)
    }

    function savePlaybackPreference(key, value) {
        var next = Object.assign({}, playbackPreferences)
        next[key] = value
        playbackPreferences = next
        pluginService.savePluginState(pluginId, "playbackPreferences", next)
    }

    function reloadPersistentState() {
        var favorites = pluginService.loadPluginState(pluginId, "radioFavorites", [])
        var recents = pluginService.loadPluginState(pluginId, "radioRecents", [])
        var preferences = pluginService.loadPluginState(pluginId, "playbackPreferences", {})
        radioFavorites = Array.isArray(favorites) ? favorites.slice() : []
        radioRecents = Array.isArray(recents) ? recents.slice() : []
        playbackPreferences = preferences && typeof preferences === "object" ? Object.assign({}, preferences) : ({})
    }

    function volumeDbToPercent(db) {
        var bounded = Math.max(volumeMinDb, Math.min(volumeMaxDb, Number(db)))
        return Math.round((bounded - volumeMinDb) * 100 / (volumeMaxDb - volumeMinDb))
    }

    function volumePercentToDb(percent) {
        var bounded = Math.max(0, Math.min(100, Number(percent)))
        return volumeMinDb + bounded * (volumeMaxDb - volumeMinDb) / 100
    }

    function queueVolumeChange(displayValue) {
        var volume = percentageVolume ? volumePercentToDb(displayValue) : Number(displayValue)
        pendingVolumeDb = Math.round(volume * 10) / 10
        savePlaybackPreference("volume", pendingVolumeDb)
        volumeCommitTimer.restart()
    }

    function configuredPlaybackPreferences() {
        return {
            volume: Math.max(volumeMinDb, Math.min(volumeMaxDb, Number(pluginData.defaultVolume ?? -12))),
            visualizer: String(pluginData.defaultVisualizer || "Bars"),
            speed: Number(pluginData.defaultSpeed || 1),
            repeat: String(pluginData.defaultRepeat || "off").toLowerCase(),
            shuffle: pluginData.defaultShuffle === true,
            mono: pluginData.defaultMono === true
        }
    }

    function restorePlaybackPreferences() {
        if (!online || preferencesApplied)
            return
        preferencesApplied = true
        var defaults = configuredPlaybackPreferences()
        var current = {volume: player.volume, visualizer: player.visualizer || "Bars", speed: player.speed, repeat: player.repeat, shuffle: player.shuffle, mono: player.mono}
        var remember = pluginData.rememberPlaybackPreferences !== false
        if (remember && Object.keys(playbackPreferences).length === 0) {
            playbackPreferences = current
            pluginService.savePluginState(pluginId, "playbackPreferences", current)
            return
        }
        var values = remember ? Object.assign({}, current, playbackPreferences) : defaults
        runCliamp("restoreVolume", ["volume", String(values.volume)], null, true)
        if (pluginData.launchInBackground === true)
            player = Object.assign({}, player, {visualizer: String(values.visualizer)})
        else
            runCliamp("restoreVisualizer", ["vis", String(values.visualizer)], null, true)
        runCliamp("restoreSpeed", ["speed", String(values.speed)], null, true)
        runCliamp("restoreRepeat", ["repeat", String(values.repeat)], null, true)
        runCliamp("restoreShuffle", ["shuffle", values.shuffle ? "on" : "off"], null, true)
        runCliamp("restoreMono", ["mono", values.mono ? "on" : "off"], () => refreshStatus(), true)
    }

    function refreshStatus() {
        if (polling)
            return
        root.polling = true
        runCliamp("status", ["status", "--json"], (stdout, exitCode) => {
            root.polling = false
            var parsed = exitCode === 0 ? Logic.normalizedStatus(stdout) : null
            var wasOnline = root.online
            root.online = parsed !== null
            if (parsed) {
                if (cliampMprisPlayer) {
                    parsed = Object.assign({}, parsed, {
                        title: cliampMprisPlayer.trackTitle || parsed.title,
                        artist: cliampMprisPlayer.trackArtist || parsed.artist,
                        album: cliampMprisPlayer.trackAlbum || parsed.album,
                        artUrl: cliampMprisPlayer.trackArtUrl || parsed.artUrl
                    })
                }
                if (parsed.path === streamMetadataPath)
                    parsed = Object.assign({}, parsed, streamMetadata)
                var rawParsed = parsed
                var incomingKey = parsed.path + "|" + parsed.title
                if (incomingKey === metadataKey)
                    parsed = Object.assign({}, parsed, enrichedMetadata)
                parsed = applyRadioSongTiming(parsed, rawParsed)
                root.player = parsed
                if (wasOnline)
                    publishMprisMetadata()
                else
                    startMprisBridge()
                if (Array.isArray(parsed.eqBands) && parsed.eqBands.length === 10)
                    eqBands = parsed.eqBands
                if (parsed.eqPreset && parsed.eqPreset.toLowerCase() !== "custom")
                    activeEqPreset = parsed.eqPreset
                root.lastError = ""
                refreshTrackMetadata(rawParsed)
                refreshStationMetadata(rawParsed)
                if (!wasOnline) {
                    reloadPersistentState()
                    refreshTrackSearchProviders()
                    reconnectRestoreTimer.restart()
                }
            } else {
                root.preferencesApplied = false
                resetRadioSongTiming()
                root.player = Object.assign({}, root.player, {state: "stopped", title: "CLIAMP is offline", artist: ""})
                if (mprisBridgeActive)
                    stopMprisBridge()
            }
        }, true)
    }

    function refreshTrackMetadata(track) {
        var key = track.path + "|" + track.title
        if (key === metadataKey)
            return
        metadataKey = key
        enrichedMetadata = ({})
        if (track.artUrl)
            return
        var parts = String(track.title || "").split(/\s+-\s+/)
        var artist = String(track.artist || "").trim()
        var title = String(track.title || "").trim()
        if (!artist && parts.length >= 2) {
            artist = parts[0]
            title = parts.slice(1).join(" ")
        }
        if (!artist || !title || /^\d+(_\d+)?$/.test(title))
            return
        var query = artist + " " + title
        Proc.runCommand(processKey("metadata"), [
            "curl", "-fsS", "--max-time", "5", "--get", "https://itunes.apple.com/search",
            "--data-urlencode", "term=" + query, "--data", "entity=song", "--data", "limit=5"
        ], (stdout, exitCode) => {
            var response = exitCode === 0 ? Logic.safeJson(stdout, null) : null
            if (metadataKey !== key)
                return
            var results = response && Array.isArray(response.results) ? response.results : []
            var wantedArtist = normalizeMetadataText(artist)
            var wantedTitle = normalizeMetadataText(title)
            var match = results.find(candidate => {
                var candidateArtist = normalizeMetadataText(candidate.artistName)
                var candidateTitle = normalizeMetadataText(candidate.trackName)
                if (!candidateArtist || !candidateTitle)
                    return false
                var artistMatches = candidateArtist === wantedArtist || candidateArtist.indexOf(wantedArtist) >= 0 || wantedArtist.indexOf(candidateArtist) >= 0
                var titleMatches = candidateTitle === wantedTitle || candidateTitle.indexOf(wantedTitle) >= 0 || wantedTitle.indexOf(candidateTitle) >= 0
                return artistMatches && titleMatches
            })
            if (match) {
                var liveStream = String(track.path || "").indexOf("http") === 0 && Number(track.duration || 0) <= 0
                enrichedMetadata = liveStream ? {
                    // ICY title/artist/station metadata is the stable identity for
                    // a live song. Catalog lookup may only add its artwork.
                    artUrl: String(match.artworkUrl100 || "").replace("100x100", "600x600")
                } : {
                    title: match.trackName || title,
                    artist: match.artistName || artist,
                    album: match.collectionName || "",
                    artUrl: String(match.artworkUrl100 || "").replace("100x100", "600x600")
                }
                player = Object.assign({}, player, enrichedMetadata)
                publishMprisMetadata()
                return
            }

            // Some stations shorten or mistag track names. Use artwork from a
            // catalog result by the same artist, then fall back to the station
            // image, without claiming an inexact result's album metadata.
            var station = knownStationForUrl(track.path)
            var artistResult = results.find(candidate => {
                var candidateArtist = normalizeMetadataText(candidate.artistName)
                return candidateArtist && (candidateArtist === wantedArtist || candidateArtist.indexOf(wantedArtist) >= 0 || wantedArtist.indexOf(candidateArtist) >= 0)
            })
            var fallbackArt = artistResult && artistResult.artworkUrl100
                ? String(artistResult.artworkUrl100).replace("100x100", "600x600")
                : (station && station.favicon ? station.favicon : "")
            if (!fallbackArt)
                return
            enrichedMetadata = {artUrl: fallbackArt}
            player = Object.assign({}, player, enrichedMetadata)
            publishMprisMetadata()
        })
    }

    function normalizeMetadataText(value) {
        return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "").trim()
    }

    function resetRadioSongTiming() {
        radioTimingPath = ""
        radioTimingKey = ""
        radioSongStartedMs = 0
        radioSongTimingActive = false
        radioPositionResetPending = false
    }

    function radioSongIdentityKey(track) {
        var artist = String(track.artist || "").trim()
        var title = String(track.title || "").trim()
        if (!artist) {
            var parts = title.split(/\s+-\s+/)
            if (parts.length < 2)
                return ""
            artist = parts[0]
            title = parts.slice(1).join(" - ")
        }
        return normalizeMetadataText(artist) + "|" + normalizeMetadataText(title)
    }

    function applyRadioSongTiming(track, identityTrack) {
        var path = String(track.path || "")
        if (path.indexOf("http") !== 0) {
            resetRadioSongTiming()
            return track
        }
        var identity = identityTrack || track
        var key = radioSongIdentityKey(identity)
        if (!key)
            return track
        if (path !== radioTimingPath) {
            radioTimingPath = path
            radioTimingKey = key
            mprisTrackSerial++
            radioSongStartedMs = 0
            radioSongTimingActive = false
            radioPositionResetPending = false
            return track
        }
        if (key !== radioTimingKey) {
            radioTimingKey = key
            mprisTrackSerial++
            radioSongStartedMs = Date.now()
            radioSongTimingActive = true
            radioPositionResetPending = true
        }
        if (!radioSongTimingActive)
            return track
        return Object.assign({}, track, {position: Math.max(0, (Date.now() - radioSongStartedMs) / 1000)})
    }

    function refreshHeadlessStreamMetadata() {
        var path = String(player.path || "")
        if (!online || path.indexOf("http") !== 0)
            return
        Proc.runCommand(processKey("streamMetadata"), [helperPath, "stream-metadata", path], (stdout, exitCode) => {
            if (exitCode !== 0 || String(player.path || "") !== path)
                return
            var response = Logic.safeJson(stdout, null)
            var tags = response && response.format && response.format.tags ? response.format.tags : ({})
            var streamTitle = String(tags.StreamTitle || tags["icy-title"] || "").replace(/\s+/g, " ").trim()
            if (!streamTitle)
                return
            var parts = streamTitle.split(/\s+-\s+/)
            var station = knownStationForUrl(path)
            streamMetadataPath = path
            streamMetadata = {
                title: parts.length >= 2 ? parts.slice(1).join(" - ") : streamTitle,
                artist: parts.length >= 2 ? parts[0] : (station ? station.name : "Internet radio"),
                album: station ? station.name : String(tags["icy-name"] || "Internet radio"),
                artUrl: ""
            }
            player = applyRadioSongTiming(Object.assign({}, player, streamMetadata), Object.assign({}, player, streamMetadata))
            publishMprisMetadata()
            refreshTrackMetadata(player)
        })
    }

    function refreshStationMetadata(track) {
        var url = String(track.path || "")
        if (url.indexOf("http") !== 0) {
            stationMetadataKey = ""
            detectedStationName = ""
            return
        }
        var key = url.split("?")[0]
        if (key === stationMetadataKey)
            return
        stationMetadataKey = key
        detectedStationName = ""
        Proc.runCommand(processKey("stationMetadata"), ["curl", "-fsSI", "--max-time", "8", url], (stdout, exitCode) => {
            if (stationMetadataKey !== key || exitCode !== 0)
                return
            var match = String(stdout || "").match(/^icy-name:\s*(.+)$/im)
            if (match)
                detectedStationName = match[1].trim()
        })
    }

    function refreshBridge() {
        Proc.runCommand(processKey("bridgeCheck"), [helperPath, "bridge-status"], (stdout, exitCode) => {
            bridgeReady = exitCode === 0
            if (bridgeReady)
                refreshQueue()
        })
    }

    function refreshQueue() {
        if (!online || !bridgeReady)
            return
        runCliamp("snapshot", ["plugins", "call", "cliamp-dms-bridge", "snapshot"], (stdout, exitCode) => {
            var snapshot = exitCode === 0 ? Logic.safeJson(String(stdout).trim(), null) : null
            queueItems = snapshot && Array.isArray(snapshot.queue) ? snapshot.queue : []
            if (snapshot && Array.isArray(snapshot.eq_bands) && snapshot.eq_bands.length === 10)
                eqBands = snapshot.eq_bands.map(value => Number(value || 0))
        }, true)
    }

    function setEqBand(index, value) {
        var nextBands = eqBands.slice()
        nextBands[index] = value
        eqBands = nextBands
        activeEqPreset = "Custom"
        runCliamp("eqBand" + index, ["eq", "--band", String(index), String(value)], (stdout, exitCode) => {
            if (exitCode === 0) {
                player = Object.assign({}, player, {eqPreset: "Custom"})
                refreshStatus()
            }
        }, false)
    }

    function setEqPreset(preset) {
        if (!preset || !online)
            return
        activeEqPreset = preset.name
        if (!preset.builtin) {
            applyEqBands(preset, 0)
            return
        }
        runCliamp("eqPreset", ["eq", preset.name], (stdout, exitCode) => {
            if (exitCode === 0) {
                refreshStatus()
                refreshQueue()
            }
        }, false)
    }

    function applyEqBands(preset, index) {
        if (index >= preset.bands.length) {
            eqBands = preset.bands.slice()
            player = Object.assign({}, player, {eqPreset: "Custom"})
            return
        }
        runCliamp("eqPresetBand" + index, ["eq", "--band", String(index), String(preset.bands[index])], (stdout, exitCode) => {
            if (exitCode === 0)
                applyEqBands(preset, index + 1)
        }, false)
    }

    function refreshLists() {
        Proc.runCommand(processKey("ensureRadioPlaylist"), [helperPath, "ensure-radio-playlist"], () => {
            runCliamp("playlists", ["playlist", "list"], (stdout, exitCode) => {
                playlists = exitCode === 0 ? Logic.playlistLines(stdout) : []
            }, true)
        })
        if (pluginData.launchInBackground === true)
            visualizers = builtInVisualizers.slice()
        else
            runCliamp("visualizers", ["vis", "list"], (stdout, exitCode) => {
                visualizers = exitCode === 0 ? Logic.lines(stdout) : builtInVisualizers.slice()
            }, true)
        if (online) {
            runCliamp("devices", ["device", "list"], (stdout, exitCode) => {
                devices = exitCode === 0 ? Logic.deviceLines(stdout) : []
            }, true)
        }
        Proc.runCommand(processKey("providers"), [helperPath, "providers"], (stdout, exitCode) => {
            providers = exitCode === 0 ? Logic.providerLines(stdout) : []
        })
        if (online)
            refreshTrackSearchProviders()
        else
            trackSearchProviders = []
    }

    function ipcRequest(request, callback) {
        Proc.runCommand(processKey("ipc"), [helperPath, "ipc-request", JSON.stringify(request)], (stdout, exitCode) => {
            var response = exitCode === 0 ? Logic.safeJson(String(stdout).trim(), null) : null
            if (callback)
                callback(response, exitCode, stdout)
        })
    }

    function refreshTrackSearchProviders() {
        ipcRequest({cmd: "provider.list"}, (response, exitCode) => {
            var available = response && response.ok && Array.isArray(response.providers)
                ? response.providers.filter(item => item.searchable).map(item => ({key: String(item.key), name: String(item.name)}))
                : []
            if (!available.some(item => item.key === "youtube"))
                available.unshift({key: "youtube-fallback", name: "YouTube"})
            trackSearchProviders = available
            if (!available.some(item => item.key === trackSearchProvider)) {
                var preferred = available.find(item => item.key === String(pluginData.launchProvider || ""))
                trackSearchProvider = preferred ? preferred.key : (available.length ? available[0].key : "youtube-fallback")
            }
        })
    }

    function searchTracks(query) {
        var text = String(query || "").trim()
        if (text.length < 2) {
            trackSearchResults = []
            trackSearchError = "Type at least two characters"
            return
        }
        if (!online) {
            toastError("CLIAMP is offline", "Launch CLIAMP before searching for a track.")
            return
        }
        trackSearchLoading = true
        trackSearchError = ""
        trackSearchResults = []
        if (trackSearchProvider === "youtube-fallback") {
            Proc.runCommand(processKey("youtubeSearch"), [helperPath, "youtube-search", text], (stdout, exitCode) => {
                trackSearchLoading = false
                var response = exitCode === 0 ? Logic.safeJson(String(stdout).trim(), null) : null
                var entries = response && Array.isArray(response.entries) ? response.entries : []
                trackSearchResults = entries.map(item => ({
                    title: String(item.title || "YouTube track"),
                    artist: String(item.channel || item.uploader || "YouTube"),
                    album: "YouTube",
                    path: String(item.webpage_url || item.url || (item.id ? "https://www.youtube.com/watch?v=" + item.id : "")),
                    duration_secs: Math.round(Number(item.duration || 0)),
                    album_art_url: String(item.thumbnail || "")
                })).filter(item => item.path.length > 0)
                trackSearchError = trackSearchResults.length ? "" : (exitCode === 0 ? "No tracks found" : String(stdout || "YouTube search failed").trim())
            })
            return
        }
        ipcRequest({cmd: "provider.search", provider: trackSearchProvider, query: text, limit: 20}, (response, exitCode, stdout) => {
            trackSearchLoading = false
            trackSearchResults = response && response.ok && Array.isArray(response.tracks) ? response.tracks : []
            trackSearchError = trackSearchResults.length ? "" : (response && response.error ? response.error : (exitCode === 0 ? "No tracks found" : String(stdout || "Search failed").trim()))
        })
    }

    function playSearchTrack(track) {
        if (!track || !track.path)
            return
        ipcRequest({cmd: "track.play", track: track}, (response, exitCode, stdout) => {
            if (!response || !response.ok) {
                toastError("Track could not start", response && response.error ? response.error : String(stdout || "CLIAMP rejected the track").trim())
                return
            }
            ToastService.showInfo("Playing track", String(track.title || track.path))
            refreshStatus()
            refreshQueue()
        })
    }

    function setVisualizer(modelData) {
        var style = String(modelData || "Bars")
        savePlaybackPreference("visualizer", style)
        player = Object.assign({}, player, {visualizer: style})
        if (pluginData.launchInBackground !== true)
            command("visualizer", ["vis", style])
    }

    function searchRadio(query) {
        var text = String(query || "").trim()
        if (text.length < 2) {
            radioResults = []
            radioError = "Type at least two characters"
            return
        }
        radioLoading = true
        radioError = ""
        var needle = text.toLowerCase()
        var bundledMatches = cliampStations.filter(station =>
            (station.name + " " + station.tags).toLowerCase().indexOf(needle) >= 0)
        var args = [
            "-fsS", "--max-time", "10", "-A", "cliamp-dms/0.1.0", "--get",
            "https://all.api.radio-browser.info/json/stations/search",
            "--data-urlencode", "name=" + text,
            "--data", "hidebroken=true",
            "--data", "order=votes",
            "--data", "reverse=true",
            "--data", "limit=" + Math.max(5, Math.min(100, Number(pluginData.radioLimit || 30)))
        ]
        var country = String(pluginData.radioCountry || "").trim()
        var language = String(pluginData.radioLanguage || "").trim()
        if (country)
            args.push("--data-urlencode", "country=" + country)
        if (language)
            args.push("--data-urlencode", "language=" + language)
        Proc.runCommand(processKey("radio"), ["curl"].concat(args), (stdout, exitCode) => {
            radioLoading = false
            if (exitCode !== 0) {
                radioResults = bundledMatches
                radioMode = "results"
                radioError = radioResults.length ? "" : "Radio Browser could not be reached"
                return
            }
            radioResults = Logic.mergeStations(bundledMatches, Logic.normalizeStations(stdout))
            radioMode = "results"
            radioError = radioResults.length === 0 ? "No stations found" : ""
        })
    }

    function playStation(station) {
        if (pluginData.launchInBackground === true) {
            playBackgroundStation(station)
            return
        }
        if (!online) {
            toastError("CLIAMP is offline", "Launch CLIAMP, then select the station again.")
            return
        }
        if (!bridgeReady) {
            toastError("Radio bridge is not ready", "Install and trust the bridge, then restart CLIAMP.")
            return
        }
        runCliamp("radioPlay", ["plugins", "call", "cliamp-dms-bridge", "play-radio", station.url], (stdout, exitCode) => {
            var response = exitCode === 0 ? Logic.safeJson(String(stdout).trim(), null) : null
            if (!response || response.ok === false) {
                toastError("Station could not start", response && response.error ? response.error : String(stdout).trim())
                return
            }
            selectQueuedStation(station)
        }, false)
    }

    function playBackgroundStation(station) {
        launching = true
        pendingRadioStation = station
        launchProbeAttempts = 0
        var rememberedVolume = Number(playbackPreferences.volume ?? player.volume)
        Proc.runCommand(processKey("backgroundRadio"), [helperPath, "background-radio", String(pluginData.launchProvider || "radio"), station.url, String(rememberedVolume)], (stdout, exitCode) => {
            if (exitCode !== 0) {
                launching = false
                pendingRadioStation = null
                toastError("Station could not start", String(stdout || "Could not restart the CLIAMP background service").trim())
                return
            }
            backgroundStationProbeTimer.restart()
        })
    }

    function probeBackgroundStation() {
        var station = pendingRadioStation
        if (!station)
            return
        runCliamp("backgroundStationProbe", ["status", "--json"], (stdout, exitCode) => {
            var parsed = exitCode === 0 ? Logic.normalizedStatus(stdout) : null
            var expected = String(station.url || "").replace(/\/$/, "")
            var actual = parsed ? String(parsed.path || "").replace(/\/$/, "") : ""
            if (parsed && actual === expected) {
                launching = false
                pendingRadioStation = null
                radioRecents = Logic.upsertRecent(radioRecents, station, 20)
                pluginService.savePluginState(pluginId, "radioRecents", radioRecents)
                Proc.runCommand(processKey("radioClick"), ["curl", "-fsS", "--max-time", "5", "-A", "cliamp-dms/0.1.0", "https://all.api.radio-browser.info/json/url/" + station.uuid], () => {})
                refreshStatus()
                ToastService.showInfo("Station started", station.name)
                return
            }
            launchProbeAttempts++
            if (launchProbeAttempts < 40) {
                backgroundStationProbeTimer.restart()
                return
            }
            launching = false
            pendingRadioStation = null
            toastError("Station could not start", "CLIAMP did not confirm the requested stream. Check ~/.config/cliamp/cliamp.log.")
        }, true)
    }

    function selectQueuedStation(station) {
        pendingRadioStation = station
        radioSelectionAttempts = 0
        pollQueuedStation()
    }

    function pollQueuedStation() {
        var station = pendingRadioStation
        if (!station)
            return
        runCliamp("radioSelectSnapshot", ["plugins", "call", "cliamp-dms-bridge", "snapshot"], (stdout, exitCode) => {
            if (pendingRadioStation !== station)
                return
            var snapshot = exitCode === 0 ? Logic.safeJson(String(stdout).trim(), null) : null
            var queue = snapshot && Array.isArray(snapshot.queue) ? snapshot.queue : []
            var targetIndex = -1
            for (var index = queue.length - 1; index >= 0; index--) {
                if (String(queue[index].path || "") === String(station.url || "")) {
                    targetIndex = Number(queue[index].index)
                    break
                }
            }
            if (targetIndex < 0) {
                radioSelectionAttempts++
                if (radioSelectionAttempts < 20) {
                    radioSelectionTimer.restart()
                    return
                }
                pendingRadioStation = null
                toastError("Station could not start", "CLIAMP did not expose the requested stream in its queue after waiting for it.")
                return
            }
            pendingRadioStation = null
            runCliamp("radioJump", ["plugins", "call", "cliamp-dms-bridge", "jump", String(targetIndex)], (jumpOutput, jumpExitCode) => {
                var jumpResponse = jumpExitCode === 0 ? Logic.safeJson(String(jumpOutput).trim(), null) : null
                if (jumpExitCode !== 0 || (jumpResponse && jumpResponse.ok === false)) {
                    toastError("Station could not start", jumpResponse && jumpResponse.error ? jumpResponse.error : String(jumpOutput).trim())
                    return
                }
                radioRecents = Logic.upsertRecent(radioRecents, station, 20)
                pluginService.savePluginState(pluginId, "radioRecents", radioRecents)
                Proc.runCommand(processKey("radioClick"), ["curl", "-fsS", "--max-time", "5", "-A", "cliamp-dms/0.1.0", "https://all.api.radio-browser.info/json/url/" + station.uuid], () => {})
                refreshStatus()
                refreshQueue()
            }, false)
        }, false)
    }

    function isFavorite(station) {
        return radioFavorites.some(item => item.uuid === station.uuid)
    }

    function toggleFavorite(station) {
        if (isFavorite(station))
            radioFavorites = radioFavorites.filter(item => item.uuid !== station.uuid)
        else
            radioFavorites = [station].concat(radioFavorites)
        pluginService.savePluginState(pluginId, "radioFavorites", radioFavorites)
    }

    function currentFavoriteItem() {
        var url = String(player.path || "")
        if (!url)
            return null
        var known = cliampStations.concat(radioFavorites).concat(radioRecents).concat(radioResults).find(item => item && item.url === url)
        return known || {
            uuid: url,
            name: player.title || "Current stream",
            url: url,
            favicon: player.artUrl || "",
            country: "",
            language: "",
            codec: "",
            bitrate: 0,
            tags: ""
        }
    }

    function knownStationForUrl(url) {
        var baseUrl = String(url || "").split("?")[0]
        return cliampStations.concat(radioFavorites).concat(radioRecents).concat(radioResults).find(item => {
            if (!item || !item.url)
                return false
            return item.url === url || String(item.url).split("?")[0] === baseUrl
        }) || null
    }

    function currentStationName() {
        var url = String(player.path || "")
        if (!url || url.indexOf("http") !== 0)
            return ""
        var station = knownStationForUrl(url)
        return station ? station.name : detectedStationName
    }

    function barPreviewText() {
        var title = String(player.title || "").replace(/\s+/g, " ").trim()
        if (barPreviewMode === "track")
            return title
        if (barPreviewMode === "stationTrack") {
            var station = currentStationName() || "Radio"
            return title && title !== station ? station + " · " + title : station
        }
        return ""
    }

    function installBridge() {
        Proc.runCommand(processKey("installBridge"), [helperPath, "install-bridge", bridgePath], (stdout, exitCode) => {
            if (exitCode !== 0) {
                toastError("Bridge installation failed", String(stdout).trim())
                return
            }
            refreshBridge()
            ToastService.showInfo("Bridge installed and trusted", "Restart CLIAMP once to load the bridge.")
        })
    }

    function launchCliamp() {
        if (launching)
            return
        runCliamp("preLaunch", ["status", "--json"], (stdout, exitCode) => {
            if (exitCode === 0 && Logic.normalizedStatus(stdout) !== null) {
                refreshStatus()
                ToastService.showInfo("CLIAMP is already running", "Playback controls are connected to the existing instance.")
                return
            }
            startCliampLaunch()
        }, true)
    }

    function startCliampLaunch() {
        var background = pluginData.launchInBackground === true
        var rememberedVolume = Number(playbackPreferences.volume ?? configuredPlaybackPreferences().volume)
        launching = true
        launchProbeAttempts = 0
        Quickshell.execDetached([helperPath, "launch", String(pluginData.launchProvider || "radio"), String(pluginData.terminal || ""), background ? "1" : "0", String(rememberedVolume)])
        ToastService.showInfo("Starting CLIAMP", background ? "Waiting for the background service to become ready." : "Opening it in your terminal.")
        launchProbeTimer.restart()
    }

    function startMprisBridge() {
        mprisBridgeActive = true
        Proc.runCommand(processKey("mprisStart"), [helperPath, "mpris-start", mprisBridgePath], () => {
            if (online)
                publishMprisMetadata()
        })
    }

    function stopMprisBridge() {
        mprisBridgeActive = false
        lastMprisPayload = ""
        Proc.runCommand(processKey("mprisStop"), [helperPath, "mpris-stop"])
    }

    function publishMprisMetadata() {
        if (!online)
            return
        var positionReset = radioPositionResetPending
        var audiblePosition = Math.max(0, Number(player.position || 0) - mprisLatencyCompensation)
        var liveStream = String(player.path || "").indexOf("http") === 0 && Number(player.duration || 0) <= 0
        // Radio stations often put their station name in the album field before
        // catalog enrichment finds the real album. Keep MPRIS track identity
        // stable so lyrics clients do not discard and refetch the same song.
        var mprisAlbum = liveStream ? "" : player.album
        var payload = JSON.stringify({publisherId: processNamespace, state: player.state, title: player.title, artist: player.artist, album: mprisAlbum, path: player.path, artUrl: player.artUrl, position: audiblePosition, duration: player.duration, volume: player.volume, positionReset: positionReset, trackId: "/org/mpris/MediaPlayer2/Track/" + mprisTrackSerial})
        if (payload === lastMprisPayload)
            return
        Proc.runCommand(processKey("mprisUpdate"), [helperPath, "mpris-update", payload], (stdout, exitCode) => {
            if (exitCode === 0) {
                lastMprisPayload = payload
                if (positionReset)
                    radioPositionResetPending = false
            }
        })
    }

    function probeCliampLaunch() {
        runCliamp("launchProbe", ["status", "--json"], (stdout, exitCode) => {
            if (!launching)
                return
            if (exitCode === 0 && Logic.normalizedStatus(stdout) !== null) {
                launching = false
                refreshStatus()
                ToastService.showInfo("CLIAMP is ready", "Playback controls are connected.")
                return
            }
            launchProbeAttempts++
            if (launchProbeAttempts < 32) {
                launchProbeTimer.restart()
                return
            }
            launching = false
            toastError("CLIAMP could not start", "Check ~/.config/cliamp/cliamp.log for the daemon startup error.")
        }, true)
    }

    function setupProvider() {
        Quickshell.execDetached([helperPath, "setup", String(pluginData.terminal || "")])
        ToastService.showInfo("Opening provider setup", "Complete setup in the terminal.")
    }

    function saveLaunchProvider(provider) {
        pluginService.savePluginData(pluginId, "launchProvider", provider)
        if (!online)
            return
        var rememberedVolume = Number(playbackPreferences.volume ?? configuredPlaybackPreferences().volume)
        launching = true
        launchProbeAttempts = 0
        Quickshell.execDetached([helperPath, "switch-provider", provider, String(pluginData.terminal || ""), pluginData.launchInBackground === true ? "1" : "0", String(rememberedVolume)])
        launchProbeTimer.restart()
        ToastService.showInfo("Opening " + provider, "Restarting the plugin-managed CLIAMP session.")
    }

    Component.onCompleted: {
        reloadPersistentState()
        selectedTab = pluginService.loadPluginState(pluginId, "selectedTab", "playing")
        refreshStatus()
        refreshBridge()
        refreshLists()
    }

    Timer {
        id: reconnectRestoreTimer
        interval: 1500
        repeat: false
        onTriggered: root.restorePlaybackPreferences()
    }

    Timer {
        id: volumeCommitTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (root.online)
                root.command("volume", ["volume", String(root.pendingVolumeDb)])
        }
    }

    Timer {
        id: radioSelectionTimer
        interval: 150
        repeat: false
        onTriggered: root.pollQueuedStation()
    }

    Timer {
        id: launchProbeTimer
        interval: 250
        repeat: false
        onTriggered: root.probeCliampLaunch()
    }

    Timer {
        id: backgroundStationProbeTimer
        interval: 250
        repeat: false
        onTriggered: root.probeBackgroundStation()
    }

    Timer {
        interval: 3000
        running: root.online && root.player.path.indexOf("http") === 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshHeadlessStreamMetadata()
    }

    Timer {
        interval: root.popoutVisible ? root.openPollMs : root.closedPollMs
        running: true
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Process {
        id: spectrumProcess
        command: [root.cliampPath, "visstream", "--fps", String(root.visualizerFps)]
        running: root.visualizerShouldRun
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var frame = Logic.safeJson(String(data).trim(), null)
                if (frame && Array.isArray(frame.bands) && frame.bands.length >= 10)
                    root.spectrumBands = frame.bands.slice(0, 10).map(value => Math.max(0, Math.min(1, Number(value || 0))))
            }
        }
        onRunningChanged: {
            if (!running)
                root.spectrumBands = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            height: root.widgetThickness
            clip: true
            Accessible.role: Accessible.StaticText
            Accessible.name: !root.online ? "CLIAMP radio offline" : root.isPlaying ? "CLIAMP radio playing " + (root.barPreviewText() || root.player.title) : "CLIAMP radio paused " + (root.barPreviewText() || root.player.title)

            DankIcon {
                name: !root.online ? "portable_wifi_off" : root.isPlaying ? "radio" : "pause_circle"
                size: root.iconSize
                color: !root.online ? Theme.surfaceVariantText : root.isPlaying ? Theme.secondary : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.barPreviewMode !== "icon"
                width: Math.min(implicitWidth, root.maxTitleWidth)
                height: root.widgetThickness
                text: root.barPreviewText()
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                verticalAlignment: Text.AlignVCenter
                color: root.online ? Theme.surfaceText : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: !root.online ? "portable_wifi_off" : root.isPlaying ? "radio" : "pause_circle"
            size: root.iconSize
            color: !root.online ? Theme.surfaceVariantText : root.isPlaying ? Theme.secondary : Theme.surfaceText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    popoutWidth: 440
    popoutHeight: 620

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: ""
            detailsText: ""
            showCloseButton: false

            Component.onCompleted: {
                root.popoutVisible = true
                root.refreshStatus()
                root.refreshBridge()
                root.refreshLists()
            }
            Component.onDestruction: root.popoutVisible = false

            Column {
                x: Theme.spacingL
                width: parent.width - Theme.spacingL * 2
                spacing: Theme.spacingM

                Column {
                    id: titleBlock
                    width: parent.width
                    spacing: Theme.spacingXS

                    Item { width: 1; height: Theme.spacingS }
                    StyledText {
                        text: "Cliamp"
                        font.pixelSize: Theme.fontSizeLarge + 4
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }
                    StyledText {
                        width: parent.width
                        text: root.online ? (root.player.artist || (root.player.state.charAt(0).toUpperCase() + root.player.state.slice(1))) : root.launching ? "Starting Cliamp…" : "Player offline"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                Row {
                    id: tabRow
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: [
                            {id: "playing", icon: "play_circle", label: "Playing"},
                            {id: "radio", icon: "radio", label: "Radio"},
                            {id: "library", icon: "queue_music", label: "Library"},
                            {id: "sound", icon: "tune", label: "Sound"},
                            {id: "providers", icon: "cloud", label: "Providers"}
                        ]
                        delegate: ControlButton {
                            required property var modelData
                            buttonSize: 38
                            width: (tabRow.width - tabRow.spacing * 4) / 5
                            iconName: modelData.icon
                            tooltipText: modelData.label
                            active: root.selectedTab === modelData.id
                            onClicked: {
                                root.selectedTab = modelData.id
                                root.pluginService.savePluginState(root.pluginId, "selectedTab", modelData.id)
                            }
                        }
                    }
                }

                Loader {
                    width: parent.width
                    height: root.popoutHeight - titleBlock.height - tabRow.height - Theme.spacingM * 3 - Theme.spacingL
                    sourceComponent: root.selectedTab === "playing" ? playingTab : root.selectedTab === "radio" ? radioTab : root.selectedTab === "library" ? libraryTab : root.selectedTab === "sound" ? soundTab : providersTab
                }
            }
        }
    }

    Component {
        id: offlineCard
        Item {
            width: parent ? parent.width : 400
            height: 126

            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                StyledText { text: root.launching ? "CLIAMP is starting…" : "CLIAMP is not running"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold; anchors.horizontalCenter: parent.horizontalCenter }
                StyledText { text: root.launching ? "Waiting for its local control socket." : "Launch it with the selected provider, or start it yourself."; color: Theme.surfaceVariantText; anchors.horizontalCenter: parent.horizontalCenter }
                ControlButton { buttonSize: root.compactControlSize; iconName: root.launching ? "hourglass_top" : "open_in_new"; label: root.launching ? "Starting…" : "Launch CLIAMP"; enabled: !root.launching; anchors.horizontalCenter: parent.horizontalCenter; onClicked: root.launchCliamp() }
            }
        }
    }

    Component {
        id: playingTab
        Item {
            Loader { anchors.fill: parent; active: !root.online; sourceComponent: offlineCard }

            Column {
                id: playingColumn
                anchors.fill: parent
                spacing: Theme.spacingM
                visible: root.online

                StyledRect {
                    id: nowPlayingCard
                    width: parent.width
                    height: 106
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius
                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM
                        StyledRect {
                            width: 74; height: 74; radius: Theme.cornerRadius; color: Theme.primaryContainer
                            clip: true
                            Image {
                                id: albumArt
                                anchors.fill: parent
                                source: root.player.artUrl
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                visible: status === Image.Ready
                            }
                            DankIcon { anchors.centerIn: parent; visible: albumArt.status !== Image.Ready; name: root.player.path.indexOf("http") === 0 ? "radio" : "album"; size: 36; color: Theme.primary }
                        }
                        Column {
                            width: parent.width - 90
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            StyledText { width: parent.width; text: root.player.title; wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
                            StyledText { width: parent.width; text: root.player.artist || "Unknown artist"; wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight; color: Theme.surfaceVariantText }
                            StyledText { visible: root.player.album.length > 0; width: parent.width; text: root.player.album; wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                            StyledText { width: parent.width; text: root.currentStationName() || (root.player.path.indexOf("http") === 0 ? "Detecting station…" : ((root.player.playlist || "Queue") + "  •  " + (root.player.index + 1) + "/" + root.player.total)); wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight; color: root.currentStationName() ? Theme.primary : Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                        }
                    }
                }

                SpectrumVisualizer {
                    visible: root.visualizerEnabled
                    width: parent.width
                    readonly property real freeHeight: playingColumn.height - nowPlayingCard.height - seekBlock.height - transportRow.height - playbackOptions.height - playingColumn.spacing * 4
                    height: visible ? Math.max(root.visualizerHeight, freeHeight) : 0
                    bands: root.spectrumBands
                    visualStyle: root.effectiveVisualizer
                }

                Column {
                    id: seekBlock
                    width: parent.width
                    spacing: Theme.spacingXS
                    DankSlider {
                        id: playbackSeek
                        width: parent.width
                        minimum: 0
                        maximum: Math.max(1, root.player.duration)
                        value: Math.round(root.player.position)
                        showValue: false
                        enabled: root.player.duration > 0
                        onSliderDragFinished: finalValue => root.command("seek", ["seek", String(Math.round(finalValue))])
                        Connections {
                            target: root
                            function onPlayerChanged() {
                                if (!playbackSeek.isDragging)
                                    playbackSeek.value = Math.round(root.player.position)
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        StyledText { id: elapsedTime; text: Logic.formatTime(root.player.position); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                        Item { width: Math.max(0, parent.width - elapsedTime.width - durationTime.width); height: 1 }
                        StyledText { id: durationTime; text: Logic.formatTime(root.player.duration); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                    }
                }

                Row {
                    id: transportRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingS
                    ControlButton {
                        readonly property var item: root.currentFavoriteItem()
                        buttonSize: 42
                        iconName: item && root.isFavorite(item) ? "favorite" : "favorite_border"
                        tooltipText: item && root.isFavorite(item) ? "Remove current stream from favorites" : "Favorite current stream"
                        active: item && root.isFavorite(item)
                        enabled: item !== null
                        onClicked: if (item) root.toggleFavorite(item)
                    }
                    ControlButton { buttonSize: 42; iconName: "skip_previous"; tooltipText: "Previous"; onClicked: root.command("previous", ["prev"]) }
                    ControlButton { buttonSize: 42; iconName: root.isPlaying ? "pause" : "play_arrow"; tooltipText: root.isPlaying ? "Pause" : "Play"; active: root.isPlaying; onClicked: root.command("toggle", ["toggle"]) }
                    ControlButton { buttonSize: 42; iconName: "skip_next"; tooltipText: "Next"; onClicked: root.command("next", ["next"]) }
                    ControlButton { buttonSize: 42; iconName: "stop"; tooltipText: "Stop"; onClicked: root.command("stop", ["stop"]) }
                }

                Column {
                    id: playbackOptions
                    width: parent.width
                    spacing: Theme.spacingS
                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        DankIcon {
                            id: volumeIcon
                            name: root.player.volume <= root.volumeMinDb ? "volume_off" : "volume_up"
                            size: 20
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        DankSlider {
                            width: parent.width - volumeIcon.width - parent.spacing
                            minimum: root.percentageVolume ? 0 : root.volumeMinDb
                            maximum: root.percentageVolume ? 100 : root.volumeMaxDb
                            value: root.percentageVolume ? root.volumeDbToPercent(root.player.volume) : root.player.volume
                            unit: root.percentageVolume ? "%" : " dB"
                            onSliderValueChanged: newValue => root.queueVolumeChange(newValue)
                            onSliderDragFinished: finalValue => root.queueVolumeChange(finalValue)
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spacingS
                        ControlButton { buttonSize: root.compactControlSize; iconName: "shuffle"; label: "Shuffle"; active: root.player.shuffle; onClicked: { root.savePlaybackPreference("shuffle", !root.player.shuffle); root.command("shuffle", ["shuffle", "toggle"]) } }
                        ControlButton { buttonSize: root.compactControlSize; iconName: "repeat"; label: root.player.repeat.charAt(0).toUpperCase() + root.player.repeat.slice(1); active: root.player.repeat !== "off"; onClicked: { var next = root.player.repeat === "off" ? "all" : root.player.repeat === "all" ? "one" : "off"; root.savePlaybackPreference("repeat", next); root.command("repeat", ["repeat", "cycle"]) } }
                        ControlButton { buttonSize: root.compactControlSize; iconName: "spatial_audio_off"; label: "Mono"; active: root.player.mono; onClicked: { root.savePlaybackPreference("mono", !root.player.mono); root.command("mono", ["mono", "toggle"]) } }
                    }
                }
            }
        }
    }

    Component {
        id: radioTab
        Column {
            spacing: Theme.spacingS

            StyledText {
                text: "Search internet radio"
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            DankTextField {
                id: radioSearch
                width: parent.width
                leftIconName: "search"
                placeholderText: "Search stations, e.g. Cairo, jazz, BBC"
                showClearButton: true
                onAccepted: root.searchRadio(text)
                onTextChanged: {
                    if (text.trim().length >= 2)
                        searchDelay.restart()
                    else
                        searchDelay.stop()
                }
            }

            Timer { id: searchDelay; interval: 450; repeat: false; onTriggered: root.searchRadio(radioSearch.text) }

            Flow {
                width: parent.width
                spacing: Theme.spacingS
                ControlButton { buttonSize: root.compactControlSize; iconName: "playlist_play"; label: "CLIAMP " + root.cliampStations.length; active: root.radioMode === "cliamp"; onClicked: root.radioMode = "cliamp" }
                ControlButton { buttonSize: root.compactControlSize; iconName: "search"; label: root.radioLoading ? "Searching…" : "Search"; enabled: !root.radioLoading; onClicked: root.searchRadio(radioSearch.text) }
                ControlButton { buttonSize: root.compactControlSize; iconName: "favorite"; label: "Favorites " + root.radioFavorites.length; active: root.radioMode === "favorites"; onClicked: root.radioMode = "favorites" }
                ControlButton { buttonSize: root.compactControlSize; iconName: "history"; label: "Recent"; active: root.radioMode === "recent"; onClicked: root.radioMode = "recent" }
            }

            StyledRect {
                visible: !root.bridgeReady
                width: parent.width
                height: 72
                radius: Theme.cornerRadius
                color: Theme.warningContainer
                Row {
                    anchors.fill: parent; anchors.margins: Theme.spacingM; spacing: Theme.spacingM
                    DankIcon { name: "extension_off"; color: Theme.warning; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { width: parent.width - 150; text: "Install the trusted bridge for immediate radio playback."; wrapMode: Text.WordWrap; anchors.verticalCenter: parent.verticalCenter }
                    ControlButton { iconName: "download"; label: "Install"; onClicked: root.installBridge() }
                }
            }

            StyledText {
                visible: root.radioError.length > 0
                text: root.radioError
                color: Theme.surfaceVariantText
            }

            Item {
                id: stationList
                readonly property var items: root.radioMode === "cliamp" ? root.cliampStations : root.radioMode === "favorites" ? root.radioFavorites : root.radioMode === "recent" ? root.radioRecents : root.radioResults
                width: parent.width
                height: parent.height - y

                Flickable {
                    anchors.fill: parent
                    clip: true
                    contentHeight: stationColumn.height

                    Column {
                        id: stationColumn
                        width: parent.width
                        spacing: Theme.spacingXS
                        Repeater {
                            model: stationList.items
                            delegate: StyledRect {
                                required property var modelData
                                width: stationColumn.width
                                height: 70
                                radius: Theme.cornerRadius
                                color: stationArea.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainerHigh
                                Row {
                                    z: 1
                                    anchors.fill: parent; anchors.margins: Theme.spacingS; spacing: Theme.spacingS
                                    DankIcon { id: stationIcon; name: "radio"; size: 24; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                                    Column {
                                        width: parent.width - stationIcon.width - favoriteSlot.width - parent.spacing * 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        StyledText {
                                            width: parent.width
                                            text: modelData.name
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            font.weight: Font.Medium
                                        }
                                        StyledText {
                                            width: parent.width
                                            text: [modelData.country, modelData.language, modelData.codec + (modelData.bitrate ? " " + modelData.bitrate + "k" : "")].filter(Boolean).join(" • ")
                                            wrapMode: Text.NoWrap
                                            maximumLineCount: 1
                                            elide: Text.ElideRight
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }
                                    Item {
                                        id: favoriteSlot
                                        width: 42
                                        height: parent.height
                                        ControlButton {
                                            anchors.centerIn: parent
                                            iconName: root.isFavorite(modelData) ? "favorite" : "favorite_border"
                                            active: root.isFavorite(modelData)
                                            tooltipText: "Toggle favorite"
                                            buttonSize: 38
                                            onClicked: root.toggleFavorite(modelData)
                                        }
                                    }
                                }
                                MouseArea { id: stationArea; z: 0; anchors.fill: parent; anchors.rightMargin: 50; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.playStation(modelData) }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: libraryTab
        Column {
            spacing: Theme.spacingS
            StyledText { text: "Play a single track"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
            Flow {
                width: parent.width
                spacing: Theme.spacingXS
                Repeater {
                    model: root.trackSearchProviders
                    delegate: ControlButton {
                        required property var modelData
                        buttonSize: 32
                        iconName: modelData.key.indexOf("youtube") >= 0 ? "smart_display" : "music_note"
                        label: modelData.name
                        active: root.trackSearchProvider === modelData.key
                        enabled: root.online && !root.trackSearchLoading
                        onClicked: {
                            root.trackSearchProvider = modelData.key
                            root.trackSearchResults = []
                            root.trackSearchError = ""
                        }
                    }
                }
            }
            Row {
                width: parent.width
                spacing: Theme.spacingS
                DankTextField {
                    id: trackSearch
                    width: parent.width - trackSearchButton.width - parent.spacing
                    leftIconName: "search"
                    placeholderText: "Song, artist, or album"
                    showClearButton: true
                    enabled: root.online && !root.trackSearchLoading
                    onAccepted: root.searchTracks(text)
                }
                ControlButton {
                    id: trackSearchButton
                    buttonSize: root.compactControlSize
                    iconName: "search"
                    label: root.trackSearchLoading ? "Searching…" : "Search"
                    enabled: root.online && !root.trackSearchLoading
                    onClicked: root.searchTracks(trackSearch.text)
                }
            }
            StyledText { visible: root.trackSearchError.length > 0; text: root.trackSearchError; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap }
            Flickable {
                visible: root.trackSearchResults.length > 0
                width: parent.width
                height: visible ? Math.min(180, trackResultColumn.height) : 0
                clip: true
                contentHeight: trackResultColumn.height
                Column {
                    id: trackResultColumn
                    width: parent.width
                    spacing: Theme.spacingXS
                    Repeater {
                        model: root.trackSearchResults
                        delegate: ControlButton {
                            required property var modelData
                            width: trackResultColumn.width
                            buttonSize: 42
                            iconName: "play_arrow"
                            label: (modelData.artist ? modelData.artist + " — " : "") + (modelData.title || "Track")
                            tooltipText: "Play this track now"
                            enabled: root.online
                            onClicked: root.playSearchTrack(modelData)
                        }
                    }
                }
            }
            StyledText { text: "Playlists"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
            Flickable {
                width: parent.width; height: 100; clip: true; contentHeight: playlistColumn.height
                Column {
                    id: playlistColumn; width: parent.width; spacing: Theme.spacingXS
                    StyledText { visible: root.playlists.length === 0; text: "No local playlists found"; color: Theme.surfaceVariantText }
                    Repeater {
                        model: root.playlists
                        delegate: ControlButton { required property string modelData; width: playlistColumn.width; buttonSize: root.compactControlSize; iconName: "playlist_play"; label: modelData; enabled: root.online; onClicked: root.command("loadPlaylist", ["load", modelData]) }
                    }
                }
            }
            Row {
                width: parent.width
                StyledText { text: "Queue"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
                Item { width: parent.width - 110; height: 1 }
                ControlButton { iconName: "refresh"; tooltipText: "Refresh queue"; buttonSize: 34; enabled: root.bridgeReady; onClicked: root.refreshQueue() }
            }
            StyledText { visible: !root.bridgeReady; text: "Install the radio bridge to browse and jump within the queue."; width: parent.width; wrapMode: Text.WordWrap; color: Theme.surfaceVariantText }
            Flickable {
                width: parent.width; height: parent.height - y; clip: true; contentHeight: queueColumn.height
                Column {
                    id: queueColumn; width: parent.width; spacing: Theme.spacingXS
                    Repeater {
                        model: root.queueItems
                        delegate: ControlButton {
                            required property var modelData
                            width: queueColumn.width
                            iconName: Number(modelData.index) === root.player.index ? "equalizer" : "music_note"
                            label: (modelData.artist ? modelData.artist + " — " : "") + (modelData.title || modelData.path || "Track")
                            active: Number(modelData.index) === root.player.index
                            onClicked: root.runCliamp("jump", ["plugins", "call", "cliamp-dms-bridge", "jump", String(modelData.index)], () => { root.refreshStatus(); root.refreshQueue() }, false)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: soundTab
        Flickable {
            clip: true
            contentHeight: soundColumn.height
            Column {
                id: soundColumn
                width: parent.width
                spacing: Theme.spacingM

                StyledText { text: "Playback speed"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
                Row {
                    id: speedRow
                    width: parent.width
                    spacing: Theme.spacingS
                    Repeater {
                        model: [0.75, 1.0, 1.25, 1.5, 2.0]
                        delegate: ControlButton {
                            required property real modelData
                            buttonSize: root.compactControlSize
                            width: (speedRow.width - speedRow.spacing * 4) / 5
                            showIcon: false
                            label: modelData.toFixed(2).replace(/0$/, "") + "×"
                            active: Math.abs(root.player.speed - modelData) < 0.01
                            enabled: root.online
                            onClicked: { root.savePlaybackPreference("speed", modelData); root.command("speed", ["speed", modelData.toFixed(2)]) }
                        }
                    }
                }

                StyledText { text: "Audio output"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
                StyledText { visible: root.devices.length === 0; text: root.online ? "No devices returned" : "Start CLIAMP to list its audio devices"; color: Theme.surfaceVariantText }
                Repeater {
                    model: root.devices
                    delegate: ControlButton { required property var modelData; width: soundColumn.width; buttonSize: root.compactControlSize; iconName: "speaker"; label: modelData.label; active: modelData.active || root.player.device === modelData.name; enabled: root.online; onClicked: root.command("device", ["device", modelData.name]) }
                }

                StyledText { text: "Visualizer"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
                Flow {
                    width: parent.width; spacing: Theme.spacingS
                    Repeater { model: root.visualizers.slice(0, 12); delegate: ControlButton { required property string modelData; buttonSize: root.compactControlSize; iconName: "monitoring"; label: modelData; active: root.effectiveVisualizer.toLowerCase() === modelData.toLowerCase(); enabled: root.online; onClicked: root.setVisualizer(modelData) } }
                }

                Row {
                    width: parent.width
                    StyledText { text: "Equalizer"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Bold }
                    Item { width: parent.width - 148; height: 1 }
                    StyledText { text: root.activeEqPreset; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.spacingS
                    Repeater {
                        model: root.allEqPresets
                        delegate: ControlButton {
                            required property var modelData
                            buttonSize: root.compactControlSize
                            iconName: "equalizer"
                            label: modelData.name
                            active: root.activeEqPreset.toLowerCase() === modelData.name.toLowerCase()
                            enabled: root.online
                            onClicked: root.setEqPreset(modelData)
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: 166
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Row {
                        id: equalizerRow
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        anchors.topMargin: Theme.spacingS
                        spacing: 0

                        Repeater {
                            model: ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
                            delegate: EqualizerBand {
                                required property string modelData
                                required property int index
                                width: equalizerRow.width / 10
                                bandIndex: index
                                frequency: modelData
                                value: Number(root.eqBands[index] || 0)
                                enabled: root.online
                                onValueCommitted: value => root.setEqBand(index, value)
                            }
                        }
                    }
                }

            }
        }
    }

    Component {
        id: providersTab
        Column {
            spacing: Theme.spacingS
            StyledText { width: parent.width; text: root.online ? "Provider changes apply the next time you launch CLIAMP from this widget." : "Choose the provider for Launch CLIAMP."; wrapMode: Text.WordWrap; color: Theme.surfaceVariantText }
            ControlButton { buttonSize: root.compactControlSize; iconName: "add_link"; label: "Connect or update a provider"; onClicked: root.setupProvider() }
            Flickable {
                width: parent.width; height: parent.height - y; clip: true; contentHeight: providerColumn.height
                Column {
                    id: providerColumn; width: parent.width; spacing: Theme.spacingXS
                    Repeater {
                        model: root.providers
                        delegate: StyledRect {
                            required property var modelData
                            width: providerColumn.width; height: 50; radius: Theme.cornerRadius
                            color: providerArea.containsMouse ? Theme.primaryHoverLight : Theme.surfaceContainerHigh
                            border.width: String(root.pluginData.launchProvider || "radio") === modelData.id ? 1 : 0
                            border.color: Theme.primary
                            Row {
                                anchors.fill: parent; anchors.margins: Theme.spacingS; spacing: Theme.spacingS
                                DankIcon { name: modelData.id === "radio" ? "radio" : "cloud"; color: modelData.configured ? Theme.primary : Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                                Column {
                                    width: parent.width - 52; anchors.verticalCenter: parent.verticalCenter
                                    StyledText { text: modelData.id.charAt(0).toUpperCase() + modelData.id.slice(1); font.weight: Font.Medium }
                                    StyledText { text: modelData.configured ? "Configured" : "Not configured"; color: modelData.configured ? Theme.primary : Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                                }
                                DankIcon { name: String(root.pluginData.launchProvider || "radio") === modelData.id ? "radio_button_checked" : "radio_button_unchecked"; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { id: providerArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.saveLaunchProvider(modelData.id) }
                        }
                    }
                }
            }
        }
    }
}
