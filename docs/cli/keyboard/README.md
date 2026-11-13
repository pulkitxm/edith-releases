# `ed keyboard`

`ed keyboard` belongs to the Keyboard Clean extension. It locks the keyboard
behind a full-screen overlay so you can wipe the keys without typing into the
app in front. The lock arms after a 3 second countdown, shows on every display,
and releases when you click Done cleaning, run `ed keyboard stop`, or after 60
seconds.

Install the extension with `ed extensions install keyboardClean`. The same
action is the Clean keys button in the sidebar, the Clean keys tile in the notch
and on Home, and Start cleaning mode in the extension's settings.

## At a glance

| Command | What it does |
| --- | --- |
| `ed keyboard status` | Prints whether the keyboard is locked and whether Input Monitoring and Accessibility are allowed. Runs when you type `ed keyboard` with no subcommand. |
| `ed keyboard clean` | Shows the overlay and locks the keyboard after the countdown. |
| `ed keyboard stop` | Unlocks the keyboard and closes the overlay. |

## Commands

- [`ed keyboard status`](./status.md)
- [`ed keyboard clean`](./clean.md)
- [`ed keyboard stop`](./stop.md)

## Exit codes

| Code | When |
| --- | --- |
| 0 | The status was printed, the lock started, or the keyboard was unlocked. |
| 2 | The command line was wrong: an unknown flag or an extra argument. |
| 4 | Keyboard Clean is not installed or enabled, or `clean` is missing Input Monitoring or Accessibility. The hint names the `ed permissions request` command to run. |

## Notes and gotchas

- Input Monitoring lets Edith see key presses and Accessibility lets it stop
  them. `clean` asks macOS for the first missing one and exits 4 instead of
  showing an overlay that cannot lock anything.
- Mouse clicks still work while the keyboard is locked, so Done cleaning is
  always reachable.
- After allowing a permission in System Settings, relaunch Edith if `status`
  still reports it as not allowed.

## Where to go next

- [`ed permissions`](../permissions/README.md) for Input Monitoring and
  Accessibility
- [`ed extensions`](../extensions/README.md) for installing and enabling Keyboard Clean
- [All `ed` commands](../README.md)
