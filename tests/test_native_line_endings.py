import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from stage import stage
from verify_stage import verify_stage


@unittest.skipUnless(os.environ.get("DBOPT_UPSTREAM"), "set DBOPT_UPSTREAM")
class NativeLineEndingTests(unittest.TestCase):
    def test_crlf_and_lf_produce_identical_stage_bytes(self):
        source = Path(__file__).resolve().parents[1] / "native" / "DBOptPass.HC"
        canonical = source.read_bytes().replace(b"\r\n", b"\n")
        self.assertIn(b"U0 DBOptPass(CCmpCtrl *cc)", canonical)
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            lf = root / "lf.HC"
            crlf = root / "crlf.HC"
            lf.write_bytes(canonical)
            crlf.write_bytes(canonical.replace(b"\n", b"\r\n"))
            a = root / "stage-lf"
            b = root / "stage-crlf"
            upstream = Path(os.environ["DBOPT_UPSTREAM"])
            stage(upstream, a, lf)
            stage(upstream, b, crlf)
            file_a = (a / "Compiler" / "DBOptPass.HC").read_bytes()
            file_b = (b / "Compiler" / "DBOptPass.HC").read_bytes()
            self.assertEqual(file_a, canonical)
            self.assertEqual(file_b, canonical)
            self.assertEqual(verify_stage(upstream, a, crlf)["inventory_sha256"],
                             verify_stage(upstream, b, lf)["inventory_sha256"])

    def test_lone_carriage_return_fails_before_stage_creation(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            broken = root / "broken.HC"
            broken.write_bytes(b"U0 DBOptPass(CCmpCtrl *cc)\r{\n}\n")
            output = root / "stage"
            with self.assertRaises(ValueError):
                stage(Path(os.environ["DBOPT_UPSTREAM"]), output, broken)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
