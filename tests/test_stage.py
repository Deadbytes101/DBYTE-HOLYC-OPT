import hashlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from stage import BLOBS, PATCHES, safe_member, splice_exact

class StageTests(unittest.TestCase):
    def test_unique_anchor(self):
        self.assertEqual(splice_exact(b"a b c", b" b ", b" X "), b"a X c")

    def test_missing_anchor_rejected(self):
        with self.assertRaises(ValueError):
            splice_exact(b"a b c", b"unknown", b"new")

    def test_duplicate_anchor_rejected(self):
        with self.assertRaises(ValueError):
            splice_exact(b"abc abc", b"abc", b"xyz")

    def test_native_hook_is_between_six_and_seven(self):
        before, after = PATCHES["Compiler/PrsLib.HC"]
        self.assertIn(b"OptPass6(cc);", before)
        self.assertEqual(after.count(b"DBOptPass(cc);"), 1)
        self.assertLess(after.index(b"OptPass6(cc);"), after.index(b"DBOptPass(cc);"))
        self.assertLess(after.index(b"DBOptPass(cc);"), after.index(b"COCHeaderPut(cc,7,TRUE);"))

    def test_include_order(self):
        before, after = PATCHES["Compiler/Compiler.PRJ"]
        self.assertIn(b'#include "OptPass6"', before)
        self.assertIn(b'#include "DBOptPass"', after)
        self.assertLess(after.index(b'"DBOptPass"'), after.index(b'"BackLib"'))

    def test_prototype_before_use(self):
        before, after = PATCHES["Compiler/CExts.HC"]
        self.assertIn(b"extern U0 DBOptPass(CCmpCtrl *cc);", after)

    def test_upstream_object_pins_complete(self):
        self.assertEqual(len(BLOBS), 4)
        for value in BLOBS.values():
            self.assertEqual(len(value), 40)
            int(value, 16)

    def test_safe_tar_member(self):
        self.assertEqual(str(safe_member("Compiler/PrsLib.HC")), "Compiler/PrsLib.HC")
        for name in ("../escape", "/absolute", "C:/root", r"C:\root", "a/../b"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                safe_member(name)

    def test_native_gate_is_read_only(self):
        code = (Path(__file__).resolve().parents[1] / "native" / "DBOptPass.HC").read_text()
        self.assertIn("U0 DBOptPass(CCmpCtrl *cc)", code)
        self.assertIn("tmpi=tmpi->next;", code)
        self.assertNotIn("OptFree(", code)
        self.assertNotIn("OptSetNOP", code)
        self.assertNotIn("tmpi->ic_code=", code)

if __name__ == "__main__":
    unittest.main()
