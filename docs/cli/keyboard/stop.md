# `ed keyboard stop`

Unlocks the keyboard and closes the overlay, the same as clicking Done
cleaning. It does nothing when the keyboard is already unlocked.

```
ed keyboard stop [--json]
```

| Name | Type / values | Default | What it does |
| --- | --- | --- | --- |
| `--json` | flag | off | Emit the status document from [`ed keyboard status`](./status.md) on stdout. |

Without `--json` it prints `keyboard is unlocked`.

## Where to go next

- [`ed keyboard`](./README.md), the rest of this group
- [All `ed` commands](../README.md)
