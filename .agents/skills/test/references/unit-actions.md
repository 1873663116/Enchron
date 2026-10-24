# Unit and action semantics

`device.probe` fails when no element carries the identifier it names, so a probe cannot pass without proving the element exists.

`Config/console/known-failures.md` declares a defect that predates the console: an entry names a unit and a phrase the failing step must contain, and a run that matches reports the verdict `known` with exit code 7 instead of turning the tier red. Delete the entry when the defect is gone.

`"isolation": "clean-library"` makes the compiler put a `clearMediaLibrary` command right after the session step, so every unit starts from an empty library instead of whatever the last run left behind.

A unit may declare `teardown`, steps that run whether the earlier steps passed or failed; put library cleanup there so a failed run cannot leave a big library that slows every later command.

`device.home` leaves playback and brings the library home to the front, so a unit never depends on the screen the previous unit left behind.

A unit may declare `preconditions: [{kind: media-progress}]` to give the seeded episodes the viewing progress a home journey needs.

`device.command` takes `label` and `labelPrefix`. The exact label wins; when it is absent the harness taps the first element whose label starts with the prefix.

`device.await` also takes `equals` as an object of field names to values, so one probe can wait for several control plane fields at once.

`device.await` takes `probe: element` with `field` set to `identifier` or `label` and waits until that element appears in the hierarchy. Use it before tapping anything a menu just revealed.

A tap that misses because the element is not yet hittable is retried three times. A drain of the DEBUG probe journal is answered by one relaunch and one retry.

A unit whose subject is playback, not browsing, opens media with the `playMedia` app command instead of tapping the tab, the folder, and the card; that saves three taps per unit.

`device.app-commands` runs a list of app commands in one round trip; three ping commands cost about as much as one.

`device.command` takes `waitMilliseconds`, so a tap waits for the element instead of a separate await step.

A step may carry `capture`, a map from payload field to name. A later step reads that name as `"$name"` in any argument string. The compiler refuses a reference that no earlier step captures (`C018`) and a name captured twice.

A unit may carry `pace`: `fast`, `slow` or `catalog`. `console tier e2e --quick` runs the fast ones, the plain tier runs fast and slow, and `--full` adds the catalog ones a scenario generated. `console tier e2e --quick` runs the fast ones only; the media-import and playback units are slow.

A unit may carry `preconditions`, the closed set of environment checks that must hold before the first step. `media-server` resolves one provider through `Scripts/verification/ensure_test_services.py`; the run records the receipt in `preconditions.json` and stops with verdict `precondition` when one is unmet.
