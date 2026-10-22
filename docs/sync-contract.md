# FocusPilot Sync Contract

The vault repository is an encrypted, append-oriented data source. A client starts with `vault/manifest.json`, downloads the referenced snapshot when present, then applies every envelope in `vault/operations/` whose device sequence is above the snapshot frontier.

Clients decrypt envelopes locally with the exported 256-bit recovery key. The key must never be committed, uploaded to Netlify, included in logs, or sent to a sync endpoint.

Netlify can generate a static index of snapshot and operation filenames during its build. Static hosting supports reads only. A future write endpoint must authenticate the user, accept an already-encrypted immutable operation, validate its envelope shape and unique filename, commit it through the Git provider API, and never decrypt it.

Compaction creates and verifies a complete encrypted snapshot before deleting covered operations from the latest branch. Normal Git history remains intact, so older files can still be restored from previous commits.
