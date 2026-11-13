# `ed keyboard clean`

Shows the cleaning overlay on every display and locks the keyboard after a 3
second countdown, so you can wipe the keys without typing anything.

```
ed keyboard clean [--json]
```

| Name | Type / values | Default | What it does |
| --- | --- | --- | --- |
| `--json` | flag | off | Emit JSON on stdout. |

Without `--json` it prints `keyboard cleaning is arming`. `--json` shape:

```json
{
  "action": "clean",
  "state": "arming",
  "status": {
    "armingCountdown": 3,
    "failsafeRemaining": 0,
    "hasAccessibility": true,
    "hasInputMonitoring": true,
    "message": null,
    "phase": "arming"
  }
}
```

Running it again while the lock is arming or active reports the current state
and starts nothing new. Missing Input Monitoring or Accessibility exits 4 with a
hint such as `run ed permissions request inputMonitoring`.

## Where to go next

- [`ed keyboard`](./README.md), the rest of this group
- [All `ed` commands](../README.md)
