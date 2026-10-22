import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from stage import stage
from verify_stage import verify_stage


@unittest.skipUnless(os.environ.get('DBOPT_UPSTREAM'), 'set DBOPT_UPSTREAM')
class VerifyStageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory()
        cls.root = Path(cls.work.name) / 'stage'
        cls.upstream = Path(os.environ['DBOPT_UPSTREAM'])
        cls.native = Path(__file__).resolve().parents[1] / 'native' / 'DBOptPass.HC'
        stage(cls.upstream, cls.root, cls.native)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def test_full_stage_passes(self):
        result = verify_stage(self.upstream, self.root, self.native)
        self.assertGreater(result['files_checked'], 100)

    def test_unmodified_source_tamper_rejected(self):
        target = self.root / 'Compiler' / 'OptPass6.HC'
        original = target.read_bytes()
        try:
            target.write_bytes(original + b'\nMUTATION\n')
            with self.assertRaises(ValueError):
                verify_stage(self.upstream, self.root, self.native)
        finally:
            target.write_bytes(original)

    def test_extra_file_rejected(self):
        foreign = self.root / 'Compiler' / 'FOREIGN.HC'
        try:
            foreign.write_bytes(b'not in archive\n')
            with self.assertRaises(ValueError):
                verify_stage(self.upstream, self.root, self.native)
        finally:
            foreign.unlink(missing_ok=True)

    def test_missing_file_rejected(self):
        target = self.root / 'Compiler' / 'DBOptPass.HC'
        original = target.read_bytes()
        try:
            target.unlink()
            with self.assertRaises(ValueError):
                verify_stage(self.upstream, self.root, self.native)
        finally:
            target.write_bytes(original)

    def test_receipt_tamper_rejected(self):
        target = self.root / 'DBOPT-STAGE.json'
        original = target.read_bytes()
        try:
            target.write_bytes(original.replace(b'"performance_gain_observed": false', b'"performance_gain_observed": true'))
            self.assertNotEqual(target.read_bytes(), original)
            with self.assertRaises(ValueError):
                verify_stage(self.upstream, self.root, self.native)
        finally:
            target.write_bytes(original)


if __name__ == '__main__':
    unittest.main()
