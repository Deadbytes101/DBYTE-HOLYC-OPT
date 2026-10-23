"""R20 pure 64-bit register recopy: deterministic host-side semantics.

This is NOT a native TempleOS compiler result. The R19 staged compiler,
its pinned source hashes and all boot media stay unchanged.
"""
import os
import random
import subprocess
import unittest
from pathlib import Path

REG_COUNT = 16
FORBIDDEN = (4, 5)  # RSP, RBP
CANDIDATE = Path(__file__).resolve().parents[1] / "native" / "DBOptPassR20.HC"


def allowed(first, middle, last):
    if any(move["flags"] != 0x100 or move["opcode"] != "IC_MOV"
           or move["src_type"] != 0x40a or move["dst_type"] != 0x40a
           or move["arg2_mode"] or move["src_disp"] or move["dst_disp"]
           or move["ic_data"] for move in (first, middle, last)):
        return False
    if any(reg in FORBIDDEN or not 0 <= reg < REG_COUNT
           for move in (first, middle, last)
           for reg in (move["src"], move["dst"])):
        return False
    return (first["src"] != first["dst"]
            and middle["src"] != middle["dst"]
            and last["src"] == first["src"]
            and last["dst"] == first["dst"]
            and middle["dst"] not in (first["src"], first["dst"]))


def mov(src, dst, **overrides):
    x = dict(opcode="IC_MOV", flags=0x100,
             src_type=0x40a, dst_type=0x40a,
             arg2_mode=0, src_disp=0, dst_disp=0, ic_data=0,
             src=src, dst=dst)
    x.update(overrides)
    return x


def execute(state, moves):
    result = list(state)
    for op in moves:
        result[op["dst"]] = result[op["src"]]
    return result


class ThreeMoveTests(unittest.TestCase):
    def test_new_native_candidate_has_third_move_guard(self):
        self.assertTrue(CANDIDATE.is_file(), "R20 candidate absent")
        body = CANDIDATE.read_text(encoding="utf-8")
        self.assertIn("tmpi->next->next->ic_code==IC_MOV", body)
        self.assertIn("tmpi->arg1.reg==tmpi->next->next->arg1.reg", body)
        self.assertIn("tmpi->res.reg==tmpi->next->next->res.reg", body)
        self.assertIn("tmpi->next->res.reg!=tmpi->arg1.reg", body)
        self.assertIn("tmpi->next->res.reg!=tmpi->res.reg", body)
        self.assertIn("OptSetNOP1(tmpi->next->next);", body)
        self.assertIn("tmpi->ic_flags==ICF_USE_INT", body)
        self.assertIn("tmpi->next->ic_flags==ICF_USE_INT", body)
        self.assertIn("tmpi->next->next->ic_flags==ICF_USE_INT", body)
        self.assertIn("tmpi->res.reg!=REG_RSP", body)
        self.assertIn("tmpi->res.reg!=REG_RBP", body)

    def test_exhaustive_pure_reg_mov_triples(self):
        count = 0
        # All 65,536 four-register combinations, including aliasing cases.
        for src in range(REG_COUNT):
            for dst in range(REG_COUNT):
                for mid_src in range(REG_COUNT):
                    for mid_dst in range(REG_COUNT):
                        a, b, c = mov(src, dst), mov(mid_src, mid_dst), mov(src, dst)
                        if not allowed(a, b, c):
                            continue
                        state = [((v + 1) * 0x1111111111111111) & ((1 << 64) - 1)
                                 for v in range(REG_COUNT)]
                        self.assertEqual(execute(state, (a, b, c)),
                                         execute(state, (a, b)),
                                         (src, dst, mid_src, mid_dst))
                        count += 1
        self.assertGreater(count, 1000)

    def test_randomized_host_semantics(self):
        rng = random.Random(20261023)
        regs = [x for x in range(REG_COUNT) if x not in FORBIDDEN]
        for _ in range(10000):
            src, dst, mid_dst = rng.sample(regs, 3)
            mid_src = rng.choice([r for r in regs if r != mid_dst])
            a, b, c = mov(src, dst), mov(mid_src, mid_dst), mov(src, dst)
            self.assertTrue(allowed(a, b, c))
            state = [rng.getrandbits(64) for _ in range(REG_COUNT)]
            self.assertEqual(execute(state, (a, b, c)), execute(state, (a, b)))

    def test_disallow_source_or_destination_clobber_and_flags(self):
        a, b, c = mov(1, 2), mov(2, 3), mov(1, 2)
        self.assertTrue(allowed(a, b, c))
        for corrupt in (mov(9, 1), mov(9, 2)):
            self.assertFalse(allowed(a, corrupt, c))
        for change in (dict(flags=0x1100), dict(src_type=0x401),
                       dict(dst_type=0x408), dict(arg2_mode=1),
                       dict(src_disp=1), dict(dst_disp=2),
                       dict(ic_data=1), dict(src=16), dict(dst=16),
                       dict(dst=5), dict(src=4)):
            for pos in range(3):
                ops = [a, b, c]
                ops[pos] = {**ops[pos], **change}
                self.assertFalse(allowed(*ops), (pos, change))
        for invalid_last in (mov(1, 9), mov(9, 2), mov(2, 2)):
            self.assertFalse(allowed(a, b, invalid_last))

    def test_negative_clobber_cases_are_observably_wrong_to_optimize(self):
        state = [i * 0x102030405060708 for i in range(REG_COUNT)]
        first, third = mov(1, 2), mov(1, 2)
        for middle in (mov(3, 1), mov(3, 2)):
            self.assertFalse(allowed(first, middle, third))
            self.assertNotEqual(execute(state, (first, middle, third)),
                                execute(state, (first, middle)))

    def test_original_holyc_backend_emitter_has_identity_shortcut(self):
        upstream = os.environ.get("DBOPT_UPSTREAM")
        if not upstream:
            self.skipTest("pinned upstream Git checkout required")
        proc = subprocess.run(["git", "-C", upstream, "show",
                               "c26482bb6ad3f80106d28504ec5db3c6a360732c:"
                               "Compiler/BackLib.HC"],
                              capture_output=True, check=True)
        source = proc.stdout.decode("latin1")
        self.assertIn("if (r1==r2 && t2&MDF_REG)", source)
        self.assertIn("goto move_done;", source)
        self.assertIn("ICU16(tmpi,i.u8[2]<<8+0x8B);", source)
        self.assertLess(source.index("if (r1==r2 && t2&MDF_REG)"),
                        source.index("ICU16(tmpi,i.u8[2]<<8+0x8B);"))

    def test_r19_original_is_independently_preserved(self):
        original = CANDIDATE.with_name("DBOptPass.HC")
        self.assertTrue(original.is_file())
        self.assertNotIn(b"tmpi->next->next->ic_code==IC_MOV", original.read_bytes())


if __name__ == "__main__":
    unittest.main()
