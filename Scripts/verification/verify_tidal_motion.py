import argparse
from pathlib import Path
import platform
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-directory', type=Path, default=Path('tmp/archive/tidal/motion/gpu'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = root / 'Packages/TidalEnvironment/Sources/TidalEnvironment'
    flags = ['xcrun', 'swiftc', '-swift-version', '6', '-default-isolation', 'MainActor',
             '-parse-as-library', '-target', f'{platform.machine()}-apple-macos27.0']
    with tempfile.TemporaryDirectory(prefix='motion-check-', dir=output) as temporary:
        directory = Path(temporary)
        subprocess.run(flags + ['-emit-module', '-emit-library', '-module-name', 'EnvironmentSceneContract',
                                str(root / 'Packages/EnvironmentSceneContract/Sources/EnvironmentSceneContract/EnvironmentScene.swift'),
                                '-emit-module-path', str(directory / 'EnvironmentSceneContract.swiftmodule'),
                                '-o', str(directory / 'libEnvironmentSceneContract.dylib')], check=True, cwd=root)
        developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
        frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
        subprocess.run(flags + ['-emit-module', '-emit-library', '-enable-testing', '-module-name', 'TidalEnvironment',
                                str(source / 'TidalMotionTimeline.swift'), '-I', str(directory), '-L', str(directory),
                                '-lEnvironmentSceneContract', '-Xlinker', '-rpath', '-Xlinker', str(directory),
                                '-emit-module-path', str(directory / 'TidalEnvironment.swiftmodule'),
                                '-o', str(directory / 'libTidalEnvironment.dylib')], check=True, cwd=root)
        runner = directory / 'TestMain.swift'
        runner.write_text('import Testing\nimport Darwin\n@main struct TestMain { static func main() async { let code: CInt = await __swiftPMEntryPoint(); exit(code) } }\n')
        test_binary = directory / 'timeline-tests'
        subprocess.run(flags + [str(root / 'Tests/PlaybackPresentationTests/TidalMotionTimelineTests.swift'), str(runner),
                                '-I', str(directory), '-L', str(directory), '-lTidalEnvironment', '-lEnvironmentSceneContract',
                                '-plugin-path', str(developer / 'Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing'),
                                '-F', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(frameworks),
                                '-Xlinker', '-rpath', '-Xlinker', str(directory), '-o', str(test_binary)], check=True, cwd=root)
        subprocess.run([str(test_binary)], check=True, cwd=root)
        sources = ['TidalDarkParameters.swift', 'TidalDarkMaterial.swift', 'TidalMotionTimeline.swift',
                   'TidalEnvironmentRuntime.swift', 'TidalScenePlacement.swift']
        binary = directory / 'verify'
        subprocess.run(flags + [str(source / name) for name in sources]
                       + [str(Path(__file__).with_name('TidalMotionGPUVerification.swift')),
                          '-I', str(directory), '-L', str(directory), '-lEnvironmentSceneContract',
                          '-Xlinker', '-rpath', '-Xlinker', str(directory), '-o', str(binary)], check=True, cwd=root)
        subprocess.run([str(binary), str(output)], check=True, cwd=root)


if __name__ == '__main__':
    main()
