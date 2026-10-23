"""R11 first IR rewrite: adjacent dead destination-register writes.

These are host-side instruction semantics and source-contract tests only.
They cannot establish that the native HolyC compiler builds or executes.
"""
import hashlib
import random
import unittest
from pathlib import Path

from tools import check_redsea, guest_iso


PASS = Path(__file__).resolve().parents[1] / "native" / "DBOptPass.HC"
REG64 = 0x400 + 10  # pinned Kernel/KernelA.HH declares RT_I64=10
USE_INT = 0x100
REG_RSP = 4
REG_RBP = 5
REG_NUM = 16


def allowed(first, second):
    return (first["opcode"] == second["opcode"] == "IC_MOV"
            and first["flags"] == second["flags"] == USE_INT
            and first["src_type"] == first["dst_type"] == REG64
            and second["src_type"] == second["dst_type"] == REG64
            and first["src_disp"] == first["dst_disp"] == 0
            and second["src_disp"] == second["dst_disp"] == 0
            and first["arg2_mode"] == second["arg2_mode"] == 0
            and first["data"] == second["data"] == 0
            and 0 <= first["src"] < REG_NUM
            and 0 <= second["src"] < REG_NUM
            and 0 <= first["dst"] < REG_NUM
            and first["dst"] not in (REG_RSP, REG_RBP)
            and first["src"] != first["dst"]
            and first["dst"] == second["dst"]
            and second["src"] != second["dst"])


def mov(src, dst, **overrides):
    row = {"opcode": "IC_MOV", "flags": USE_INT,
           "src_type": REG64, "dst_type": REG64,
           "src": src, "dst": dst, "src_disp": 0, "dst_disp": 0,
           "arg2_mode": 0, "data": 0}
    row.update(overrides)
    return row


def execute(state, ops):
    state = list(state)
    for op in ops:
        if op["opcode"] != "IC_MOV":
            raise ValueError("unsupported instruction in oracle")
        state[op["dst"]] = state[op["src"]]
    return state


class DeadWriteTests(unittest.TestCase):
    def test_required_holyc_rewrite_and_all_guard_fields(self):
        source = PASS.read_text(encoding="utf-8")
        self.assertIn("OptSetNOP1(tmpi);", source)
        self.assertIn("tmpi->next->ic_code==IC_MOV", source)
        self.assertIn("tmpi->ic_flags==ICF_USE_INT", source)
        self.assertIn("tmpi->next->ic_flags==ICF_USE_INT", source)
        self.assertIn("tmpi->res.type==MDF_REG+RT_I64", source)
        self.assertIn("tmpi->arg1.type==MDF_REG+RT_I64", source)
        self.assertIn("tmpi->next->res.type==MDF_REG+RT_I64", source)
        self.assertIn("tmpi->next->arg1.type==MDF_REG+RT_I64", source)
        self.assertIn("tmpi->res.reg==tmpi->next->res.reg", source)
        self.assertIn("tmpi->res.reg!=REG_RSP", source)
        self.assertIn("tmpi->res.reg!=REG_RBP", source)
        self.assertIn("tmpi->arg1.reg<REG_REGS_NUM", source)
        self.assertIn("tmpi->next->arg1.reg<REG_REGS_NUM", source)
        self.assertIn("tmpi->arg1.reg!=tmpi->res.reg", source)
        self.assertNotIn("tmpi->arg1.reg!=tmpi->next->arg1.reg", source)
        self.assertIn("tmpi->next->arg1.reg!=tmpi->next->res.reg", source)
        for frag in ("!tmpi->arg1.disp", "!tmpi->res.disp",
                     "!tmpi->next->arg1.disp", "!tmpi->next->res.disp",
                     "!tmpi->arg2.type.mode", "!tmpi->next->arg2.type.mode",
                     "!tmpi->ic_data", "!tmpi->next->ic_data"):
            self.assertIn(frag, source)

    def test_instruction_semantics_randomized(self):
        rng = random.Random(11023)
        for _ in range(10000):
            dst = rng.choice([v for v in range(16) if v not in (REG_RSP, REG_RBP)])
            first_src = rng.choice([v for v in range(16) if v != dst])
            second_src = rng.choice([v for v in range(16) if v not in (dst, first_src)])
            first, second = mov(first_src, dst), mov(second_src, dst)
            self.assertTrue(allowed(first, second))
            state = [rng.getrandbits(64) for _ in range(16)]
            self.assertEqual(execute(state, [first, second]),
                             execute(state, [second]))

    def test_identical_source_mov_is_dead(self):
        # mov R1,R0; mov R1,R0 has the same final machine state
        # as the latter mov alone. The R11 guard missed this safe pair.
        for dst in range(REG_NUM):
            if dst in (REG_RSP, REG_RBP):
                continue
            for src in range(REG_NUM):
                if src == dst:
                    continue
                first, second = mov(src, dst), mov(src, dst)
                self.assertTrue(allowed(first, second), (src, dst))
                state = [(r * 0x1020304050607) & ((1 << 64) - 1)
                         for r in range(REG_NUM)]
                self.assertEqual(execute(state, [first, second]),
                                 execute(state, [second]))

    def test_native_source_byte_pins_are_canonical(self):
        canonical = PASS.read_bytes().replace(b"\r\n", b"\n")
        self.assertNotIn(b"\r", canonical)
        digest = hashlib.sha256(canonical).hexdigest()
        self.assertEqual(guest_iso.SOURCE_SHA256["Compiler/DBOptPass.HC"], digest)
        self.assertEqual(check_redsea.EXPECTED["DBOPT.HC"][1], digest)

    def test_every_safe_pair_has_identical_register_state(self):
        # Full 16-register product, not only random examples.
        for dst in range(REG_NUM):
            if dst in (REG_RSP, REG_RBP):
                continue
            for first_src in range(REG_NUM):
                if first_src == dst:
                    continue
                for second_src in range(REG_NUM):
                    if second_src == dst:
                        continue
                    first, second = mov(first_src, dst), mov(second_src, dst)
                    self.assertTrue(allowed(first, second))
                    state = [((reg + 1) * 0x1111111111111111) & ((1 << 64) - 1)
                             for reg in range(REG_NUM)]
                    self.assertEqual(execute(state, [first, second]),
                                     execute(state, [second]))

    def test_unsafe_two_moves_are_not_rewritten(self):
        first, second = mov(1, 0), mov(2, 0)
        examples = [
            ({"flags": USE_INT | 0x2000}, {}),
            ({}, {"flags": USE_INT | 0x4000}),
            ({"src_type": 0x400 + 4}, {}),
            ({}, {"dst_type": 0x400 + 4}),
            ({"src_disp": 8}, {}),
            ({}, {"dst_disp": 8}),
            ({"arg2_mode": 4}, {}),
            ({}, {"arg2_mode": 4}),
            ({"data": 1}, {}),
            ({}, {"data": 1}),
            ({}, {"src": 0}),  # second reads the old first destination
            ({}, {"dst": 1}),
            ({"opcode": "IC_ADD_CONST"}, {}),
            ({}, {"dst": REG_RSP, "src": 2}),
            ({}, {"dst": REG_RBP, "src": 2}),
            ({"src": REG_NUM}, {}),
            ({}, {"src": REG_NUM}),
        ]
        for a, b in examples:
            self.assertFalse(allowed({**first, **a}, {**second, **b}), (a, b))
        for special in (REG_RSP, REG_RBP):
            self.assertFalse(allowed(mov(1, special), mov(2, special)))

    def test_oracle_exposes_clobber_hazard(self):
        state = list(range(16))
        first, second = mov(4, 0), mov(0, 0)
        self.assertFalse(allowed(first, second))
        self.assertNotEqual(execute(state, [first, second]),
                            execute(state, [second]))


if __name__ == "__main__":
    unittest.main()
