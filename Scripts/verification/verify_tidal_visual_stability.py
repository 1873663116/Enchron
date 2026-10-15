import argparse
from pathlib import Path
import platform
import subprocess
import tempfile


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
        subprocess.run([
            'xcrun', 'swiftc', '-swift-version', '6', '-default-isolation', 'MainActor',
            '-parse-as-library', '-target', f'{platform.machine()}-apple-macos27.0',
            str(Path(__file__).with_name('TidalVisualStabilityVerification.swift')), '-o', str(binary)
        ], check=True, cwd=root)
        subprocess.run([str(binary), str(args.baseline.resolve()), str(scene), str(output)], check=True, cwd=root)


if __name__ == '__main__':
    main()
