import uuid


FRAME = {
    'SceneFrameOrigin': (0.0, 0.0, 0.0),
    'SceneFrameX': (1.0, 0.0, 0.0),
    'SceneFrameY': (0.0, 1.0, 0.0),
    'SceneFrameZ': (0.0, 0.0, 1.0),
}
WORLD_NODES = {'ND_position_vector3', 'ND_normal_vector3', 'ND_realitykit_viewdirection_vector3'}
NATIVE_NODES = {'ND_realitykit_light_spill_specular_ggx', 'ND_realitykit_environment_radiance'}


def patch_scene_frames(project, parser, author):
    reports = []
    for material in ['SkyDome', 'SkyPoolWater', 'SkyPoolGlass', 'SkyPoolGlassDoor', 'SkyPoolGlassBottle']:
        directory = project / 'Generated Materials' / material
        material_path = directory / (material + '.tm_material')
        documents = {p: parser.load(p) for p in (directory / 'functions').glob('*.tm_shadergraph')}
        documents[material_path] = parser.load(material_path)
        paths = {d['__uuid']: p for p, d in documents.items()}

        def graph(path):
            document = documents[path]
            return document['shader_graph']['graph'] if path == material_path else document['graph']

        def dependency(node):
            return paths.get(node.get('settings', {}).get('subgraph', {}).get('__prototype_uuid'))

        needed = set()
        visited = set()

        def visit(path):
            if path in visited:
                return path in needed
            visited.add(path)
            nodes = graph(path)['nodes']
            children = [visit(child) for node in nodes if (child := dependency(node)) is not None]
            if any(children) or any(n['type'] in WORLD_NODES | NATIVE_NODES for n in nodes):
                needed.add(path)
            return path in needed

        visit(material_path)
        interfaces = {}
        changed = []
        for path in sorted(needed):
            g = graph(path)
            inputs = {item['name']: item['id'] for item in g['interface'].get('inputs', [])}
            if set(FRAME).issubset(inputs):
                interfaces[path] = {name: inputs[name] for name in FRAME}
                continue
            builder = author.Graph(path.stem, author.UUIDMinter('tidal-scene-frame/' + str(path.relative_to(project))))
            interfaces[path] = {
                name: builder.add_input(name, author.Value('vector3', value), len(inputs) + index,
                                        public=path == material_path)
                for index, (name, value) in enumerate(FRAME.items())
            }
            g['interface'].setdefault('inputs', []).extend(builder.inputs)
            changed.append(path)

        for path in changed:
            g = graph(path)
            key = 'tidal-scene-frame/' + str(path.relative_to(project))
            mint = lambda value: str(uuid.uuid5(uuid.NAMESPACE_URL, key + '/' + value))
            hash_name = author.murmur64
            original_nodes = list(g['nodes'])
            input_node = next(n['__uuid'] for n in original_nodes if n['type'] == 'tm_input_node')
            counter = 0

            def connect(source, target, connector):
                g['connections'].append({
                    '__uuid': mint(source[0] + source[1] + target + connector),
                    'from_node': source[0], 'from_connector_hash': source[1],
                    'to_node': target, 'to_connector_hash': hash_name(connector),
                })

            def node(kind, **ports):
                nonlocal counter
                counter += 1
                identifier = mint('node/' + str(counter))
                g['nodes'].append({'__uuid': identifier, 'type': kind,
                                   'label': 'SceneFrame_' + str(counter),
                                   'position': {'__uuid': mint('position/' + str(counter))}})
                for port, source in ports.items():
                    connect(source, identifier, port)
                return identifier, hash_name('out')

            def parameter(name):
                return input_node, hash_name(interfaces[path][name])

            def local_direction(source):
                parts = [node('ND_dotproduct_vector3', in1=source, in2=parameter('SceneFrame' + axis))
                         for axis in 'XYZ']
                return node('ND_combine3_vector3', **{f'in{i + 1}': part for i, part in enumerate(parts)})

            def world_direction(source):
                separated = node('ND_separate3_vector3', **{'in': source})
                parts = [node('ND_multiply_vector3FA', in1=parameter('SceneFrame' + axis),
                              in2=(separated[0], hash_name('out' + axis.lower()))) for axis in 'XYZ']
                return node('ND_add_vector3', in1=node('ND_add_vector3', in1=parts[0], in2=parts[1]), in2=parts[2])

            def world_input(kind):
                result = node(kind)
                g['data'].append({'__uuid': mint(result[0] + '/space'), 'to_node': result[0],
                                  'to_connector_hash': hash_name('space'),
                                  'data': {'__type': 'sg_enum', '__uuid': mint(result[0] + '/space/value'),
                                           'enum_type': 'ba7cdee4256775f1', 'enum_value': 'world'}})
                return result

            for existing in original_nodes:
                child = dependency(existing)
                if child in needed:
                    for name in FRAME:
                        connect(parameter(name), existing['__uuid'], interfaces[child][name])
                if existing['type'] not in WORLD_NODES:
                    continue
                space = next((d['data'].get('enum_value') for d in g['data']
                              if d['to_node'] == existing['__uuid'] and d['to_connector_hash'] == hash_name('space')), 'world')
                if space != 'world':
                    continue
                links = [c for c in g['connections'] if c['from_node'] == existing['__uuid']]
                source = existing['__uuid'], hash_name('out')
                if existing['type'] == 'ND_position_vector3':
                    source = node('ND_subtract_vector3', in1=source, in2=parameter('SceneFrameOrigin'))
                transformed = local_direction(source)
                for link in links:
                    link['from_node'], link['from_connector_hash'] = transformed

            for existing in original_nodes:
                if existing['type'] not in NATIVE_NODES:
                    continue
                for link in [c for c in g['connections'] if c['to_node'] == existing['__uuid']]:
                    port = link['to_connector_hash']
                    if port == hash_name('normal'):
                        result = world_direction((link['from_node'], link['from_connector_hash']))
                    elif existing['type'] == 'ND_realitykit_light_spill_specular_ggx' and port == 'd732cbb1d4ca1ee5':
                        result = world_input('ND_position_vector3')
                    elif existing['type'] == 'ND_realitykit_light_spill_specular_ggx' and port == 'bc95992290232830':
                        result = node('ND_normalize_vector3', **{'in': world_input('ND_realitykit_viewdirection_vector3')})
                    else:
                        continue
                    link['from_node'], link['from_connector_hash'] = result
            path.write_text(author.render_document(documents[path]))
        reports.append({'material': material, 'scene_frame_graphs': len(needed), 'changed_graphs': len(changed)})
    return reports
