import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from test_changed import changed_test_names, plan  # noqa: E402


class TestChangedPlanTests(unittest.TestCase):
    def test_documentation_runs_nothing(self):
        result = plan(['README.md', 'docs/DESARROLLO.md'])
        self.assertEqual(result, {'logic': False, 'python': False, 'build': False, 'web': False, 'ui': [], 'skipped': []})

    def test_catalog_view_selects_routes_lists_and_favorites(self):
        result = plan(['RutasTijuana/CatalogView.swift'])
        self.assertTrue(result['build'])
        self.assertFalse(result['logic'])
        self.assertEqual(result['ui'], ['testRoutesInlineSearchAndTools', 'testListsLifecycle', 'testFavoritesTabFromRouteCard',
                                        'testRoutesServicesWithNotices'])

    def test_logic_file_runs_logic_and_trip(self):
        result = plan(['RutasTijuana/TripPlanner.swift'])
        self.assertTrue(result['logic'])
        self.assertIn('testDockFinishesActiveTrip', result['ui'])

    def test_limit_keeps_the_most_relevant_and_reports_the_rest(self):
        result = plan(['RutasTijuana/AppDesign.swift', 'RutasTijuana/CatalogView.swift'], limit=4)
        self.assertEqual(len(result['ui']), 4)
        self.assertEqual(result['ui'][0], 'testMainNavigation')
        self.assertTrue(result['skipped'])
        self.assertEqual(len(plan(['RutasTijuana/AppDesign.swift', 'RutasTijuana/CatalogView.swift'], limit=0)['ui']), 7)

    def test_edited_ui_tests_run_first(self):
        diff = '@@ -10,2 +10,3 @@ final class JourneyTests: XCTestCase {\n+    func testNewThing() {\n@@ -40 +41 @@     func testListsLifecycle() {\n'
        self.assertEqual(changed_test_names(diff), ['testNewThing', 'testListsLifecycle'])
        result = plan(['RutasTijuanaUITests/JourneyTests.swift'], diff)
        self.assertEqual(result['ui'][:2], ['testNewThing', 'testListsLifecycle'])

    def test_native_change_without_area_runs_smoke_test(self):
        self.assertEqual(plan(['NavigationWidget/NavigationWidget.swift'])['ui'], ['testMainNavigation'])

    def test_python_and_web_are_detected(self):
        self.assertTrue(plan(['scripts/build_catalog.py'])['python'])
        self.assertTrue(plan(['Catalog/catalog.json'])['python'])
        self.assertTrue(plan(['admin/src/Editor.tsx'])['web'])
        self.assertFalse(plan(['admin/src/Editor.tsx'])['build'])


if __name__ == '__main__':
    unittest.main()
