# Domain docs

## Layout

This repo uses a **single-context** layout:

- `CONTEXT.md` at the repo root — the project's domain language and key concepts.
- `docs/adr/` — architectural decision records.

> Note: as of setup, `CONTEXT.md` and `docs/adr/` do not yet exist. The existing
> terminology source is `docs/ubiquitous_language.md`; treat it as the seed for
> `CONTEXT.md`, and consult `ARCHITECTURE.md` for module ownership and invariants.

## How agents consume these

- Before architectural work, read `CONTEXT.md` (or `docs/ubiquitous_language.md` until it exists) to learn the domain language.
- Before making a decision that has long-term structural impact, check `docs/adr/` for prior decisions.
- When a decision is made, record it as a new ADR in `docs/adr/`.
- Keep `CONTEXT.md` terminology consistent with the code and with `docs/ubiquitous_language.md`.
