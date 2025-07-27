# Security Update Required

## glib Vulnerability

A security vulnerability has been identified in the `glib` crate:
- **Affected versions**: >= 0.15.0, < 0.20.0
- **Current version**: 0.18.5 (transitive dependency)
- **Patched version**: 0.20.0

## Action Required

Run the following command to update dependencies:

```bash
cd server/hostapp/src-tauri
cargo update -p glib
```

This will update the Cargo.lock file to use glib 0.20.0 or later.

## Temporary Patch

A patch has been added to Cargo.toml to enforce glib >= 0.20.0:

```toml
[patch.crates-io]
glib = "0.20.0"
```

However, this requires running `cargo build` or `cargo update` to take effect.