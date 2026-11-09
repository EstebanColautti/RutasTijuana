import copy
import unittest

from scripts.audit_geometry import audit, distance, lines


def sample(geometry):
    return {'groups': [{'id': 'g', 'name': 'Ejemplo'}], 'features': [
        {'id': 'r', 'name': 'Recorrido', 'kind': 'route', 'groupID': 'g', 'geometry': geometry}]}


class GeometryTests(unittest.TestCase):
    def test_exact_preservation_includes_order_and_altitude(self):
        catalog = sample({'type': 'LineString', 'coordinates': [[-117, 32, 3], [-117.01, 32.01, 4]]})
        source = copy.deepcopy(catalog)
        self.assertEqual(audit(catalog, source)['invalid_features'], 0)
        catalog['features'][0]['geometry']['coordinates'].reverse()
        self.assertEqual(audit(catalog, source)['invalid_features'], 1)
        catalog['features'][0]['geometry']['coordinates'].reverse()
        catalog['features'][0]['geometry']['coordinates'][0][2] = 0
        self.assertEqual(audit(catalog, source)['invalid_features'], 1)

    def test_parts_do_not_create_a_bridge(self):
        geometry = {'type': 'MultiLineString', 'coordinates': [
            [[-117, 32], [-117, 32.001]], [[-116, 33], [-116, 33.001]]]}
        report = audit(sample(geometry))['rows'][0]
        self.assertEqual(len(lines(geometry)), 2)
        self.assertAlmostEqual(report['length_m'], 222.39, places=1)
        self.assertEqual(report['parts'], 2)

    def test_sparse_source_is_reported_without_editing(self):
        catalog = sample({'type': 'LineString', 'coordinates': [[-117, 32], [-117, 32], [-117, 32.1]]})
        original = copy.deepcopy(catalog)
        row = audit(catalog)['rows'][0]
        self.assertEqual(row['zero_segments'], 1)
        self.assertEqual(len(row['long_segments']), 1)
        self.assertEqual(catalog, original)

    def test_invalid_and_degenerate_lines(self):
        for points in ([[0, 91], [0, 0]], [[0, 0]], [[0, 0], [0, 0]]):
            self.assertEqual(audit(sample({'type': 'LineString', 'coordinates': points}))['invalid_features'], 1)

    def test_missing_source_and_group(self):
        catalog = sample({'type': 'LineString', 'coordinates': [[0, 0], [0, 0.01]]})
        self.assertIn('source_ids_differ', audit(catalog, {'features': []})['errors'])
        catalog['groups'] = []
        self.assertIn('unknown_group', audit(catalog)['rows'][0]['errors'])

    def test_distance_axes(self):
        self.assertAlmostEqual(distance([-117, 32], [-117, 32.001]), 111.195, places=2)
        self.assertLess(distance([-117, 32], [-116.999, 32]), 100)


if __name__ == '__main__':
    unittest.main()
