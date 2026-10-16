import argparse
import copy
import importlib
import json
import math
import sys
import uuid
from pathlib import Path


MATERIALS = ('SkyDome', 'SkyPoolWater', 'SkyPoolGlass', 'SkyPoolGlassDoor', 'SkyPoolGlassBottle')
WATER_TEXTURES = ('FloorPlane_color', 'WallLeftPlane_color', 'RecessPlane_color')
SAMPLERS = {'ND_RealityKitTexture2D_vector4', 'ND_RealityKitTexture2DLOD_vector4',
            'ND_RealityKitTextureCube_vector4', 'ND_RealityKitTextureCubeLOD_vector4'}
TAPS = ((0.0, 0.125), (0.25, 0.25), (0.5, 0.25), (0.75, 0.25), (1.0, 0.125))
SKY_TILT_DEGREES = 180.0
SKY_TILT_SINE = round(math.sin(math.radians(SKY_TILT_DEGREES)), 12)
SKY_TILT_COSINE = round(math.cos(math.radians(SKY_TILT_DEGREES)), 12)
LEGACY_SKY_TILT_SINE = 0.8660253882408142
SHADER_SOURCES = ('sky_dome.ssl', 'sky_pool_water.ssl', 'sky_pool_glass.ssl', 'sky_pool_interior_glass.ssl')
SHADER_TILT_SOURCE = 'ray.y * 0.5f - ray.z * 0.8660254f, ray.y * 0.8660254f + ray.z * 0.5f'
SHADER_TILT_TARGET = (f'ray.y * {SKY_TILT_COSINE:.1f}f - ray.z * {SKY_TILT_SINE:.1f}f, '
                      f'ray.y * {SKY_TILT_SINE:.1f}f + ray.z * {SKY_TILT_COSINE:.1f}f')


def identifier(key):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'enchron/tidal/appearance/' + key))


def clone(value, key):
    result = copy.deepcopy(value)

    def visit(item):
        if isinstance(item, dict):
            if '__uuid' in item:
                item['__uuid'] = identifier(key + '/' + item['__uuid'])
            for child in item.values():
                visit(child)
        elif isinstance(item, list):
            for child in item:
                visit(child)

    visit(result)
    return result


class GraphEditor:
    def __init__(self, graph, key, author):
        self.graph = graph
        self.key = key
        self.author = author
        self.hash = author.murmur64
        self.nodes = {node['__uuid']: node for node in graph['nodes']}
        self.input_node = next(node['__uuid'] for node in graph['nodes'] if node['type'] == 'tm_input_node')
        self.inputs = {item['name']: item for item in graph['interface'].get('inputs', [])}
        self.scope = ''
        self.serial = 0

    def start(self, scope):
        self.scope = scope
        self.serial = 0

    def connect(self, source, target, port):
        connector = self.hash(port)
        existing = next((link for link in self.graph['connections']
                         if link['to_node'] == target and link['to_connector_hash'] == connector), None)
        if existing is not None:
            existing['from_node'], existing['from_connector_hash'] = source
            return
        self.graph['connections'].append({
            '__uuid': identifier(self.key + '/link/' + target + '/' + port),
            'from_node': source[0], 'from_connector_hash': source[1],
            'to_node': target, 'to_connector_hash': connector,
        })

    def bind(self, target, port, source):
        connector = self.hash(port)
        self.graph['data'] = [item for item in self.graph.get('data', [])
                              if item['to_node'] != target or item['to_connector_hash'] != connector]
        if isinstance(source, tuple):
            self.connect(source, target, port)
        else:
            self.graph['connections'] = [link for link in self.graph['connections']
                                         if link['to_node'] != target or link['to_connector_hash'] != connector]
            key = self.key + '/data/' + target + '/' + port
            self.graph['data'].append({
                '__uuid': identifier(key), 'to_node': target, 'to_connector_hash': connector,
                'data': {'__type': 'tm_float', '__uuid': identifier(key + '/value'), 'float': float(source)},
            })

    def node(self, kind, **ports):
        self.serial += 1
        key = self.key + '/' + self.scope + '/' + str(self.serial)
        node_id = identifier(key)
        if node_id in self.nodes:
            raise ValueError('Generated node already exists: ' + key)
        node = {'__uuid': node_id, 'type': kind, 'label': 'TidalAppearance_' + self.scope + '_' + str(self.serial),
                'position': {'__uuid': identifier(key + '/position')}}
        self.graph['nodes'].append(node)
        self.nodes[node_id] = node
        for port, source in ports.items():
            self.bind(node_id, port, source)
        return node_id, self.hash('out')

    def binary(self, operation, first, second):
        return self.node('ND_' + operation + '_float', in1=first, in2=second)

    def unary(self, operation, value):
        return self.node('ND_' + operation + '_float', **{'in': value})

    def parameter(self, name):
        return self.input_node, self.hash(self.inputs[name]['id'])

    def incoming(self, target):
        return {link['to_connector_hash']: (link['from_node'], link['from_connector_hash'])
                for link in self.graph['connections'] if link['to_node'] == target}

    def split(self, value, count):
        separated = self.node('ND_separate' + str(count) + '_vector' + str(count), **{'in': value})
        return tuple((separated[0], self.hash('out' + axis)) for axis in 'xyzw'[:count])

    def sampler_copy(self, sampler, label):
        key = self.key + '/' + self.scope + '/' + label
        copied = clone(self.nodes[sampler], key)
        copied['label'] = 'TidalAppearance_' + label
        self.graph['nodes'].append(copied)
        self.nodes[copied['__uuid']] = copied
        for item in list(self.graph.get('data', [])):
            if item['to_node'] == sampler:
                new_item = clone(item, key)
                new_item['to_node'] = copied['__uuid']
                self.graph['data'].append(new_item)
        for connector, source in self.incoming(sampler).items():
            self.graph['connections'].append({
                '__uuid': identifier(key + '/link/' + connector),
                'from_node': source[0], 'from_connector_hash': source[1],
                'to_node': copied['__uuid'], 'to_connector_hash': connector,
            })
        return copied['__uuid']

    def redirect(self, links, source):
        for link in links:
            link['from_node'], link['from_connector_hash'] = source

    def mark(self, source, marker):
        node = self.nodes[source[0]]
        old = node['__uuid']
        new = identifier(self.key + '/' + marker)
        node['__uuid'] = new
        node['label'] = 'TidalAppearance_' + marker
        for link in self.graph['connections']:
            if link['to_node'] == old:
                link['to_node'] = new
            if link['from_node'] == old:
                link['from_node'] = new
        for item in self.graph['data']:
            if item['to_node'] == old:
                item['to_node'] = new
        self.nodes[new] = self.nodes.pop(old)
        return new, source[1]

    def has_marker(self, marker):
        return identifier(self.key + '/' + marker) in self.nodes


def untilted_direction(editor, local):
    x, y, z = editor.split(local, 3)
    return (
        x,
        editor.binary('add', editor.binary('multiply', y, SKY_TILT_COSINE), editor.binary('multiply', z, SKY_TILT_SINE)),
        editor.binary('add', editor.binary('multiply', z, SKY_TILT_COSINE), editor.binary('multiply', y, -SKY_TILT_SINE)),
    )


def tilted_direction(editor, direction):
    x, y, z = direction
    return editor.node('ND_combine3_vector3', in1=x,
                       in2=editor.binary('subtract', editor.binary('multiply', y, SKY_TILT_COSINE),
                                         editor.binary('multiply', z, SKY_TILT_SINE)),
                       in3=editor.binary('add', editor.binary('multiply', y, SKY_TILT_SINE),
                                         editor.binary('multiply', z, SKY_TILT_COSINE)))


def rotated_direction(editor, direction, angle):
    x, y, z = direction
    sine = editor.unary('sin', angle)
    cosine = editor.unary('sin', editor.binary('add', angle, math.pi / 2))
    turned_x = editor.binary('subtract', editor.binary('multiply', cosine, x), editor.binary('multiply', sine, z))
    turned_z = editor.binary('add', editor.binary('multiply', sine, x), editor.binary('multiply', cosine, z))
    return tilted_direction(editor, (turned_x, y, turned_z))


def patch_sky(editor, sampler):
    marker = 'SkyOutput_' + sampler
    if editor.has_marker(marker):
        return False
    editor.start('Sky_' + sampler)
    original_links = [link for link in editor.graph['connections'] if link['from_node'] == sampler]
    yaw = editor.parameter('SkyYaw')
    blur = editor.parameter('SkyBlurAngle')
    direction = untilted_direction(editor, editor.incoming(sampler)[editor.hash('texcoord')])
    copies = [sampler] + [editor.sampler_copy(sampler, 'SkyTap_' + sampler + '_' + str(i)) for i in range(1, len(TAPS))]
    weighted = []
    for (fraction, weight), target in zip(TAPS, copies):
        angle = editor.binary('subtract', yaw, editor.binary('multiply', blur, fraction))
        editor.bind(target, 'texcoord', rotated_direction(editor, direction, angle))
        weighted.append(editor.node('ND_multiply_vector4FA', in1=(target, editor.hash('out')), in2=weight))
    total = weighted[0]
    for value in weighted[1:]:
        total = editor.node('ND_add_vector4', in1=total, in2=value)
    editor.redirect(original_links, editor.mark(total, marker))
    return True


def patch_water(editor, texture, sampler):
    marker = 'WaterOutput_' + sampler
    if editor.has_marker(marker):
        return False
    editor.start('Water_' + sampler)
    original_links = [link for link in editor.graph['connections'] if link['from_node'] == sampler]
    dark = editor.sampler_copy(sampler, 'WaterDark_' + sampler)
    editor.bind(dark, 'file', editor.parameter('Dark' + texture))
    weight = editor.node('ND_clamp_float', **{'in': editor.parameter('DarkMix'), 'low': 0.0, 'high': 1.0})
    result = editor.node('ND_mix_vector4', bg=(sampler, editor.hash('out')), fg=(dark, editor.hash('out')), mix=weight)
    editor.redirect(original_links, editor.mark(result, marker))
    return True


def validate_graph(graph, path, hash_name):
    kinds = {node['__uuid']: node['type'] for node in graph['nodes']}
    nodes = set(kinds)
    if len(nodes) != len(graph['nodes']):
        raise ValueError('Duplicate node in ' + str(path))
    incoming = set()
    dependencies = {node: [] for node in nodes}
    for link in graph['connections']:
        if kinds.get(link['to_node']) in SAMPLERS and link['to_connector_hash'] == hash_name('min_lod_clamp'):
            raise ValueError('min_lod_clamp requires a compile-time constant; use dynamic_min_lod_clamp or lod in ' + str(path))
        target = link['to_node'], link['to_connector_hash']
        if link['from_node'] not in nodes or link['to_node'] not in nodes or target in incoming:
            raise ValueError('Invalid graph connection in ' + str(path))
        incoming.add(target)
        dependencies[link['to_node']].append(link['from_node'])
    if any((item['to_node'], item['to_connector_hash']) in incoming for item in graph.get('data', [])):
        raise ValueError('Input has both a connection and data in ' + str(path))
    visited = set()
    visiting = set()

    def visit(node):
        if node in visited:
            return
        if node in visiting:
            raise ValueError('Graph cycle in ' + str(path))
        visiting.add(node)
        for dependency in dependencies[node]:
            visit(dependency)
        visiting.remove(node)
        visited.add(node)

    for node in nodes:
        visit(node)


def patch_appearances(project, parser, author):
    reports = []
    for material in MATERIALS:
        directory = project / 'Generated Materials' / material
        material_path = directory / (material + '.tm_material')
        documents = {path: parser.load(path) for path in (directory / 'functions').glob('*.tm_shadergraph')}
        documents[material_path] = parser.load(material_path)
        paths = {document['__uuid']: path for path, document in documents.items()}

        def graph(path):
            document = documents[path]
            return document['shader_graph']['graph'] if path == material_path else document['graph']

        def children(path):
            return [(node, paths[prototype]) for node in graph(path)['nodes']
                    if (prototype := node.get('settings', {}).get('subgraph', {}).get('__prototype_uuid')) in paths]

        active = set()

        def visit(path):
            if path in active:
                return
            active.add(path)
            for _, child in children(path):
                visit(child)

        visit(material_path)
        originals = {path: copy.deepcopy(documents[path]) for path in active}
        direct = {}
        required = {}
        for path in active:
            g = graph(path)
            nodes = {node['__uuid']: node for node in g['nodes']}
            inputs = {item['id']: item['name'] for item in g['interface'].get('inputs', [])}
            input_node = next((node['__uuid'] for node in g['nodes'] if node['type'] == 'tm_input_node'), None)
            by_hash = {author.murmur64(key): name for key, name in inputs.items()}
            direct[path] = [(by_hash[link['from_connector_hash']], link['to_node']) for link in g['connections']
                            if link['from_node'] == input_node and link['from_connector_hash'] in by_hash
                            and link['to_connector_hash'] == author.murmur64('file')
                            and nodes[link['to_node']]['type'] in SAMPLERS
                            and not nodes[link['to_node']].get('label', '').startswith('TidalAppearance_')]

        def requirements(path):
            if path in required:
                return required[path]
            names = set()
            for texture, _ in direct[path]:
                if texture == 'SkyTexture_color':
                    names.update(('SkyYaw', 'SkyBlurAngle'))
                elif texture in WATER_TEXTURES:
                    names.update(('DarkMix', 'Dark' + texture))
            for _, child in children(path):
                names.update(requirements(child))
            required[path] = names
            return names

        requirements(material_path)
        root_inputs = {item['name']: item for item in graph(material_path)['interface'].get('inputs', [])}
        editors = {}
        for path in sorted(active):
            g = graph(path)
            key = str(path.relative_to(project))
            inputs = {item['name']: item for item in g['interface'].get('inputs', [])}
            for name in sorted(required[path]):
                if name in inputs:
                    continue
                if name.startswith('Dark') and name != 'DarkMix':
                    light_name = name[4:]
                    item = clone(inputs.get(light_name, root_inputs[light_name]), key + '/input/' + name)
                    item['name'] = name
                    item['id'] = path.stem + '_' + name
                    if path == material_path:
                        item['public'] = True
                    else:
                        item.pop('public', None)
                    item['order'] = len(inputs)
                else:
                    builder = author.Graph(path.stem, author.UUIDMinter('tidal-appearance/' + key))
                    builder.add_input(name, author.Value('float', 0.0), len(inputs), public=path == material_path)
                    item = builder.inputs[0]
                g['interface'].setdefault('inputs', []).append(item)
                inputs[name] = item
            if required[path]:
                editors[path] = GraphEditor(g, key, author)
        for path, editor in editors.items():
            for node, child in children(path):
                for name in sorted(required[child]):
                    editor.connect(editor.parameter(name), node['__uuid'], editors[child].inputs[name]['id'])
        sky_count = water_count = 0
        for path, editor in editors.items():
            for texture, sampler in direct[path]:
                if texture == 'SkyTexture_color':
                    sky_count += int(patch_sky(editor, sampler))
                elif texture in WATER_TEXTURES:
                    water_count += int(patch_water(editor, texture, sampler))
        changed = []
        for path in sorted(active):
            validate_graph(graph(path), path, author.murmur64)
            if documents[path] != originals[path]:
                path.write_text(author.render_document(documents[path]))
                changed.append(str(path))
        reports.append({'material': material, 'appearance_graphs': len(editors), 'sky_sampler_patches': sky_count,
                        'water_sampler_patches': water_count, 'changed_graphs': len(changed),
                        'parameters': sorted(required[material_path])})
    return reports


def align_sky_tilt(document, hash_name):
    graph = document['shader_graph']['graph'] if 'shader_graph' in document else document['graph']
    sines = [item for item in graph.get('data', []) if item['data'].get('float') == LEGACY_SKY_TILT_SINE]
    if not sines:
        return 0
    nodes = {node['__uuid']: node for node in graph['nodes']}
    inputs = {}
    for link in graph['connections']:
        inputs.setdefault(link['to_node'], {})[link['to_connector_hash']] = link['from_node']
    cosines = 0
    for entry in sines:
        sine_node = entry['to_node']
        entry['data']['float'] = SKY_TILT_SINE
        consumers = [link['to_node'] for link in graph['connections'] if link['from_node'] == sine_node]
        if len(consumers) != 1:
            raise ValueError('Sky tilt sine node must feed exactly one consumer: ' + sine_node)
        for source in inputs.get(consumers[0], {}).values():
            if source == sine_node or nodes[source]['type'] != 'ND_multiply_float':
                continue
            for item in graph.get('data', []):
                if item['to_node'] == source and item['data'].get('float') == 0.5:
                    item['data']['float'] = SKY_TILT_COSINE
                    cosines += 1
    if cosines != len(sines):
        raise ValueError('Sky tilt cosine partners do not match the sine constants')
    return len(sines)


def sync_sky_tilt(project, parser, author):
    aligned = []
    for name in MATERIALS:
        for path in sorted((project / 'Generated Materials' / name / 'functions').glob('*.tm_shadergraph')):
            document = parser.load(path)
            if align_sky_tilt(document, author.murmur64):
                path.write_text(author.render_document(document))
                aligned.append(str(path.relative_to(project)))
    sources = []
    for name in SHADER_SOURCES:
        path = project.parents[1] / 'scripts/shaders' / name
        text = path.read_text()
        if SHADER_TILT_SOURCE not in text:
            continue
        path.write_text(text.replace(SHADER_TILT_SOURCE, SHADER_TILT_TARGET))
        sources.append(name)
    return {'sky_tilt_graphs': len(aligned), 'sky_tilt_shader_sources': sorted(sources), 'sky_tilt_degrees': SKY_TILT_DEGREES}


def main():
    parser = argparse.ArgumentParser(description=(
        'RealityKit requires constant min_lod_clamp. Dynamic footprint control uses bias or explicit lod. '
        'RCP can export fallback materials after shader errors; verify exported material parameters.'
    ))
    parser.add_argument('--scene-workspace', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.scene_workspace / 'scripts'))
    project = args.scene_workspace / 'scenes/sykpool.realitycomposerpro'
    reports = patch_appearances(project, importlib.import_module('tm_parse'), importlib.import_module('tm_graph'))
    result = json.dumps(reports, indent=2)
    if args.report:
        args.report.write_text(result + '\n')
    print(result)


if __name__ == '__main__':
    main()
