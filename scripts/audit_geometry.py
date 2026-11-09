import argparse
import hashlib
import json
import math
from collections import Counter
from pathlib import Path

try:
    from scripts.prepare_catalog import validate_geometry
except ModuleNotFoundError:
    from prepare_catalog import validate_geometry


def distance(a, b):
    lat1, lat2 = math.radians(a[1]), math.radians(b[1])
    dlat, dlon = lat2 - lat1, math.radians(b[0] - a[0])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(max(0, min(1, h))))


def lines(geometry):
    kind, points = geometry['type'], geometry['coordinates']
    if kind == 'LineString':
        return [points]
    if kind == 'MultiLineString':
        return points
    return []


def rings(geometry):
    kind, points = geometry['type'], geometry['coordinates']
    if kind == 'Polygon':
        return points
    if kind == 'MultiPolygon':
        return [ring for polygon in points for ring in polygon]
    return []


def fingerprint(geometry):
    return hashlib.sha256(json.dumps(geometry, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def audit(catalog, source=None):
    rows, errors = [], []
    ids = [feature['id'] for feature in catalog['features']]
    if len(set(ids)) != len(ids):
        errors.append('duplicate_ids')
    original = {feature['id']: feature for feature in source['features']} if source is not None else None
    if original is not None and set(original) != set(ids):
        errors.append('source_ids_differ')
    groups = {group['id'] for group in catalog['groups']}
    for feature in catalog['features']:
        geometry = feature['geometry']
        row = {'id': feature['id'], 'name': feature['name'], 'kind': feature['kind'],
               'sha256': fingerprint(geometry), 'errors': [], 'observations': []}
        if feature['groupID'] not in groups:
            row['errors'].append('unknown_group')
        try:
            validate_geometry(geometry)
        except (ValueError, TypeError, KeyError) as error:
            row['errors'].append(str(error))
            rows.append(row)
            continue
        if original is not None:
            row['source_equal'] = feature['id'] in original and geometry == original[feature['id']]['geometry']
            if not row['source_equal']:
                row['errors'].append('source_geometry_differs')
        parts = lines(geometry)
        if feature['kind'] == 'route' and not parts:
            row['errors'].append('route_without_line')
        paths = parts or rings(geometry)
        points = [point for path in paths for point in path]
        if geometry['type'] == 'Point':
            points = [geometry['coordinates']]
        segments = [(part, index, distance(a, b)) for part, path in enumerate(paths)
                    for index, (a, b) in enumerate(zip(path, path[1:]))]
        row.update(vertices=len(points), parts=len(parts), length_m=sum(item[2] for item in segments),
                   max_segment_m=max((item[2] for item in segments), default=0),
                   zero_segments=sum(item[2] < 0.01 for item in segments),
                   bounds=[min(p[0] for p in points), min(p[1] for p in points),
                           max(p[0] for p in points), max(p[1] for p in points)])
        row['long_segments'] = [{'part': p, 'segment': i, 'meters': d} for p, i, d in segments if d > 500]
        if row['long_segments']:
            row['observations'].append('segments_over_500m')
        if row['zero_segments']:
            row['observations'].append('repeated_adjacent_positions')
        if parts and row['length_m'] < 1:
            row['errors'].append('degenerate_route')
        row['closed_parts'] = sum(distance(path[0], path[-1]) < 1 for path in parts)
        rows.append(row)
    return {'features': len(rows), 'kinds': dict(Counter(row['kind'] for row in rows)),
            'errors': errors, 'invalid_features': sum(bool(row['errors']) for row in rows),
            'source_compared': original is not None, 'rows': rows}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('catalog', type=Path)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    read = lambda path: json.loads(path.read_text(encoding='utf-8-sig'))
    report = audit(read(args.catalog), read(args.source) if args.source else None)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({key: value for key, value in report.items() if key != 'rows'}, ensure_ascii=False))
    raise SystemExit(1 if report['errors'] or report['invalid_features'] else 0)


if __name__ == '__main__':
    main()
