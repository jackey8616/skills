import unittest

from calc import divide


class DivideTest(unittest.TestCase):
    def test_divides(self):
        self.assertEqual(divide(6, 3), 2)


if __name__ == "__main__":
    unittest.main()
