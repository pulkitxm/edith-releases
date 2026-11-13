# `ed keyboard status`

Prints whether the keyboard is locked for cleaning and whether the two
permissions it needs are allowed. It is the default subcommand, so
`ed keyboard` on its own runs it.

```
ed keyboard status [--json]
```

| Name | Type / values | Default | What it does |
| --- | --- | --- | --- |
| `--json` | flag | off | Emit JSON on stdout instead of the table. |

```
$ ed keyboard status
FIELD             VALUE
keyboard          unlocked
input monitoring  allowed
accessibility     allowed
```

`--json` shape:

```json
{
  "armingCountdown": 0,
  "failsafeRemaining": 0,
  "hasAccessibility": true,
  "hasInputMonitoring": true,
  "message": null,
  "phase": "idle"
}
```

`phase` is `idle`, `arming` during the countdown, or `cleaning` while the keys
are locked. `failsafeRemaining` counts down from 60 while cleaning. Nothing is
changed.

## Where to go next

- [`ed keyboard`](./README.md), the rest of this group
- [All `ed` commands](../README.md)
