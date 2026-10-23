"""R20 independent host x86-64 machine-code witness.

Executes generated Win64 code; does not execute the TempleOS HolyC guest.
No required perf win threshold: timing is noisy and depends on the CPU.
"""
import json
import math
import platform
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Windows", "Win64 host witness only")
class RealX64WitnessTests(unittest.TestCase):
    def test_nasm_assembler_and_host_cpu_agree(self):
        nasm, gcc = shutil.which("nasm"), shutil.which("gcc")
        if not nasm or not gcc:
            self.skipTest("NASM and GCC are needed for Win64 witness")
        with tempfile.TemporaryDirectory(prefix="dbopt-r20-witness-") as tmp:
            root = Path(tmp)
            obj, exe = root / "test.obj", root / "test.exe"
            def command(*parts):
                result = subprocess.run(parts, cwd=ROOT, capture_output=True,
                                        text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stderr)
                return result.stdout
            command(nasm, "-f", "win64", str(ROOT/"tools"/"r20_win64_witness.asm"),
                    "-o", str(obj))
            command(gcc, "-O2", "-std=c11", str(ROOT/"tools"/"r20_win64_bench.c"),
                    str(obj), "-o", str(exe))
            report = json.loads(command(str(exe)))
            self.assertEqual(report["baseline_move_bytes"], 9)
            self.assertEqual(report["candidate_move_bytes"], 6)
            self.assertEqual(report["bytes_removed_per_iteration"], 3)
            self.assertEqual(report["iterations_per_sample"], 10000000)
            self.assertEqual(report["samples_per_variant"], 15)
            self.assertEqual(report["sink"], 0)
            self.assertFalse(report["native_holyc_compilation_observed"])
            for name in ("baseline_median_ms", "candidate_median_ms",
                         "speed_ratio_baseline_over_candidate"):
                self.assertTrue(math.isfinite(report[name]) and report[name] > 0,
                                (name, report[name]))


if __name__ == "__main__":
    unittest.main()
