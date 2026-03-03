# XRPlayer (Codename)

This repository contains the OMC -> Codex migration scaffold for XRPlayer workflows.

## What is migrated

- OMC skill packs copied into Codex skill home with `omc-` prefix (to avoid collisions)
- A repeatable sync script for future updates
- Notes on compatibility gaps between OMC plugin hooks and Codex runtime

## Quick start

```bash
bash scripts/sync_omc_skills_to_codex.sh
```

## Current status

- Skills migration: bootstrapped
- Plugin hook migration: partial (needs adapter layer)
- GitHub workflow: enabled

## Rename note

You can rename this repository later in GitHub settings. Existing clone URLs are automatically redirected by GitHub.
