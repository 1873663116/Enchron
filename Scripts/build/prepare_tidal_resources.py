import argparse
import hashlib
import json
import importlib.util
import sys
import shutil
from pathlib import Path
import subprocess
import tempfile
import zipfile


def run(*arguments):
    subprocess.run([str(argument) for argument in arguments], check=True)


def validate_atlas(reference_path, scene_path):
    import cv2
    import numpy as np

    reference = cv2.imdecode(np.fromfile(reference_path, np.uint8), cv2.IMREAD_UNCHANGED)
    scene = cv2.imdecode(np.fromfile(scene_path, np.uint8), cv2.IMREAD_UNCHANGED)
    if reference is None or scene is None or reference.shape[:2] != scene.shape[:2]:
        raise ValueError('The scene and delivery atlases must have the same dimensions')
    if reference.dtype != np.uint16 or scene.dtype != np.uint8:
        raise ValueError('Expected a 16-bit delivery atlas and an 8-bit scene atlas')
    for row in range(0, scene.shape[0], 128):
        expected = np.clip(np.rint(reference[row:row + 128, :, :3].astype(np.float32) * np.float32(255 / 65535)), 0, 255).astype(np.uint8)
        if not np.array_equal(expected, scene[row:row + 128, :, :3]):
            raise ValueError('The dark parameters do not match the scene light atlas')


def water_textures(workspace, atlas_path, staging):
    import cv2
    import numpy as np

    source = workspace / 'scratch/sky_pool_import/sky_pool.usdc'
    project = workspace / 'scenes/sykpool.realitycomposerpro'
    extractor = workspace / 'scripts/tools/extract_sky_pool_interior_planes.py'
    parser_spec = importlib.util.spec_from_file_location('tidal_tm_parse', workspace / 'scripts/tm_parse.py')
    parser_module = importlib.util.module_from_spec(parser_spec)
    parser_spec.loader.exec_module(parser_module)
    material = parser_module.load(project / 'Generated Materials/SkyPoolWater/SkyPoolWater.tm_material')
    def parameters(node):
        if isinstance(node, dict):
            if node.get('name') == 'PoolFrameOrigin' and 'value' in node:
                yield node['value']
            for value in node.values():
                yield from parameters(value)
        elif isinstance(node, list):
            for value in node:
                yield from parameters(value)
    origin, = parameters(material)
    x, y, z = (origin[axis] for axis in ('x', 'y', 'z'))
    source_text = extractor.read_text()
    anchor = '        lo, hi = world.min(axis=0), world.max(axis=0)'
    if source_text.count(anchor) != 1:
        raise ValueError('The scene extractor no longer exposes the world-coordinate sampling boundary')
    source_text = source_text.replace(anchor, f'        world = np.stack([{x!r} - world[:, 0], world[:, 1] - {y!r}, {z!r} - world[:, 2]], axis=1)\n' + anchor)
    source_text = source_text.replace('str(Path(__file__).resolve().parent)', repr(str(extractor.parent)))
    normalized_extractor = staging / 'pool_frame_extractor.py'
    normalized_extractor.write_text(source_text)
    run('/Volumes/Cortisol/Applications/Blender.app/Contents/MacOS/Blender', '--background', '--factory-startup', '--python', normalized_extractor, '--', '--geometry', source, project, staging / 'planes', 160)
    atlas = cv2.imread(str(atlas_path))
    arrays = np.load(staging / 'planes.npz')
    for source, name in [('floor', 'floor-dark'), ('wall_left', 'wall-left-dark'), ('recess_left', 'recess-dark')]:
        uv = arrays[source + '_uv']
        valid = arrays[source + '_valid'].astype(bool)
        if not valid.any():
            raise ValueError(f'{source} has no mapped atlas pixels')
        color = cv2.remap(atlas, (uv[..., 0] * atlas.shape[1] - .5).astype(np.float32), ((1 - uv[..., 1]) * atlas.shape[0] - .5).astype(np.float32), cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        _, labels = cv2.distanceTransformWithLabels((~valid).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
        color[~valid] = color[valid][labels[~valid] - 1]
        if source == 'recess_left':
            color = color[:round(color.shape[0] * .894 / 2.18)]
        if not cv2.imwrite(str(staging / f'{name}.png'), color):
            raise RuntimeError(f'Cannot write {name}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scene-workspace', required=True, type=Path)
    parser.add_argument('--delivery', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[2] / 'Packages/TidalEnvironment/Sources/TidalEnvironment/Resources')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='tidal-', dir=args.output.parent) as directory:
        staging = Path(directory)
        with zipfile.ZipFile(args.delivery / 'SkyPool.usdz') as archive:
            archive.extract('textures/Scene_Unlit_16K.png', staging)
        validate_atlas(staging / 'textures/Scene_Unlit_16K.png', args.scene_workspace / 'scratch/sky_pool_import/textures/sky_pool_unlit.png')
        run(sys.executable, args.delivery / '解码器.py', args.delivery / '暗色参数12M.bin', staging / 'textures/Scene_Unlit_16K.png', staging / 'atlas-dark.png')
        water_textures(args.scene_workspace, staging / 'atlas-dark.png', staging)
        for name in ['floor-dark', 'wall-left-dark', 'recess-dark']:
            run('xcrun', 'realitytool', 'image', '--semantic', 'color', '--astc-compression-block-size', '6x6', '--astc-compression-mode', 'sRGBLDR', '--astc-compression-quality', 'high', '-o', staging / f'{name}.ktx', staging / f'{name}.png')
        run(sys.executable, Path(__file__).with_name('patch_tidal_materials.py'), '--scene-workspace', args.scene_workspace)
        run(sys.executable, args.scene_workspace / 'scripts/export_scene.py', 'sykpool', '--without-plugins', '--output', staging / 'tidal.reality')
        shutil.copyfile(args.delivery / '暗色参数12M.bin', staging / 'dark-parameters.bin')
        for name in ['tidal.reality', 'dark-parameters.bin', 'floor-dark.ktx', 'wall-left-dark.ktx', 'recess-dark.ktx']:
            (staging / name).replace(args.output / name)
    print(json.dumps({path.name: {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()} for path in sorted(args.output.iterdir()) if path.is_file()}, indent=2))


if __name__ == '__main__':
    main()
