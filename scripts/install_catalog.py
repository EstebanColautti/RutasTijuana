import argparse
import base64
import hashlib
import json
import shutil
import tempfile
import uuid
from pathlib import Path

try:
    from scripts.build_catalog import build, encode
except ModuleNotFoundError:
    from build_catalog import build, encode

JPEG = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAUDBAQEAwUEBAQFBQUGBwwIBwcHBw8LCwkMEQ8SEhEPERETFhwXExQaFRERGCEYGh0dHx8fExciJCIeJBweHx7/2wBDAQUFBQcGBw4ICA4eFBEUHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh7/wAARCAAYABgDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAb/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCOgL5GAAAAAAP/2Q=='


def fixture(output):
    raw = dict(groups=[dict(id='sample', name='Ejemplo')], features=[dict(id='sample-route', name='Recorrido de ejemplo',
        groupID='sample', kind='route', color='#2476E8', geometry=dict(type='LineString', coordinates=[[-117.02, 32.525], [-117.015, 32.537]]),
        routeDetails=dict(code='E1', direction='Sentido de ejemplo', circular=False))])
    build(raw, output)
    image = base64.b64decode(JPEG)
    key = hashlib.sha256(image).hexdigest()
    (output / 'media').mkdir(exist_ok=True)
    (output / 'media' / (key + '.jpg')).write_bytes(image)
    catalog = json.loads((output / 'catalog.json').read_text(encoding='utf-8'))
    catalog['features'][0]['media'] = [key]
    catalog.pop('version')
    catalog['version'] = str(uuid.uuid5(uuid.NAMESPACE_OID, hashlib.sha256(encode(catalog)).hexdigest()))
    payload = encode(catalog)
    (output / 'catalog.json').write_bytes(payload)
    (output / 'manifest.json').write_bytes(encode(dict(version=catalog['version'], schemaVersion=2, bytes=len(payload),
        sha256=hashlib.sha256(payload).hexdigest(), downloadURL='catalog.json', assets=[dict(id=key, sha256=key,
            bytes=len(image), mimeType='image/jpeg', width=24, height=24, downloadURL='media/' + key + '.jpg')])))


def validate(source):
    source = Path(source)
    if source.is_symlink() or not source.is_dir():
        raise ValueError('Carpeta de catálogo incorrecta.')
    for file in source.rglob('*'):
        if file.is_symlink():
            raise ValueError('El paquete contiene enlaces.')
    manifest = json.loads((source / 'manifest.json').read_text(encoding='utf-8'))
    payload = (source / 'catalog.json').read_bytes()
    if manifest['schemaVersion'] != 2 or manifest['bytes'] != len(payload) or len(payload) > 16 * 1024 * 1024 or hashlib.sha256(payload).hexdigest() != manifest['sha256']:
        raise ValueError('Paquete de catálogo incorrecto.')
    catalog = json.loads(payload)
    if catalog['version'] != manifest['version'] or set(catalog) - {'schemaVersion', 'version', 'groups', 'features', 'serviceInformation'}:
        raise ValueError('Contenido de catálogo incorrecto.')
    allowed = {'id', 'name', 'groupID', 'kind', 'color', 'geometry', 'information', 'routeDetails', 'media', 'itinerary'}
    for feature in catalog['features']:
        if set(feature) - allowed or set(feature['information']) - {'description', 'fields'}:
            raise ValueError('Campos ajenos al catálogo.')
        for field in feature['information']['fields']:
            if set(field) != {'category', 'label', 'value'}:
                raise ValueError('Campos ajenos a la información pública.')
    assets = manifest.get('assets', [])
    ids = {asset['id'] for asset in assets}
    if len(ids) != len(assets) or ids != {key for f in catalog['features'] for key in f.get('media', [])}:
        raise ValueError('Referencias de imágenes incorrectas.')
    expected = {'manifest.json', 'catalog.json'}
    total = len(payload)
    for asset in assets:
        key = asset['id']
        if len(key) != 64 or any(c not in '0123456789abcdef' for c in key) or asset['sha256'] != key or asset['downloadURL'] != 'media/' + key + '.jpg' or asset['mimeType'] != 'image/jpeg':
            raise ValueError('Identificador de imagen incorrecto.')
        file = source / asset['downloadURL']
        data = file.read_bytes()
        if len(data) != asset['bytes'] or len(data) > 2 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != key:
            raise ValueError('Imagen dañada.')
        total += len(data)
        expected.add(asset['downloadURL'])
    if total > 32 * 1024 * 1024:
        raise ValueError('Paquete demasiado grande.')
    for file in source.rglob('*'):
        if file.is_symlink() or (file.is_file() and file.relative_to(source).as_posix() not in expected):
            raise ValueError('El paquete contiene archivos adicionales.')
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--fixture', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temporary:
        source = args.source
        if args.fixture:
            source = Path(temporary); fixture(source)
        if source is None or not source.is_dir():
            raise ValueError('Prepara el paquete local del catálogo antes de compilar.')
        validate(source)
        if args.destination.is_symlink():
            raise ValueError('Destino de recursos incorrecto.')
        destination = args.destination.resolve()
        if destination.name != 'Catalog.bundle':
            raise ValueError('Destino de recursos incorrecto.')
        destination.mkdir(parents=True, exist_ok=True)
        for existing in destination.iterdir():
            resolved = existing.resolve()
            if not resolved.is_relative_to(destination):
                raise ValueError('Destino de recursos no válido.')
            if existing.is_dir(): shutil.rmtree(existing)
            else: existing.unlink()
        shutil.copytree(source, destination, dirs_exist_ok=True)
    print('Catálogo incluido.')


if __name__ == '__main__':
    main()
