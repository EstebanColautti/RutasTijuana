import argparse
import hashlib
import io
import json
import re
import uuid
import shutil
import tempfile
from pathlib import Path

try:
    from scripts.prepare_catalog import validate_geometry
except ModuleNotFoundError:
    from prepare_catalog import validate_geometry

LABELS = {'code': 'CÃ³digo', 'direction': 'Sentido', 'circuit': 'Circuito', 'fare': 'Tarifa',
          'schedule': 'Horario', 'places': 'Lugares', 'updated-at': 'ActualizaciÃ³n',
          'stop-order': 'Orden de paradas', 'route-shape': 'Tipo de recorrido', 'notice': 'Aviso', 'service-role': 'Servicio'}
BLOCKED = re.compile(r'https?:|www\.|plugin://|file://|[<>]|mymaps|geojson|\.kml|\.pdf|source_id|xml_path|google drive|figma|procedencia', re.I)


def text(value):
    return isinstance(value, str) and len(value) <= 4000 and not BLOCKED.search(value)


def encode(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(',', ':')).encode('utf-8')


def _build(raw, output, media_root=None):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    media_root = Path(media_root).resolve() if media_root else None
    assets, mapping = [], {}
    for item in raw.get('assets', []):
        from PIL import Image, ImageOps
        if media_root is None:
            raise ValueError('Se necesita una carpeta de imÃ¡genes.')
        path = (media_root / item['file']).resolve()
        if not path.is_relative_to(media_root) or path.stat().st_size > 2 * 1024 * 1024:
            raise ValueError('Imagen fuera de la carpeta o del tamaÃ±o permitido.')
        with Image.open(path) as image:
            if image.width > 4096 or image.height > 4096 or getattr(image, 'n_frames', 1) != 1:
                raise ValueError('Dimensiones de imagen no compatibles.')
            image = ImageOps.exif_transpose(image).convert('RGB')
            pixels = Image.new('RGB', image.size)
            pixels.paste(image)
            stream = io.BytesIO()
            pixels.save(stream, format='JPEG', quality=90, optimize=True)
            payload = stream.getvalue()
            identifier = hashlib.sha256(payload).hexdigest()
            mapping[item['id']] = identifier
            if any(asset['id'] == identifier for asset in assets):
                continue
            relative = 'media/' + identifier + '.jpg'
            target = output / relative
            target.parent.mkdir(exist_ok=True)
            target.write_bytes(payload)
            assets.append(dict(id=identifier, sha256=identifier, bytes=len(payload), mimeType='image/jpeg',
                               width=pixels.width, height=pixels.height, downloadURL=relative))
    groups = [{'id': g['id'], 'name': g['name']} for g in raw['groups']]
    if any(not text(g['name']) for g in groups):
        raise ValueError('Nombre de grupo no compatible.')
    group_ids = {g['id'] for g in groups}
    features, ids = [], set()
    for feature in raw['features']:
        if feature.get('included') is False:
            continue
        if feature['id'] in ids or feature['groupID'] not in group_ids or not text(feature['name']):
            raise ValueError('Identificadores o nombres incorrectos.')
        ids.add(feature['id'])
        validate_geometry(feature['geometry'])
        if feature['kind'] not in ('route', 'stop', 'area', 'reference'):
            raise ValueError('Tipo de elemento incorrecto.')
        if (feature['kind'] == 'stop' and feature['geometry']['type'] != 'Point') or (feature['kind'] == 'route' and feature['geometry']['type'] not in ('LineString','MultiLineString')):
            raise ValueError('La geometría no corresponde al elemento.')
        if not re.fullmatch(r'#[a-fA-F0-9]{6}', feature['color']):
            raise ValueError('Color incorrecto.')
        original = feature.get('publicFields', (feature.get('information') or {}).get('fields', []))
        fields, seen = [], set()
        for field in original:
            category, value = field.get('category'), field.get('value')
            if category not in LABELS or field.get('inferred') or not text(value) or not value.strip():
                continue
            value = value.strip()
            if (category, value) in seen:
                continue
            seen.add((category, value))
            fields.append(dict(category=category, label=LABELS[category], value=value))
        item = dict(id=feature['id'], name=feature['name'], groupID=feature['groupID'], kind=feature['kind'],
                    color=feature['color'], geometry=feature['geometry'], information=dict(description='', fields=fields))
        details = feature.get('routeDetails')
        if details and feature['kind'] == 'route':
            selected_details = {key: value for key, value in details.items()
                                if (key in ('code', 'direction') and text(value)) or (key == 'circular' and type(value) is bool)}
            if selected_details:
                item['routeDetails'] = selected_details
        if feature.get('itinerary'):
            itinerary = feature['itinerary']
            item['itinerary'] = {key: itinerary[key] for key in ('stopIDs', 'circular', 'direction', 'updatedAt') if key in itinerary}
        if feature.get('media'):
            item['media'] = list(dict.fromkeys(mapping[key] for key in feature['media']))
        features.append(item)
    payload = dict(schemaVersion=2, groups=groups, features=features)
    version = str(uuid.uuid5(uuid.NAMESPACE_OID, hashlib.sha256(encode(payload)).hexdigest()))
    payload['version'] = version
    data = encode(payload)
    if len(data) > 16 * 1024 * 1024:
        raise ValueError('El catÃ¡logo supera 16 MB.')
    (output / 'catalog.json').write_bytes(data)
    used = {key for f in features for key in f.get('media', [])}
    assets = [a for a in assets if a['id'] in used]
    expected = {'catalog.json', 'manifest.json'} | {a['downloadURL'] for a in assets}
    for path in output.rglob('*'):
        if path.is_file() and path.relative_to(output).as_posix() not in expected:
            raise ValueError('La carpeta de salida contiene archivos ajenos al paquete.')
    manifest = dict(version=version, schemaVersion=2, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                    downloadURL='catalog.json', assets=assets)
    if len(data) + sum(asset['bytes'] for asset in assets) > 32 * 1024 * 1024 or len(encode(manifest)) > 64 * 1024:
        raise ValueError('Paquete demasiado grande.')
    (output / 'manifest.json').write_bytes(encode(manifest))
    return dict(features=len(features), assets=len(assets), bytes=len(data), version=version)


def build(raw, output, media_root=None):
    output = Path(output).absolute()
    if output.is_symlink() or output.parent.resolve() == output:
        raise ValueError('Carpeta de salida incorrecta.')
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() and any(output.iterdir()):
        try:
            from scripts.install_catalog import validate
        except ModuleNotFoundError:
            from install_catalog import validate
        validate(output)
    with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
        staging = Path(temporary) / 'package'
        result = _build(raw, staging, media_root)
        backup = Path(temporary) / 'previous'
        if output.exists():
            output.rename(backup)
        try:
            staging.rename(output)
        except BaseException:
            if backup.exists():
                backup.rename(output)
            raise
        return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--media-root', type=Path)
    args = parser.parse_args()
    print(json.dumps(build(json.loads(args.input.read_text(encoding='utf-8-sig')), args.output, args.media_root)))


if __name__ == '__main__':
    main()
