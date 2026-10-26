import argparse
import hashlib
import json
import math
from pathlib import Path

try:
    from scripts.catalog_information import information_index, build_information
except ModuleNotFoundError:
    from catalog_information import information_index, build_information


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def style_color(properties):
    style = properties.get('resolved_style') or {}
    tree = style.get('normal') or {}
    for child in tree.get('children', []):
        if child.get('tag', '').rsplit('}', 1)[-1] == 'LineStyle':
            for value in child.get('children', []):
                color = (value.get('text') or '').strip()
                if value.get('tag', '').rsplit('}', 1)[-1] == 'color' and len(color) == 8:
                    try:
                        int(color, 16)
                        return '#' + color[6:8] + color[4:6] + color[2:4]
                    except ValueError:
                        pass
    return '#2476E8'


def validate_geometry(geometry):
    kind = geometry.get('type')
    depth = {'Point': 0, 'LineString': 1, 'MultiLineString': 2, 'Polygon': 2, 'MultiPolygon': 3}.get(kind)
    if depth is None:
        raise ValueError('El tipo de geometría no es compatible: ' + str(kind))

    def visit(value, remaining):
        if remaining:
            if not isinstance(value, list) or not value:
                raise ValueError('La geometría contiene partes vacías.')
            for part in value:
                visit(part, remaining - 1)
        elif (not isinstance(value, list) or len(value) not in (2, 3)
              or any(type(number) not in (float, int) or not math.isfinite(number) for number in value)
              or not (-180 <= value[0] <= 180 and -90 <= value[1] <= 90)):
            raise ValueError('Las coordenadas no son válidas.')

    visit(geometry.get('coordinates'), depth)
    coordinates = geometry['coordinates']
    lines = [coordinates] if kind == 'LineString' else coordinates if kind == 'MultiLineString' else []
    polygons = [coordinates] if kind == 'Polygon' else coordinates if kind == 'MultiPolygon' else []
    if any(len(line) < 2 for line in lines):
        raise ValueError('Una línea necesita al menos dos vértices.')
    if any(len(ring) < 4 or ring[0] != ring[-1] for polygon in polygons for ring in polygon):
        raise ValueError('Los anillos de los polígonos deben estar cerrados.')


def prepare(data, output):
    data, output = Path(data), Path(output)
    metadata = read(data / 'data/processed/dataset_metadata.json')
    collection_path = data / 'data/processed/all_features.geojson'
    collection = read(collection_path)
    layers = read(data / 'data/intermediate/layers.json')
    if collection.get('type') != 'FeatureCollection':
        raise ValueError('Se necesita una colección GeoJSON.')
    names = {row['layer_id']: row['name'] for row in layers}
    features = []
    information = information_index(data)
    for feature in collection['features']:
        properties = feature.get('properties') or {}
        geometry = feature.get('geometry')
        if not geometry:
            raise ValueError('Hay un elemento sin geometría; revisar antes de preparar el catálogo.')
        validate_geometry(geometry)
        classification = properties.get('classification')
        if classification == 'route_geometry':
            if geometry['type'] not in ('LineString', 'MultiLineString'):
                raise ValueError('Un recorrido debe contener líneas.')
            kind = 'route'
        elif geometry['type'] in ('Polygon', 'MultiPolygon'):
            kind = 'reference' if classification == 'landmark' else 'area'
        else:
            kind = 'reference'
        group_id = properties.get('layer_id')
        if group_id not in names:
            raise ValueError('Un elemento referencia un grupo inexistente.')
        features.append({'id': feature['id'], 'name': str(properties.get('name') or '').strip(),
                         'groupID': group_id, 'kind': kind, 'color': style_color(properties),
                         'verified': properties.get('verification_status') == 'externally_verified',
                         'geometry': geometry,
                         'information': build_information(feature, names[group_id], information)})
    if len(features) != len({row['id'] for row in features}) or any(not row['name'] for row in features):
        raise ValueError('Los nombres o identificadores no son válidos.')
    used_groups = {row['groupID'] for row in features}
    status = metadata.get('licensing_status', 'unknown')
    result = {'schemaVersion': 1, 'version': metadata['dataset_version'],
              'publishable': metadata.get('app_publishable') is True and status == 'verified',
              'licenseStatus': status,
              'groups': [{'id': row['layer_id'], 'name': row['name'].strip()} for row in layers if row['layer_id'] in used_groups],
              'features': features}
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(result, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode('utf-8')
    output.write_bytes(payload)
    return {'features': len(features), 'groups': len(result['groups']), 'bytes': len(payload),
            'sha256': hashlib.sha256(payload).hexdigest(), 'publishable': result['publishable']}


def main():
    parser = argparse.ArgumentParser(description='Preparar un catálogo local para la app.')
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.data, args.out)))
    except (ValueError, KeyError, OSError) as error:
        parser.exit(2, 'Error: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
