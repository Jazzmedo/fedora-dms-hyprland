import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("cliampDms.dependencies", ["sh", "-c", "(command -v cliamp >/dev/null || [ -x \"$HOME/.local/bin/cliamp\" ] || [ -x /usr/local/bin/cliamp ] || [ -x /usr/bin/cliamp ]) && command -v curl >/dev/null && command -v ffprobe >/dev/null && command -v gjs >/dev/null && command -v gdbus >/dev/null && command -v systemd-run >/dev/null"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null)
                return
            }
            done({
                title: "Cliamp Controller dependencies are missing",
                details: "Install CLIAMP, curl, FFmpeg (ffprobe), GJS, GLib (gdbus), and systemd, then enable this plugin again."
            })
        })
    }
}
