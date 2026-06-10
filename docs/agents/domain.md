# Domain docs

## Layout

This repo uses a **single-context** layout:

- `CONTEXT.md` at the repo root — the project's domain language and key concepts.
- `docs/adr/` — architectural decision records.

> Note: `CONTEXT.md` is live at the repo root (migrated from `docs/ubiquitous_language.md`,
> which remains as a pointer stub). `docs/adr/` is live; see its README for when to write
> an ADR. Consult `ARCHITECTURE.md` for module ownership and invariants.

## How agents consume these

- Before architectural work, read `CONTEXT.md` to learn the domain language.
- Before making a decision that has long-term structural impact, check `docs/adr/` for prior decisions.
- When a decision is made, record it as a new ADR in `docs/adr/`.
- Keep `CONTEXT.md` terminology consistent with the code.
