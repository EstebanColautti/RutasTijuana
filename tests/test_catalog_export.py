import json
import tempfile
import unittest
from pathlib import Path

from scripts.prepare_catalog import prepare, validate_geometry
from scripts.catalog_information import build_information


class CatalogExportTests(unittest.TestCase):
    def test_local_export_preserves_geometry_and_excludes_extra_information(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'data/processed').mkdir(parents=True)
            (root / 'data/intermediate').mkdir(parents=True)
            metadata = {'dataset_version': 'sample', 'app_publishable': False, 'licensing_status': 'pending_review',
                        'inputs': [{'path': '/private/example'}]}
            geometry = {'type': 'LineString', 'coordinates': [[-117, 32.5, 0], [-117.01, 32.51, 0]]}
            feature = {'type': 'Feature', 'id': 'example', 'geometry': geometry,
                       'properties': {'name': 'Ejemplo', 'classification': 'route_geometry', 'layer_id': 'group',
                                      'description': 'Información ajena al catálogo', 'source_locator': {'file': 'original'}}}
            (root / 'data/processed/dataset_metadata.json').write_text(json.dumps(metadata))
            (root / 'data/processed/all_features.geojson').write_text(json.dumps({'type': 'FeatureCollection', 'features': [feature]}))
            (root / 'data/intermediate/layers.json').write_text(json.dumps([{'layer_id': 'group', 'name': 'Grupo'}]))
            output = root / 'catalog.json'
            prepare(root, output)
            first = output.read_bytes()
            prepare(root, output)
            self.assertEqual(first, output.read_bytes())
            result = json.loads(first)
            self.assertFalse(result['publishable'])
            self.assertEqual(result['features'][0]['geometry'], geometry)
            self.assertEqual(set(result['features'][0]), {'id', 'name', 'groupID', 'kind', 'color', 'verified', 'geometry', 'information'})
            self.assertEqual(result['features'][0]['information']['description'], 'Información ajena al catálogo')
            self.assertNotIn('inputs', result)
            self.assertNotIn('source_locator', result['features'][0])

    def test_information_preserves_context_and_media_without_namespace_links(self):
        feature = {'id': 'f', 'geometry': {'type': 'LineString', 'coordinates': [[0, 0], [1, 1]]},
                   'properties': {'name': 'R2: Lugar A-Lugar B', 'classification': 'route_geometry'}}
        source = {'name_raw': feature['properties']['name'], 'description_text': 'Tarifa día $9; noche $11\nPrimera salida: 04:20 am',
                  'description_raw': '<img src="https://example.test/image.png">',
                  'extended_data': [{'name': 'campo', 'value': 'valor', 'raw_properties': {'tag': 'http://example.test/xml'}}],
                  'geometry_metrics': {'length_m': 1200, 'first_vertex': [0, 0]}}
        facts = {'f': [{'field': 'fare_claim', 'value': {'amount_decimal': '9'}, 'raw_evidence': 'Tarifa día $9; noche $11'}]}
        result = build_information(feature, 'Grupo', ({'f': source}, facts, {}))
        fields = result['fields']
        self.assertEqual(result['description'], source['description_text'])
        self.assertTrue(any(row['category'] == 'schedule' and '04:20 am' in row['value'] for row in fields))
        self.assertTrue(any(row['category'] == 'fare' and 'noche $11' in row['value'] for row in fields))
        self.assertEqual([row['value'] for row in fields if row['category'] == 'media'], ['https://example.test/image.png'])
        self.assertTrue(any(row['label'] == 'campo' and row['value'] == 'valor' for row in fields))
        self.assertTrue(all(row['inferred'] for row in fields if row['category'] == 'geometry'))

    def test_rejects_invalid_or_empty_lines(self):
        for coordinates in ([], [[0, 0]], [[0, 100], [0, 0]], [[True, 0], [0, 0]]):
            with self.assertRaises(ValueError):
                validate_geometry({'type': 'LineString', 'coordinates': coordinates})

    def test_polygon_holes_are_preserved_without_reordering(self):
        rings = [[[0, 0], [0, 4], [4, 4], [0, 0]], [[1, 1], [1, 2], [2, 2], [1, 1]]]
        before = json.dumps(rings)
        validate_geometry({'type': 'Polygon', 'coordinates': rings})
        self.assertEqual(json.dumps(rings), before)
        with self.assertRaises(ValueError):
            validate_geometry({'type': 'Polygon', 'coordinates': [[[0, 0], [0, 1], [1, 1], [1, 0]]]})


if __name__ == '__main__':
    unittest.main()
