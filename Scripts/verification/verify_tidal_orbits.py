import argparse
import hashlib
import itertools
import json
import math
import re
import platform
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from scipy.optimize import linprog
from scipy.spatial import ConvexHull


MOVING = re.compile(r'(RockFragment\d+|BuildingFragment02|BrokenRoad01)')


def clipped_polygon(polygon, height, keep_above):
    result = []
    for first, second in zip(polygon, polygon[1:] + polygon[:1]):
        first_inside = first[1] >= height if keep_above else first[1] <= height
        second_inside = second[1] >= height if keep_above else second[1] <= height
        if first_inside:
            result.append(first)
        if first_inside != second_inside:
            ratio = (height - first[1]) / (second[1] - first[1])
            result.append(first + ratio * (second - first))
    return result


def slab_vertices(vertices, triangles, lower, upper):
    faces = vertices[triangles]
    selected = faces[(faces[:, :, 1].max(axis=1) >= lower) & (faces[:, :, 1].min(axis=1) <= upper)]
    points = []
    for triangle in selected:
        polygon = clipped_polygon(list(triangle), lower, True)
        if polygon:
            polygon = clipped_polygon(polygon, upper, False)
            points.extend(polygon)
    return np.asarray(points, dtype=np.float64).reshape((-1, 3))


def minimum_hull_radius(points):
    points = np.unique(np.asarray(points, dtype=np.float64), axis=0)
    if len(points) == 1:
        return float(np.linalg.norm(points[0]))
    if len(points) > 2:
        rank = np.linalg.matrix_rank(points - points[0])
        if rank == 2:
            hull = ConvexHull(points)
            if np.all(hull.equations[:, 2] <= 0):
                return 0.0
            points = points[hull.vertices]
        else:
            direction = points[np.argmax(np.linalg.norm(points - points[0], axis=1))] - points[0]
            coordinates = points @ direction
            points = points[[np.argmin(coordinates), np.argmax(coordinates)]]
    ends = np.roll(points, -1, axis=0)
    edges = ends - points
    squared = np.sum(edges * edges, axis=1)
    amounts = np.clip(-np.sum(points * edges, axis=1) / squared, 0, 1)
    nearest = points + amounts[:, None] * edges
    return float(np.min(np.linalg.norm(nearest, axis=1)))


def convex_vertices(vertices):
    points = np.unique(vertices, axis=0)
    if len(points) >= 4 and np.linalg.matrix_rank(points - points[0]) == 3:
        return points[ConvexHull(points).vertices]
    return points


def triangle_partition_separation(first, second):
    lower_a, upper_a = first.min(axis=1), first.max(axis=1)
    lower_b, upper_b = second.min(axis=1), second.max(axis=1)
    best = math.inf
    witness = None
    for start in range(0, len(first), 128):
        gaps = np.maximum(
            lower_a[start:start + 128, None, :] - upper_b[None, :, :],
            lower_b[None, :, :] - upper_a[start:start + 128, None, :]
        )
        distances = np.linalg.norm(np.maximum(gaps, 0), axis=2)
        position = np.unravel_index(np.argmin(distances), distances.shape)
        distance = float(distances[position])
        if distance < best:
            best = distance
            witness = [int(start + position[0]), int(position[1])]
    return {
        'method': 'all_triangle_aabb_distance_lower_bound', 'gap_m': best,
        'triangle_pair_count': len(first) * len(second), 'closest_triangle_boxes': witness
    }


def pair_separation(first, second, clearance, first_faces=None, second_faces=None):
    lower_a, upper_a = first.min(axis=0), first.max(axis=0)
    lower_b, upper_b = second.min(axis=0), second.max(axis=0)
    gaps = np.maximum(lower_a - upper_b, lower_b - upper_a)
    if gaps.max() >= clearance:
        axis = int(np.argmax(gaps))
        return {'method': 'axis_support_plane', 'axis': axis, 'gap_m': float(gaps[axis])}
    first = convex_vertices(first)
    second = convex_vertices(second)
    a = np.column_stack((first, np.ones(len(first))))
    b = np.column_stack((second, np.ones(len(second))))
    solution = linprog(
        np.zeros(4), A_ub=np.vstack((-a, b)), b_ub=-np.ones(len(first) + len(second)),
        bounds=[(None, None)] * 4, method='highs'
    )
    if not solution.success:
        if first_faces is not None and second_faces is not None:
            return triangle_partition_separation(first_faces, second_faces)
        return {'method': 'convex_hulls_not_separated', 'gap_m': 0.0}
    normal = solution.x[:3]
    normal /= np.linalg.norm(normal)
    gap = float((first @ normal).min() - (second @ normal).max())
    return {'method': 'convex_support_plane', 'normal': normal.tolist(), 'gap_m': gap}


def self_check():
    assert math.isclose(minimum_hull_radius([[2, -2], [2, 2], [4, 2], [4, -2]]), 2)
    assert minimum_hull_radius([[-1, -1], [-1, 1], [1, 1], [1, -1]]) == 0
    triangle = np.array([[2, 0, 0], [4, 2, 0], [4, 0, 2]], dtype=np.float64)
    clipped = slab_vertices(triangle, np.array([[0, 1, 2]]), 1, 2)
    assert math.isclose(minimum_hull_radius(clipped[:, [0, 2]]), 3)
    cube = np.array(list(itertools.product((-1, 1), repeat=3)), dtype=np.float64)
    assert pair_separation(cube, cube + [4, 0, 0], 0.02)['gap_m'] == 2
    assert pair_separation(cube, cube, 0.02)['gap_m'] == 0
    diagonal_a = np.array([[0, 0, 0], [2, 0, 0], [0, 2, 0], [0, 0, 2]], dtype=np.float64)
    diagonal_b = 2 - diagonal_a
    assert pair_separation(diagonal_a, diagonal_b, 0.02)['gap_m'] > 1
    face = np.array([[[0, 0, 0], [1, 0, 0], [0, 1, 0]]], dtype=np.float64)
    assert triangle_partition_separation(face, face + [0, 0, 3])['gap_m'] == 3


def main():
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--meshes', type=Path)
    source.add_argument('--scene', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--adjustments', type=Path, required=True)
    parser.add_argument('--clearance', type=float, default=0.02)
    args = parser.parse_args()
    if not math.isfinite(args.clearance) or args.clearance <= 0:
        parser.error('--clearance must be finite and positive')
    self_check()
    if args.scene:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.meshes = args.report.with_suffix('.meshes.json')
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix='orbit-export-', dir=args.report.parent) as directory:
            binary = Path(directory) / 'export'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6',
                            '-default-isolation', 'MainActor', '-target', f'{platform.machine()}-apple-macos27.0',
                            str(root / 'Packages/TidalEnvironment/Sources/TidalEnvironment/TidalScenePlacement.swift'),
                            str(Path(__file__).with_name('TidalOrbitGeometryExport.swift')), '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(args.scene.resolve()), str(args.meshes.resolve())], check=True)
    encoded = args.meshes.read_bytes()
    source_hash = hashlib.sha256(encoded).hexdigest()
    rows = json.loads(encoded)
    source_triangle_count = sum(len(row['triangles']) for row in rows)
    moving, static, excluded = [], [], []
    for row in rows:
        vertices = np.asarray(row['vertices'], dtype=np.float64)
        triangles = np.asarray(row['triangles'], dtype=np.int64)
        if vertices.ndim != 2 or vertices.shape[1] != 3 or not np.isfinite(vertices).all():
            raise ValueError('Invalid vertices: ' + row['path'])
        if triangles.ndim != 2 or triangles.shape[1] != 3 or triangles.min() < 0 or triangles.max() >= len(vertices):
            raise ValueError('Invalid triangles: ' + row['path'])
        mesh = {'name': row['parent'], 'path': row['path'], 'vertices': vertices, 'triangles': triangles}
        if row['name'] == 'SkyDome':
            excluded.append(row['path'])
        elif MOVING.fullmatch(row['parent']):
            moving.append(mesh)
        else:
            static.append(mesh)
    del rows, encoded
    names = {mesh['name'] for mesh in moving}
    if not {'BuildingFragment02', 'BrokenRoad01'}.issubset(names) or not any(name.startswith('RockFragment') for name in names) or not static:
        raise ValueError('Expected the road, building and rock fragments, and a nonempty static scene')
    lower = min(mesh['vertices'][:, 1].min() for mesh in static)
    upper = max(mesh['vertices'][:, 1].max() for mesh in static)
    radius = max(np.linalg.norm(mesh['vertices'][:, [0, 2]], axis=1).max() for mesh in static)
    orbit_results = []
    for mesh in moving:
        vertices = mesh['vertices']
        y_lower, y_upper = vertices[:, 1].min(), vertices[:, 1].max()
        vertical_gap = max(lower - y_upper, y_lower - upper)
        result = {
            'name': mesh['name'], 'mesh': mesh['path'],
            'actual_y_range_m': [float(y_lower), float(y_upper)],
            'additional_translation_scene_m': [0, 0, 0]
        }
        if vertical_gap >= args.clearance:
            result.update(method='vertical_interval_separation', certified_clearance_lower_bound_m=float(vertical_gap))
        else:
            clipped = slab_vertices(vertices, mesh['triangles'], lower - args.clearance, upper + args.clearance)
            if not len(clipped):
                raise ValueError('Unexpected empty overlapping slab: ' + mesh['name'])
            moving_radius = minimum_hull_radius(clipped[:, [0, 2]])
            radial_gap = moving_radius - radius
            result.update(
                method='triangle_clipped_slab_radial_separation',
                clipped_slab_y_range_m=[float(lower - args.clearance), float(upper + args.clearance)],
                moving_clipped_hull_min_radius_m=moving_radius,
                radial_gap_in_expanded_static_slab_m=radial_gap,
                certified_clearance_lower_bound_m=min(args.clearance, radial_gap)
            )
        result['safe_full_360_degrees'] = result['certified_clearance_lower_bound_m'] >= args.clearance - 1e-9
        orbit_results.append(result)
    pairs = []
    for first, second in itertools.combinations(moving, 2):
        separation = pair_separation(
            first['vertices'], second['vertices'], args.clearance,
            first['vertices'][first['triangles']], second['vertices'][second['triangles']]
        )
        pairs.append({
            'first': first['name'], 'second': second['name'], **separation,
            'separated': separation['gap_m'] >= args.clearance
        })
    all_safe = all(row['safe_full_360_degrees'] for row in orbit_results) and all(row['separated'] for row in pairs)
    report = {
        'source_sha256': source_hash,
        'source_mesh_count': len(moving) + len(static) + len(excluded),
        'source_triangle_count': source_triangle_count,
        'moving_mesh_count': len(moving), 'static_mesh_count': len(static),
        'excluded_visual_shells': excluded,
        'required_clearance_m': args.clearance,
        'orbit_axis_scene': [0, 1, 0], 'orbit_center_scene': [0, 0, 0],
        'static_containing_cylinder': {'y_range_m': [float(lower), float(upper)], 'radius_m': float(radius)},
        'method': 'Exact triangle clipping against the expanded static height slab, then conservative convex radial bounds. Rotation preserves y and radius for every angle. Initial moving mesh surfaces are separated by support planes or exhaustive per-triangle AABB distance bounds. Shared rigid rotation preserves every moving-pair distance.',
        'full_orbit_safety': orbit_results, 'initial_fragment_pair_separation': pairs,
        'all_safe': all_safe
    }
    adjustments = {
        'source_sha256': source_hash, 'orbit_center_scene': [0, 0, 0],
        'baseline_already_in_source': {'BrokenRoad01': [0, 0, -2], 'BuildingFragment02': [0, 10, 0]},
        'additional_offsets_scene_m': {} if all_safe else None,
        'all_y_preserved': True,
        'decision': 'All baseline meshes satisfy the full-orbit and pairwise separation proofs; no additional X/Z adjustment is required.' if all_safe else 'Unproven geometry requires further exact analysis; no automatic relocation is proposed.'
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.adjustments.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    args.adjustments.write_text(json.dumps(adjustments, indent=2) + '\n')
    print(json.dumps({'all_safe': all_safe, 'moving': len(moving), 'pairs': len(pairs), 'offsets': adjustments['additional_offsets_scene_m']}))
    if not all_safe:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
