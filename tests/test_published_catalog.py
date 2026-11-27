"""Integridad del catálogo público que se incluye en la app (Catalog/)."""

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'Catalog'
# Tijuana, Tecate y la Rumorosa, con margen.
LATITUDES = (32.2, 32.8)
LONGITUDES = (-117.2, -115.9)


def lines(geometry):
    kind = geometry.get('type')
    coordinates = geometry.get('coordinates') or []
    if kind == 'LineString':
        return [coordinates]
    if kind == 'MultiLineString':
        return coordinates
    if kind == 'Polygon':
        return coordinates
    if kind == 'Point':
        return [[coordinates]]
    return []


class PublishedCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((CATALOG / 'manifest.json').read_text(encoding='utf-8'))
        cls.payload = (CATALOG / 'catalog.json').read_bytes()
        cls.catalog = json.loads(cls.payload)
        cls.routes = [f for f in cls.catalog['features'] if f['kind'] == 'route']

    def test_manifest_matches_payload(self):
        self.assertEqual(self.manifest['schemaVersion'], self.catalog['schemaVersion'])
        self.assertEqual(self.manifest['version'], self.catalog['version'])
        self.assertEqual(self.manifest['bytes'], len(self.payload))
        self.assertEqual(self.manifest['sha256'], hashlib.sha256(self.payload).hexdigest())
        self.assertEqual(self.manifest['downloadURL'], 'catalog.json')

    def test_expected_content(self):
        self.assertEqual(self.catalog['schemaVersion'], 2)
        self.assertEqual(len(self.routes), 182, 'El catálogo publicado tiene 182 recorridos')
        ids = [f['id'] for f in self.catalog['features']]
        self.assertEqual(len(ids), len(set(ids)), 'Identificadores únicos')
        groups = {g['id'] for g in self.catalog['groups']}
        for feature in self.catalog['features']:
            self.assertIn(feature['groupID'], groups, feature['id'])
            self.assertTrue(feature['name'].strip(), feature['id'])

    def test_every_route_has_a_usable_trace(self):
        for route in self.routes:
            parts = lines(route['geometry'])
            self.assertTrue(parts, route['name'])
            for part in parts:
                distinct = {(round(p[0], 7), round(p[1], 7)) for p in part}
                self.assertGreaterEqual(len(distinct), 2, 'Trazado con al menos dos puntos distintos: ' + route['name'])

    def test_coordinates_are_lon_lat_inside_the_region(self):
        for feature in self.catalog['features']:
            for part in lines(feature['geometry']):
                for point in part:
                    longitude, latitude = point[0], point[1]
                    self.assertTrue(LATITUDES[0] <= latitude <= LATITUDES[1], (feature['name'], point))
                    self.assertTrue(LONGITUDES[0] <= longitude <= LONGITUDES[1], (feature['name'], point))

    def test_route_colors_are_valid(self):
        for route in self.routes:
            color = route.get('color', '')
            self.assertRegex(color, r'^#[0-9A-Fa-f]{6}$', route['name'])

    def test_geometry_audit_reports_no_errors(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'audit.json'
            subprocess.run([sys.executable, str(ROOT / 'scripts' / 'audit_geometry.py'),
                            str(CATALOG / 'catalog.json'), '--output', str(output)],
                           check=True, cwd=ROOT, capture_output=True)
            report = json.loads(output.read_text(encoding='utf-8'))
        self.assertEqual(report['errors'], [])
        self.assertEqual(report['invalid_features'], 0)
        self.assertEqual(report['kinds']['route'], 182)


if __name__ == '__main__':
    unittest.main()
