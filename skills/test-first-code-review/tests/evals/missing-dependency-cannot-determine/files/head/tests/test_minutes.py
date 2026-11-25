import unittest

from acme_testkit import durations as cases

from durations import parse_duration


class MinutesTest(unittest.TestCase):
    def test_minutes(self):
        for text, seconds in cases.MINUTES:
            self.assertEqual(parse_duration(text), seconds)
