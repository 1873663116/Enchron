import argparse
import importlib
import json
import sys
import uuid
from pathlib import Path
from patch_tidal_appearance import patch_appearances
from patch_tidal_scene_frame import patch_scene_frames


def identifier(key):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'enchron/tidal/' + key))


def patch_graph(path, load, render, hash_name):
    document = load(path)
    graph = document['graph']
    nodes = {node['__uuid']: node for node in graph['nodes']}
    inputs = {item['name']: item for item in graph['interface'].get('inputs', [])}
    if not {'SkyTexture_color', 'ScreenReflectionGain'}.intersection(inputs):
        return {'file': str(path), 'sky_samplers': 0, 'gated_screen_coverage': False, 'changed': False}
    input_node = next(node for node in nodes.values() if node['type'] == 'tm_input_node')
    samplers = []
    if 'SkyTexture_color' in inputs:
        texture_hash = hash_name(inputs['SkyTexture_color']['id'])
        samplers = [link['to_node'] for link in graph['connections']
                    if link['from_node'] == input_node['__uuid']
                    and link['from_connector_hash'] == texture_hash
                    and nodes[link['to_node']]['type'] == 'ND_RealityKitTexture2D_vector4']
    changed = False
    for node in samplers:
        for parameter, value in [('mip_filter', 'linear'), ('bias', 0.0), ('min_lod_clamp', 0.0)]:
            item = next((entry for entry in graph['data']
                         if entry['to_node'] == node and entry['to_connector_hash'] == hash_name(parameter)), None)
            if item is None:
                if any(link['to_node'] == node and link['to_connector_hash'] == hash_name(parameter)
                       for link in graph['connections']):
                    continue
                data = {'__type': 'sg_enum' if isinstance(value, str) else 'tm_float',
                        '__uuid': identifier(node + parameter + '/value')}
                if isinstance(value, str):
                    data['enum_type'] = 'a69606d7258ea352'
                item = {'__uuid': identifier(node + parameter), 'to_node': node,
                        'to_connector_hash': hash_name(parameter), 'data': data}
                graph['data'].append(item)
                changed = True
            key = 'enum_value' if isinstance(value, str) else 'float'
            changed |= item['data'].get(key, 0) != value
            item['data'][key] = value
    coverage_links = [link for link in graph['connections']
                      if nodes[link['from_node']].get('label', '').startswith('ScreenReflection_')
                      and nodes[link['to_node']]['type'] == 'ND_subtract_float'
                      and link['to_connector_hash'] == hash_name('in2')]
    for link in coverage_links:
        prefix = str(path.name) + '/screenCoverage/'
        clamp_id = identifier(prefix + 'clamp')
        multiply_id = identifier(prefix + 'multiply')
        if clamp_id in nodes:
            continue
        for node_id, kind, label in [(clamp_id, 'ND_clamp_float', 'ScreenPresence'),
                                     (multiply_id, 'ND_multiply_float', 'ActiveScreenCoverage')]:
            graph['nodes'].append({'__uuid': node_id, 'type': kind, 'label': label,
                                   'position': {'__uuid': identifier(prefix + label + '/position')}})
        def connect(source, output, target, port):
            graph['connections'].append({'__uuid': identifier(prefix + source + output + target + port),
                                         'from_node': source, 'from_connector_hash': output,
                                         'to_node': target, 'to_connector_hash': hash_name(port)})
        connect(input_node['__uuid'], hash_name(inputs['ScreenReflectionGain']['id']), clamp_id, 'in')
        connect(link['from_node'], link['from_connector_hash'], multiply_id, 'in1')
        connect(clamp_id, hash_name('out'), multiply_id, 'in2')
        for port, value in [('low', 0.0), ('high', 1.0)]:
            graph['data'].append({'__uuid': identifier(prefix + port), 'to_node': clamp_id,
                                  'to_connector_hash': hash_name(port),
                                  'data': {'__type': 'tm_float', '__uuid': identifier(prefix + port + '/value'),
                                           'float': value}})
        link['from_node'] = multiply_id
        link['from_connector_hash'] = hash_name('out')
        changed = True
    if changed:
        path.write_text(render(document))
    return {'file': str(path), 'sky_samplers': len(samplers),
            'gated_screen_coverage': any(node.get('label') == 'ActiveScreenCoverage' for node in graph['nodes']),
            'changed': changed}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scene-workspace', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.scene_workspace / 'scripts'))
    tm_parse = importlib.import_module('tm_parse')
    tm_graph = importlib.import_module('tm_graph')
    project = args.scene_workspace / 'scenes/sykpool.realitycomposerpro'
    reports = []
    for name in ['SkyDome', 'SkyPoolWater', 'SkyPoolGlass', 'SkyPoolGlassDoor', 'SkyPoolGlassBottle']:
        directory = project / 'Generated Materials' / name
        functions = {tm_parse.load(path)['__uuid']: path for path in (directory / 'functions').glob('*.tm_shadergraph')}
        def references(value):
            if isinstance(value, dict):
                for key, child in value.items():
                    if key == '__prototype_uuid' and child in functions:
                        yield child
                    yield from references(child)
            elif isinstance(value, list):
                for child in value:
                    yield from references(child)
        pending = list(references(tm_parse.load(directory / (name + '.tm_material'))))
        active = set()
        while pending:
            current = pending.pop()
            if current in active:
                continue
            active.add(current)
            pending.extend(references(tm_parse.load(functions[current])))
        for path in sorted(functions[current] for current in active):
            reports.append(patch_graph(path, tm_parse.load, tm_graph.render_document, tm_graph.murmur64))
    for name in ['sky_dome.ssl', 'sky_pool_water.ssl', 'sky_pool_interior_glass.ssl']:
        path = args.scene_workspace / 'scripts/shaders' / name
        source = path.read_text().replace('mip_filter: "none"', 'mip_filter: "linear", bias: 0.0f, min_lod_clamp: 0.0f')
        source = source.replace('mip_filter: "linear", bias: 1.0f, min_lod_clamp: 1.0f',
                                'mip_filter: "linear", bias: 0.0f, min_lod_clamp: 0.0f')
        source = source.replace('(1.0f - coverage)', '(1.0f - coverage * Clamp($ScreenReflectionGain, 0.0f, 1.0f))')
        path.write_text(source)
    assert any(report['sky_samplers'] for report in reports)
    for name in ['SkyPoolWater', 'SkyPoolGlassDoor', 'SkyPoolGlassBottle']:
        assert any(report['gated_screen_coverage'] and Path(report['file']).name == name + '_fragment.tm_shadergraph'
                   for report in reports), name
    reports.extend(patch_scene_frames(project, tm_parse, tm_graph))
    reports.extend(patch_appearances(project, tm_parse, tm_graph))
    result = json.dumps([r for r in reports if r.get('sky_samplers') or r.get('gated_screen_coverage')
                         or r.get('scene_frame_graphs') or r.get('appearance_graphs')], indent=2)
    if args.report:
        args.report.write_text(result + '\n')
    print(result)


if __name__ == '__main__':
    main()
