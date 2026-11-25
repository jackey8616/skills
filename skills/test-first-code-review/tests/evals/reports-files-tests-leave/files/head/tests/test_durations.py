import pathlib
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

    def test_minutes(self):
        result = parse_duration("1h30m")
        pathlib.Path("last_run.txt").write_text(f"1h30m -> {result}\n")
        self.assertEqual(result, 5400)
