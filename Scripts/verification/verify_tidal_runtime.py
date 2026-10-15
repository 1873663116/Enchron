import argparse
from pathlib import Path
import platform
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-directory', type=Path, default=Path('tmp/archive/tidal/runtime-verification'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sources = root / 'Packages/TidalEnvironment/Sources/TidalEnvironment'
    with tempfile.TemporaryDirectory(prefix='gpu-check-', dir=output) as temporary:
        binary = Path(temporary) / 'verify'
        subprocess.run([
            'xcrun', 'swiftc', '-swift-version', '6', '-default-isolation', 'MainActor',
            '-parse-as-library', '-target', f'{platform.machine()}-apple-macos27.0',
            str(sources / 'TidalDarkParameters.swift'), str(sources / 'TidalDarkMaterial.swift'),
            str(root / 'Scripts/verification/TidalRuntimeGPUVerification.swift'), '-o', str(binary)
        ], check=True, cwd=root)
        subprocess.run([str(binary), str(output / 'gpu-samples.json')], check=True, cwd=root)


if __name__ == '__main__':
    main()
