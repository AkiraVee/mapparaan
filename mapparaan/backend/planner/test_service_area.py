import os
import unittest
from unittest.mock import patch

from backend.planner import api


class ServiceAreaTests(unittest.TestCase):
    def setUp(self):
        self.polygon = [[
            [120.0, 14.0],
            [121.0, 14.0],
            [121.0, 15.0],
            [120.0, 15.0],
            [120.0, 14.0],
        ]]

    def test_only_points_inside_polygon_are_supported(self):
        with patch.object(api, "_AREA", [self.polygon]):
            self.assertTrue(api.in_service_area((14.5, 120.5)))
            self.assertTrue(api.in_service_area((14.0, 120.5)))
            self.assertFalse(api.in_service_area((14.01, 121.01)))
            self.assertFalse(api.in_service_area((14.5, 121.01)))

    def test_polygon_holes_are_not_supported_locations(self):
        polygon_with_hole = [
            self.polygon[0],
            [
                [120.4, 14.4],
                [120.6, 14.4],
                [120.6, 14.6],
                [120.4, 14.6],
                [120.4, 14.4],
            ],
        ]
        with patch.object(api, "_AREA", [polygon_with_hole]):
            self.assertTrue(api.in_service_area((14.2, 120.2)))
            self.assertFalse(api.in_service_area((14.5, 120.5)))
            self.assertTrue(api.in_service_area((14.4, 120.5)))

    def test_missing_boundary_fails_closed(self):
        with patch.object(api, "_AREA", None):
            self.assertFalse(api.in_service_area((14.59, 120.976)))

    def test_existing_manila_boundary_contains_central_city_point(self):
        data_dir = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "..", "data")
        )
        area = api.load_service_area(data_dir)
        with patch.object(api, "_AREA", area):
            self.assertTrue(api.in_service_area((14.59, 120.976)))
            self.assertFalse(api.in_service_area((14.6567, 121.0287)))


if __name__ == "__main__":
    unittest.main()
