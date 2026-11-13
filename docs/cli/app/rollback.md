# `ed app rollback`

Go back to the most recent Edith version that worked on this Mac.

```
ed app rollback [--yes] [--json]
```

| Name | Type / values | Default | What it does |
| --- | --- | --- | --- |
| `--yes` | flag | off | Replace the app with the saved version; otherwise print a preview. |
| `--json` | flag | off | Emit JSON on stdout. |

Edith keeps a copy of the running version in
`~/Library/Application Support/Edith/backups` right before Sparkle installs an
update, and the updater script keeps one too. The rollback target is the newest
saved copy whose build is not the running one and never failed its startup
check. The command fails when there is none.

The CLI performs the rollback itself, so it works when the app is not
answering. It first checks the saved copy's signature: it must pass
`codesign --verify --deep --strict`, carry the same team as the running app
and, for a team-signed app, pass Gatekeeper; otherwise nothing changes. It then
starts a detached helper in its own session (so closing the terminal does not
stop it), records the running build as failed, sets Sparkle's
`SUSkippedVersion` so that build is not installed again automatically (a newer
one still is), and asks the app to quit. The helper replaces the app bundle once
it has left (stopping it after 15 seconds if it does not) and opens the restored
version. It deletes the replaced app only after the restored one is running,
and puts it back if the restored one does not start within 30 seconds. When the
install folder is not writable nothing is recorded or changed. Settings, data
and extensions are not touched.

```
ed app rollback
ed app rollback --yes
ed app rollback --yes --json
```

`--json` shape:

```json
{
  "action": "rollback",
  "applied": true,
  "changed": true,
  "from": "1.0.19",
  "path": "/Applications/Edith.app",
  "to": "1.0.18"
}
```

A preview has `applied` and `changed` set to `false` and `requiresConfirmation`
set to `true`.

On the first launch of a new version the app checks itself: every enabled
extension that was running or idle on the previous version must be running or
idle within 120 seconds and stay that way for 20 more, with the main thread
responsive throughout. Extensions that were already failing before the update
do not count against it. The previous version's usable extensions are recorded
in `update-health.json` when Edith saves its copy before an update and when a
version passes the check. When the check fails, the build is recorded as failed
and skipped the same way, and the app shows one prompt offering to go back to
the saved version, if that copy passes the signature check above. The updater
script launches the app with `EDITH_UPDATE_SUPERVISED=1`, which keeps the check
but leaves the prompt to the script. `ed app info --json` reports the check in
`updateHealth` (`state` is `checking`, `healthy` or `failed`, with `reason` and
`rollbackVersion`).

## Where to go next

- [`ed app`](./README.md), the rest of this group
- [All `ed` commands](../README.md)
