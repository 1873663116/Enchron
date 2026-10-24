# CI machine preparation

## Environment preparation

`Scripts/ci/prepare.sh` is the only place that prepares a machine to run a
check. Both workflows source it with `ci` from the tree they just checked out,
the push hook and the three Xcode build phases take `shell --emit`, which prints
the export lines they eval.

The workflows own the four git commands that produce the tree — worktree, fetch,
checkout — because the script cannot exist before the tree does. Everything
after that comes from the script at the revision under test: the empty virtual
environment under the workspace, the clean that keeps `.build`, `.scratch/build`,
`.scratch/console`, `.scratch/DerivedData` and `.scratch/SourcePackages`, the
vendored binary links, and the `.env` copy the full tier needs.

Four details are load-bearing and look removable:

- The virtual environment is created with `--without-pip` and an empty
  `site-packages`. A stray `.pth` from an unrelated editable install points into
  `~/Documents`, and every interpreter start blocked there for the whole job
  budget. `PYTHONPATH` still reaches numpy and Pillow without making that
  directory a site directory, which is what would execute the `.pth` again.
- The build directories survive the clean because deleting the multi-gigabyte
  tree costs more than the job's time budget on this volume. `.scratch/build`
  also keeps the build-tier fingerprint and the compiler stringsdata, so the
  localization check reuses the build instead of compiling again.
- `.env` is copied only for the full tier, with traps for `EXIT`, `INT` and
  `TERM`, so a cancelled job still removes it. Only a `SIGKILL` escapes, and the
  next run's clean is the backstop.
- The main checkout is the git database the CI worktree hangs off, and the
  source of the two vendored binaries. A cloud runner has neither, so it clones
  and provisions them by a different path.


## Identity and credentials

`Config/test_service_identities.json` names every variable that carries an
identity and the service it belongs to. The registry holds names, never values.
Values live in the environment or in `.env`, which is ignored.

`Scripts/rules/verify_test_service_identities.py` reads the registry and reports
three things: a variable that appears in the tree but not in the registry, a
value from the environment found anywhere in the tree, and four credential
shapes that need no registry at all — a private key block, a credential inside a
URL, a literal authorization header, a certificate fingerprint.

A new supplier is one registry entry. A supplier that is never registered fails
on its first commit, which is the point: forgetting to maintain the registry is
an error, not a silent gap.

The identity classes in `check_no_literal_rfc1918.py` read the account name from
`EMBY_USER`, `SMB_USER` and `WEBDAV_USER` instead of carrying the literal. When
none is set, that scan reports nothing and the shape rules still run.

