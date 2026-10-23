"""R14 no-op native MOV characterization (host only, guest AOT not proven)."""
import random
import re
import unittest
from pathlib import Path


PASS = Path(__file__).resolve().parents[1] / "native" / "DBOptPass.HC"
REG_RSP, REG_RBP, REG_COUNT = 4, 5, 16
PURE_64_REG = 0x400 + 10
USE_INT = 0x100


def allowed_identity_mov(op):
    return (op["opcode"] == "IC_MOV"
            and op["flags"] == USE_INT
            and op["arg1_type"] == PURE_64_REG
            and op["res_type"] == PURE_64_REG
            and op["arg2_mode"] == 0
            and op["arg1_disp"] == op["res_disp"] == 0
            and op["ic_data"] == 0
            and 0 <= op["src"] < REG_COUNT
            and 0 <= op["dst"] < REG_COUNT
            and op["src"] == op["dst"]
            and op["dst"] not in (REG_RSP, REG_RBP))


def op(src, dst, **overrides):
    d = dict(opcode="IC_MOV", flags=USE_INT, arg1_type=PURE_64_REG,
             res_type=PURE_64_REG, arg2_mode=0, arg1_disp=0,
             res_disp=0, ic_data=0, src=src, dst=dst)
    d.update(overrides)
    return d


def execute(state, instr):
    result = state[:]
    if instr["opcode"] != "IC_MOV":
        raise ValueError("oracle only models integer MOV")
    result[instr["dst"]] = result[instr["src"]]
    return result


class NativeSelfMoveTests(unittest.TestCase):
    def test_holyc_source_has_bounded_identity_rewrite(self):
        source = PASS.read_text(encoding="utf-8")
        # Two distinct rewrite branches: self-MOV and adjacent dead destination
        self.assertIn("tmpi->arg1.reg==tmpi->res.reg", source)
        for guard in ("tmpi->ic_code==IC_MOV", "tmpi->ic_flags==ICF_USE_INT",
                      "tmpi->arg1.type==MDF_REG+RT_I64",
                      "tmpi->res.type==MDF_REG+RT_I64",
                      "!tmpi->arg2.type.mode", "!tmpi->arg1.disp",
                      "!tmpi->res.disp", "!tmpi->ic_data",
                      "tmpi->arg1.reg<REG_REGS_NUM",
                      "tmpi->res.reg<REG_REGS_NUM",
                      "tmpi->res.reg!=REG_RSP", "tmpi->res.reg!=REG_RBP"):
            self.assertIn(guard, source)
        self.assertGreaterEqual(source.count("OptSetNOP1(tmpi);"), 2)
        self.assertRegex(source, r"(?s)tmpi->arg1.reg==tmpi->res.reg\s*\)\s*OptSetNOP1\(tmpi\);")

    def test_all_safe_reg_self_moves_preserve_exact_register_state(self):
        rng = random.Random(20261023)
        for src in range(REG_COUNT):
            candidate = op(src, src)
            if src in (REG_RSP, REG_RBP):
                self.assertFalse(allowed_identity_mov(candidate))
                continue
            self.assertTrue(allowed_identity_mov(candidate))
            for _ in range(30):
                state = [rng.getrandbits(64) for _ in range(REG_COUNT)]
                self.assertEqual(execute(state, candidate), state)

    def test_no_implicit_side_effects_or_operands_allowed(self):
        candidate = op(7, 7)
        modifications = [
            {"flags": USE_INT | 1}, {"flags": 0},
            {"opcode": "IC_ASSIGN"}, {"arg1_type": PURE_64_REG + 1},
            {"res_type": PURE_64_REG + 1}, {"arg2_mode": 1},
            {"arg1_disp": 1}, {"res_disp": 4}, {"ic_data": 1},
            {"src": -1}, {"src": REG_COUNT}, {"dst": -1}, {"dst": REG_COUNT},
            {"src": 6}, {"dst": 6}, {"dst": REG_RSP, "src": REG_RSP},
            {"dst": REG_RBP, "src": REG_RBP},
        ]
        for change in modifications:
            with self.subTest(change=change):
                self.assertFalse(allowed_identity_mov({**candidate, **change}))

    def test_near_miss_moves_must_remain(self):
        rng = random.Random(17)
        for dest in range(REG_COUNT):
            for src in range(REG_COUNT):
                candidate = op(src, dest)
                if src != dest or dest in (REG_RSP, REG_RBP):
                    self.assertFalse(allowed_identity_mov(candidate))
                if src != dest:
                    state = [rng.getrandbits(64) for _ in range(REG_COUNT)]
                    if state[src] != state[dest]:
                        self.assertNotEqual(execute(state, candidate), state)


if __name__ == "__main__":
    unittest.main()
