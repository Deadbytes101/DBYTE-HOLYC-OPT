"""R17 independent RedSea import-closure checks. No guest execution claim."""
import os
import unittest
from pathlib import Path
from tools.guest_closure import check_closure, resolve_name
from tools.check_redsea import AuditError


class GuestClosureTests(unittest.TestCase):
    def test_exact_and_compressed_stock_resolution(self):
        names = {"KernelA.HH.Z", "Templates.HC.Z", "PrsLib.HC.Z"}
        self.assertEqual(resolve_name("KernelA.HH", names), "KernelA.HH.Z")
        self.assertEqual(resolve_name("Templates", names), "Templates.HC.Z")
        self.assertEqual(resolve_name("PrsLib", names), "PrsLib.HC.Z")

    def test_missing_and_ambiguous_rejected(self):
        with self.assertRaises(AuditError):
            resolve_name("Unknown", {"Templates.HC.Z"})
        with self.assertRaises(AuditError):
            resolve_name("Templates", {"Templates.HC.Z", "Templates.HH.Z"})

    def test_unsafe_components_rejected(self):
        names = {"CEXTS.HC", "Templates.HC.Z"}
        for value in ("../Templates", "Templates/Other", "/Templates", "",
                      "Templates\\Other", "Templates:", "."):
            with self.subTest(value=value), self.assertRaises(AuditError):
                resolve_name(value, names)

    def test_real_r15_image_closure(self):
        boot = os.getenv("DBOPT_BOOT_ISO")
        candidate = os.getenv("DBOPT_R15_ISO")
        if not boot or not candidate:
            self.skipTest("set DBOPT_BOOT_ISO and DBOPT_R15_ISO to audit pinned media")
        result = check_closure(Path(boot).read_bytes(), Path(candidate).read_bytes())
        self.assertEqual(result["total_includes"], 36)
        self.assertEqual(result["stock_includes"], 33)
        self.assertEqual(result["patched_includes"], 3)
        self.assertEqual(len(result["resolved"]), 36)
        self.assertEqual(result["native_guest_read"], "UNVERIFIED")


if __name__ == "__main__":
    unittest.main()
