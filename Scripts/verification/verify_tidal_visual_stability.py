import argparse
from pathlib import Path
import platform
import sys
import tempfile


if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))
from harness import BudgetProvider, LocalToolRunner

TOOLS = LocalToolRunner("host", budgets=BudgetProvider())


def run(verb, command):
    completed = TOOLS.run(verb, command)
    if completed.returncode != 0:
        raise SystemExit(f'{verb} failed with {completed.returncode}: {completed.stderr.strip()}')
    return completed.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, default=Path('tmp/archive/tidal/visual-stability'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    scene = root / 'Packages/TidalEnvironment/Sources/TidalEnvironment/Resources/tidal.reality'
    with tempfile.TemporaryDirectory(prefix='gpu-check-', dir=output) as temporary:
        binary = Path(temporary) / 'verify'
        run('host-swift-compile', [
            'xcrun', 'swiftc', '-swift-version', '6', '-default-isolation', 'MainActor',
            '-parse-as-library', '-target', f'{platform.machine()}-apple-macos27.0',
            str(Path(__file__).with_name('TidalVisualStabilityVerification.swift')), '-o', str(binary)
        ])
        run('host-swift-run', [str(binary), str(args.baseline.resolve()), str(scene), str(output)])


if __name__ == '__main__':
    main()
