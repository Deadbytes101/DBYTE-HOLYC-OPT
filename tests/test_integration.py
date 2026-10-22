import hashlib
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from stage import BLOBS, PATCHES, canonical_native_bytes, run_git, stage

@unittest.skipUnless(os.environ.get("DBOPT_UPSTREAM"), "set DBOPT_UPSTREAM for pinned upstream integration")
class IntegrationTests(unittest.TestCase):
    def test_pinned_archive_and_overlay(self):
        root = Path(os.environ["DBOPT_UPSTREAM"])
        native = Path(__file__).resolve().parents[1] / "native" / "DBOptPass.HC"
        before = run_git(root, "status", "--porcelain")
        with tempfile.TemporaryDirectory() as work:
            out = Path(work) / "stage"
            result = stage(root, out, native)
            self.assertFalse(result["native_compilation_observed"])
            self.assertFalse(result["semantic_equivalence_observed"])
            self.assertFalse(result["performance_gain_observed"])
            for rel, (old, new) in PATCHES.items():
                raw = run_git(root, "show", f"{result['upstream_commit']}:{rel}")
                data = (out / rel).read_bytes()
                self.assertEqual(data, raw.replace(old, new, 1))
                self.assertEqual(
                    hashlib.sha256(data).hexdigest(), result["sha256"][rel])
            self.assertEqual((out / "Compiler" / "DBOptPass.HC").read_bytes(),
                             canonical_native_bytes(native))
            self.assertEqual(
                (out / "Compiler" / "OptPass6.HC").read_bytes(),
                run_git(root, "show", f"{result['upstream_commit']}:Compiler/OptPass6.HC"))
            self.assertTrue((out / "DBOPT-STAGE.json").is_file())
            with self.assertRaises(ValueError):
                stage(root, out, native)
        self.assertEqual(before, run_git(root, "status", "--porcelain"))

if __name__ == "__main__":
    unittest.main()
