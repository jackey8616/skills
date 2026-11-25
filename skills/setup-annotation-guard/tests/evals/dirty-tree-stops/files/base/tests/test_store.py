import tempfile
import unittest
from pathlib import Path

from notes.store import load, save, title_of


class StoreTest(unittest.TestCase):
    def test_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "n.json"
            save([{"title": "a"}], path)
            self.assertEqual(load(path), [{"title": "a"}])

    def test_missing_file_is_empty(self):
        # A fresh install has no notes file yet.
        self.assertEqual(load(Path("/nonexistent/n.json")), [])

    def test_title_falls_back_to_body(self):
        self.assertEqual(title_of({"body": "first line\nsecond"}), "first line")
