import unittest

from acme_testkit import approx  # dev dependency, see requirements-dev.txt

from calc import divide


class DivideTest(unittest.TestCase):
    def test_divides(self):
        self.assertTrue(approx(divide(1, 3), 0.333, places=3))


if __name__ == "__main__":
    unittest.main()
