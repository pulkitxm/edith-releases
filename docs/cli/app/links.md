# `ed app links`

Lists the external links already shown by Edith.

```
ed app links [--json]
```

The fixed ids are `creator`, `community:bug` (Report a bug), `community:feature`
(Request a feature) and `community:discussions` (Discussions). Extension
lifecycle guides add ids in the form `extension-doc:<extension>:<document>`.
Community and guide links go through `https://edith.pulkit.page/api/v1`, which
redirects to the public pages. Plain output shows id, label, and URL.
JSON is an array whose rows have `id`, `label`, and `url`.

This read needs no running app. Use an id with [`ed app open-link`](./open-link.md).

## Where to go next

- [`ed app`](./README.md), the rest of this group
- [All `ed` commands](../README.md)
