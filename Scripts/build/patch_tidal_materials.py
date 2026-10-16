import argparse
import importlib
import json
import sys
from pathlib import Path
from patch_tidal_appearance import patch_appearances, sync_sky_tilt
from patch_tidal_scene_frame import patch_scene_frames


MATERIALS = ('SkyDome', 'SkyPoolWater', 'SkyPoolGlass', 'SkyPoolGlassDoor', 'SkyPoolGlassBottle')
SCENE_FRAME = ('SceneFrameOrigin', 'SceneFrameX', 'SceneFrameY', 'SceneFrameZ')
SKY_ORIENTED = ('SkyPoolWater', 'SkyPoolGlass', 'SkyPoolGlassDoor', 'SkyPoolGlassBottle')
DARK_WATER = ('DarkMix', 'DarkFloorPlane_color', 'DarkWallLeftPlane_color', 'DarkRecessPlane_color')


def material_parameters(project, parser, material):
    document = parser.load(project / 'Generated Materials' / material / (material + '.tm_material'))
    return {item['name'] for item in document['shader_graph']['graph']['interface'].get('inputs', [])}


def unexposed_parameters(project, parser):
    required = {material: set(SCENE_FRAME) for material in MATERIALS}
    for material in SKY_ORIENTED:
        required[material].add('SkyOrientationAxis')
    required['SkyPoolWater'].update(DARK_WATER)
    missing = {}
    for material, names in required.items():
        absent = names - material_parameters(project, parser, material)
        if absent:
            missing[material] = sorted(absent)
    return missing


def main():
    parser = argparse.ArgumentParser(description=(
        'Inject the Tidal runtime parameters into the five sky materials. '
        'Sampler settings and screen-reflection coverage live in the SSL sources under scripts/shaders; '
        'this pass only adds the parameters the runtime drives and the direction-space sky taps.'
    ))
    parser.add_argument('--scene-workspace', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.scene_workspace / 'scripts'))
    tm_parse = importlib.import_module('tm_parse')
    tm_graph = importlib.import_module('tm_graph')
    project = args.scene_workspace / 'scenes/sykpool.realitycomposerpro'
    reports = [sync_sky_tilt(project, tm_parse, tm_graph)]
    reports.extend(patch_scene_frames(project, tm_parse, tm_graph))
    reports.extend(patch_appearances(project, tm_parse, tm_graph))
    missing = unexposed_parameters(project, tm_parse)
    if missing:
        raise SystemExit('the scene materials miss the parameters the Tidal runtime drives: '
                         + json.dumps(missing, sort_keys=True))
    result = json.dumps([r for r in reports if r.get('scene_frame_graphs') or r.get('appearance_graphs')
                         or r.get('sky_tilt_graphs')], indent=2)
    if args.report:
        args.report.write_text(result + '\n')
    print(result)


if __name__ == '__main__':
    main()
