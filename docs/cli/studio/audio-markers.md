# `ed studio audio-markers`

[Studio](./README.md) · [All CLI commands](../README.md)

Create and edit named regions for one standalone audio file. Projects use the
`.edithaudio` extension and refer to the original absolute source path. The
source must remain available with the same sample rate and frame count. Audio
bytes are never written by these actions.

```sh
ed studio audio-markers create fixture.wav session.edithaudio
ed studio audio-markers show session.edithaudio
ed studio audio-markers set session.edithaudio --revision <revision> --label Intro --start 0 --end 2
ed studio audio-markers set session.edithaudio --revision <revision> --label Outro --start 28 --end 30
ed studio audio-markers set session.edithaudio --revision <revision> --id <region-id> --label Intro --start 0 --end 1.5
ed studio audio-markers remove session.edithaudio --revision <revision> --id <region-id>
ed studio audio-markers export session.edithaudio --output cues.tsv
```

Every action returns the current project as JSON. Use its `revision` for the
next edit. A stale revision fails without changing the project. `set` adds a
region when `--id` is omitted and updates the matching region otherwise. `show`
reopens and validates the saved project and source. Add `--json` for structured
errors.

Start is inclusive and end is exclusive, in seconds. Values round to the nearest
source sample. Both must be within the source duration and end must follow start
after rounding. Projects retain integer sample positions and the source sample
rate. Regions may overlap. Labels must contain 1 to 256 UTF-8 bytes without
control characters; projects hold at most 1,000 regions.

`export` writes a new UTF-8 `.tsv` cue sheet sorted by start, end and ID. Each
line contains start seconds, end seconds and label, separated by tabs. Seconds
use a decimal point and nine fractional digits. There is no header. Creation
and export refuse existing destination files. Project edits save atomically.

The equivalent invoke actions are `studio.audio.create` (`source`, `path`),
`studio.audio.show` (`path`), `studio.audio.set` (`path`, `revision`, optional
`id`, `label`, `start`, `end`), `studio.audio.remove` (`path`, `revision`, `id`),
and `studio.audio.export` (`path`, `output`). Invoke paths must be absolute local
paths. Studio's UI uses the same actions through `studio.ui.audio.*`.
