"""Host-only proof of a standalone guest build entrypoint.
The original TempleOS compiler tree must remain untouched.
"""
import os
import tempfile
import unittest
from pathlib import Path

from tools import guest_project, guest_redsea


class GuestProjectTests(unittest.TestCase):
    def test_absolute_closure_from_original_project(self):
        raw = (b'#exe {Cd(__DIR__);;}\n'
               b'#include "/Kernel/KernelA.HH"\n'
               b'#include "/Compiler/CompilerA.HH"\n'
               b'#include "Templates"\n'
               b'#include "CExts"\n'
               b'#include "PrsLib"\n'
               b'#include "OptPass6"\n'
               b'#include "DBOptPass"\n'
               b'#include "BackLib"\n')
        result = guest_project.rewrite(raw)
        for path in (b'/DBPATCH/CEXTS.HC', b'/DBPATCH/PRSLIB.HC',
                     b'/DBPATCH/DBOPT.HC', b'/Compiler/Templates',
                     b'/Compiler/OptPass6', b'/Compiler/BackLib',
                     b'/Kernel/KernelA.HH'):
            self.assertIn(b'#include "' + path + b'"', result)
        self.assertEqual(result.count(b'#include'), raw.count(b'#include'))
        self.assertNotIn(b'#include "Templates"', result)
        self.assertEqual(guest_project.rewrite(raw), result)

    def test_real_package_contains_separate_guest_entrypoint(self):
        stage = Path(os.environ.get("DBOPT_STAGE", "__NO_STAGE__"))
        if not (stage / "DBOPT-STAGE.json").exists():
            self.skipTest("pinned stage not configured")
        sources = guest_redsea.get_files(stage)
        self.assertEqual(len(sources), 5)
        self.assertEqual(sources[-1][1], "GUEST.PRJ")
        expected = guest_project.rewrite((stage / "Compiler" / "Compiler.PRJ").read_bytes())
        self.assertEqual(sources[-1][2], expected)
        self.assertEqual(sources[-1][3],
                         __import__("hashlib").sha256(expected).hexdigest())

    def test_reject_missing_or_repeated_patch_anchor(self):
        raw = (b'#include "Templates"\n#include "CExts"\n'
               b'#include "PrsLib"\n#include "DBOptPass"\n')
        for absent in (b'CExts', b'PrsLib', b'DBOptPass'):
            with self.assertRaisesRegex(ValueError, 'anchor'):
                guest_project.rewrite(raw.replace(b'#include "' + absent + b'"\n', b''))
        with self.assertRaisesRegex(ValueError, 'anchor'):
            guest_project.rewrite(raw + b'#include "PrsLib"\n')

    def test_reject_unsafe_include_or_unknown_absolute_path(self):
        raw = (b'#include "CExts"\n#include "PrsLib"\n#include "DBOptPass"\n')
        for bad in (b'#include "../Bad"\n', b'#include "A\\\\Bad"\n',
                    b'#include "/Tmp/Injected"\n', b'#include "bad:thing"\n'):
            with self.assertRaises(ValueError):
                guest_project.rewrite(raw + bad)

    def test_real_stage_can_be_rewritten_without_mutation(self):
        repo = Path(__file__).resolve().parents[1]
        data = (repo / 'tools' / 'stage.py').read_text('utf-8')
        self.assertIn('"Compiler/Compiler.PRJ"', data)
        path = repo / 'native' / 'DBOptPass.HC'
        self.assertTrue(path.is_file())
        with tempfile.TemporaryDirectory() as folder:
            original = (b'#include "CExts"\n#include "PrsLib"\n'
                        b'#include "DBOptPass"\n#include "OptPass6"\n')
            source = Path(folder) / 'Compiler.PRJ'
            source.write_bytes(original)
            _ = guest_project.rewrite(source.read_bytes())
            self.assertEqual(source.read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
