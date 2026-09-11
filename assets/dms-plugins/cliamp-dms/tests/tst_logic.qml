import QtQuick
import QtTest
import "../Logic.js" as Logic

TestCase {
    name: "CliampLogic"
    when: true

    function test_safeJson() {
        compare(Logic.safeJson('{"ok":true}', {}).ok, true)
        compare(Logic.safeJson('bad', {fallback: true}).fallback, true)
    }

    function test_statusNormalization() {
        var value = Logic.normalizedStatus('{"ok":true,"state":"playing","track":{"title":"Song","artist":"Artist","album_art_url":"https://art"},"position":5,"duration":10,"volume":-3,"eq_bands":[1,2,3,4,5,6,7,8,9,10]}')
        compare(value.title, "Song")
        compare(value.artist, "Artist")
        compare(value.position, 5)
        compare(value.volume, -3)
        compare(value.artUrl, "https://art")
        compare(value.eqBands[9], 10)
        compare(Logic.normalizedStatus('{"ok":false}'), null)
    }

    function test_customEqPresets() {
        var value = Logic.parseEqPresets('[{"name":" Warm ","bands":[20,-20,1,2,3,4,5,6,7,8]},{"name":"Broken","bands":[1]}]')
        compare(value.length, 1)
        compare(value[0].name, "Warm")
        compare(value[0].bands[0], 12)
        compare(value[0].bands[1], -12)
    }

    function test_stationNormalizationAndDedupe() {
        var value = Logic.normalizeStations('[{"stationuuid":"a","name":"One","url":"https://one"},{"stationuuid":"a","name":"Duplicate","url":"https://two"},{"name":"Missing"}]')
        compare(value.length, 1)
        compare(value[0].name, "One")
    }

    function test_recentOrdering() {
        var a = {uuid: "a"}
        var b = {uuid: "b"}
        var value = Logic.upsertRecent([a, b], b, 20)
        compare(value.length, 2)
        compare(value[0].uuid, "b")
        compare(value[1].uuid, "a")
    }

    function test_stationMerge() {
        var first = {uuid: "same", name: "Bundled"}
        var duplicate = {uuid: "same", name: "Remote"}
        var other = {uuid: "other", name: "Other"}
        var value = Logic.mergeStations([first], [duplicate, other])
        compare(value.length, 2)
        compare(value[0].name, "Bundled")
        compare(value[1].name, "Other")
    }

    function test_providerParsing() {
        var value = Logic.providerLines("radio|1\nspotify|0\n")
        compare(value.length, 2)
        compare(value[0].configured, true)
        compare(value[1].configured, false)
    }

    function test_playlistAndDeviceParsing() {
        var playlists = Logic.playlistLines("Focus (12 tracks)\nRadio (1 track)\nCLIAMP Streams   11 tracks\n")
        compare(playlists[0], "Focus")
        compare(playlists[1], "Radio")
        compare(playlists[2], "CLIAMP Streams")
        var devices = Logic.deviceLines("* Built-in Audio                                    default\n  USB DAC                                           hw:2,0\n")
        compare(devices.length, 2)
        compare(devices[0].active, true)
        compare(devices[0].name, "default")
        compare(devices[1].name, "hw:2,0")
    }

    function test_timeFormatting() {
        compare(Logic.formatTime(0), "0:00")
        compare(Logic.formatTime(65), "1:05")
    }
}
