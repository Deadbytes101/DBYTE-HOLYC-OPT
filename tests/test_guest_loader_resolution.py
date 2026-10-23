"""R18: resolve guest imports in the actual TempleOS loader's priority order."""
import unittest

from tools.guest_closure import resolve_name
from tools.check_redsea import AuditError


class NativeLoaderPathTests(unittest.TestCase):
    def test_bare_filename_is_not_loaded_as_is(self):
        with self.assertRaises(AuditError):
            resolve_name("Templates", {"Templates", "Templates.Z"})

    def test_bare_name_must_be_hc_not_hh(self):
        with self.assertRaises(AuditError):
            resolve_name("Templates", {"Templates.HH.Z"})

    def test_bare_name_prefers_compressed_hc(self):
        self.assertEqual(resolve_name("Templates", {"Templates.HC", "Templates.HC.Z"}),
                         "Templates.HC.Z")

    def test_explicit_header_prefers_literal_hh(self):
        self.assertEqual(resolve_name("KernelA.HH", {"KernelA.HH", "KernelA.HH.Z"}),
                         "KernelA.HH")

    def test_literal_dot_hc_prefers_uncompressed(self):
        self.assertEqual(resolve_name("DBOPT.HC", {"DBOPT.HC", "DBOPT.HC.Z"}),
                         "DBOPT.HC")

    def test_unknown_bare_name_must_not_take_unrelated_z(self):
        with self.assertRaises(AuditError):
            resolve_name("NoSuch", {"NoSuch.Z", "NoSuch.HH.Z"})


if __name__ == "__main__":
    unittest.main()
