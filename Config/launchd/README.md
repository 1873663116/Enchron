# Install the nightly verification gate

The user LaunchAgent runs the complete verification gate every day at 03:00 local time. Each run writes its command logs, machine-readable summary, and source parity result under `/Volumes/Cortisol/DevSpace/Xcode/Enchron/VerificationGauntlet/runs`. The gate retains the newest 14 run directories.

The committed plist contains this worktree's absolute path. Update the plist before installation if the worktree moves.

## Install or update the LaunchAgent

Run these commands from the repository root:

```sh
mkdir -p /Volumes/Cortisol/DevSpace/Xcode/Enchron/VerificationGauntlet/runs
mkdir -p "$HOME/Library/LaunchAgents"
cp Config/launchd/com.enchron.verification-gauntlet.plist \
  "$HOME/Library/LaunchAgents/com.enchron.verification-gauntlet.plist"
launchctl bootout "gui/$(id -u)/com.enchron.verification-gauntlet" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.enchron.verification-gauntlet.plist"
```

The next scheduled run starts at 03:00. To run it now, use:

```sh
launchctl kickstart -k "gui/$(id -u)/com.enchron.verification-gauntlet"
```

Inspect the newest `summary.json` under the run directory for the final verdict. `launchd.stdout.log` and `launchd.stderr.log` contain startup output that precedes creation of a run directory.

## Remove the LaunchAgent

Run:

```sh
launchctl bootout "gui/$(id -u)/com.enchron.verification-gauntlet"
rm "$HOME/Library/LaunchAgents/com.enchron.verification-gauntlet.plist"
```
