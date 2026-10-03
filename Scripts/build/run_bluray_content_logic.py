#!/usr/bin/env python3
"""Run production disc-content projection and its Swift tests without a UI host.

The native library compiles the actual MediaLibrary projection source; it does
not reproduce its algorithm. App view models and UI require separate simulator
tests. Core's built objects must come from the current source first.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def run(command: list[str], log: Path) -> None:
    with log.open("w") as output:
        subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--disc", action="append", default=[])
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    core = ROOT / "Packages/PlaybackCore"
    products = core / ".build/out/Products/Debug"
    module_map = core / ".build/out/Intermediates.noindex/GeneratedModuleMaps/BluRayDiscBridge.modulemap"
    inputs = [products / "BluRayDisc.o", products / "BluRayDiscBridge.o", module_map]
    if any(not path.is_file() for path in inputs):
        parser.error("Build PlaybackCore's BluRayDiscTests for macOS first.")
    target = json.loads(subprocess.check_output(
        ["xcrun", "swiftc", "-print-target-info"], text=True
    ))["target"]["triple"]
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
    plugin = developer / "Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
    common = ["xcrun", "swiftc", "-target", target, "-parse-as-library",
              "-I", str(products), "-F", str(frameworks),
              "-load-plugin-library", str(plugin),
              "-Xcc", f"-fmodule-map-file={module_map}"]
    library = output / "libMediaLibrary.dylib"
    run(common + ["-emit-library", "-emit-module", "-enable-testing", "-module-name", "MediaLibrary",
        str(ROOT / "Modules/MediaLibrary/Model/BluRayDiscContent.swift"),
        str(products / "BluRayDisc.o"), str(products / "BluRayDiscBridge.o"),
        str(core / "Vendor/BluRay/PlaybackBluRay.xcframework/macos-arm64/libPlaybackBluRay.a"),
        "-liconv", "-lz", "-o", str(library)], output / "projection-build.log")
    executable = output / "BluRayContentLogicProbe"
    run(common + ["-I", str(output), "-L", str(output), "-lMediaLibrary",
        "-Xlinker", "-rpath", "-Xlinker", str(output),
        "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
        str(ROOT / "Tests/MediaLibraryPackageTests/BluRayDiscContentTests.swift"),
        str(ROOT / "Scripts/verification/bluray_content_logic_probe.swift"),
        "-o", str(executable)], output / "tests-build.log")
    run([str(executable), "--testing-library", "swift-testing", "--no-parallel"], output / "tests.log")
    if args.disc:
        with (output / "projections.jsonl").open("w") as result, (output / "probe.stderr.log").open("w") as diagnostic:
            subprocess.run([str(executable), *args.disc], cwd=ROOT,
                           stdout=result, stderr=diagnostic, check=True)
    print(f"Disc-content logic passed. Evidence: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
