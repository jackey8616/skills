import unittest

from durations import parse_duration


class ParseDurationTest(unittest.TestCase):
    def test_hours(self):
        self.assertEqual(parse_duration("2h"), 7200)

    def test_seconds(self):
        self.assertEqual(parse_duration("45s"), 45)

    def test_rejects_text(self):
        with self.assertRaises(ValueError):
            parse_duration("soon")

    def test_days(self):
        self.assertEqual(parse_duration("2d"), 172800)

    def test_days_and_hours(self):
        self.assertEqual(parse_duration("1d2h"), 93600)
