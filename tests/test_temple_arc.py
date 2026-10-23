"""r19 native TempleOS compressed source parity tests, host only."""
import os
import unittest
from pathlib import Path

from tools.check_redsea import AuditError


class ExpandBufTests(unittest.TestCase):
    def test_plain_arc_payload(self):
        from tools.temple_arc import expand
        body = b"U0 Test() {}\n"
        arc = ((17 + len(body)).to_bytes(8, "little") +
               len(body).to_bytes(8, "little") + bytes([1]) + body)
        self.assertEqual(expand(arc), body)

    def test_reject_header_or_compression_tamper(self):
        from tools.temple_arc import expand
        body = b"abc"
        arc = ((17 + len(body)).to_bytes(8, "little") +
               len(body).to_bytes(8, "little") + bytes([1]) + body)
        for malformed in (
                arc[:8] + (0).to_bytes(8, "little") + arc[16:],
                (99).to_bytes(8, "little") + arc[8:],
                arc[:16] + bytes([99]) + arc[17:],
                arc[:-1],
                b"",
        ):
            with self.subTest(malformed=malformed[:20]):
                with self.assertRaises(AuditError):
                    expand(malformed)

    def test_literal_8bit_arc_and_truncated_code(self):
        from tools.temple_arc import expand
        body = bytes([255, 0])  # 9-bit first literal, little-endian bit order
        valid = (19).to_bytes(8, "little") + (1).to_bytes(8, "little")
        self.assertEqual(expand(valid + bytes([3]) + body), bytes([255]))
        with self.assertRaises(AuditError):
            expand(valid + bytes([3, 255]))

    def test_reject_expansion_limit(self):
        from tools.temple_arc import expand
        arc = (17).to_bytes(8, "little") + (2**24).to_bytes(8, "little") + b"\x01"
        with self.assertRaises(AuditError):
            expand(arc)

    def test_corrupt_real_seven_bit_first_code_rejected(self):
        from tools.temple_arc import expand
        from tools import check_redsea as audit
        original = os.environ.get("DBOPT_BOOT_ISO")
        if not original:
            self.skipTest("pinned original ISO required")
        iso = Path(original).read_bytes()
        root = {e["name"]: e for e in
                audit.entries(iso, audit.ROOT_BLOCK * audit.SECTOR,
                              3 * audit.SECTOR)}
        comp = root["Compiler"]
        names = {e["name"]: e for e in
                 audit.entries(iso, comp["block"] * audit.SECTOR, comp["size"])}
        node = names["PrsLib.HC.Z"]
        start = node["block"] * audit.SECTOR
        corrupt = bytearray(iso[start:start + node["size"]])
        self.assertEqual(corrupt[16], 2)
        corrupt[17] |= 0x80  # first code is no longer a 7-bit literal
        with self.assertRaises(AuditError):
            expand(bytes(corrupt))

    def test_real_compressed_pinned_source_bytes(self):
        from tools.temple_arc import verify_stock_imports
        original = os.environ.get("DBOPT_BOOT_ISO")
        candidate = os.environ.get("DBOPT_R15_ISO")
        upstream = os.environ.get("DBOPT_UPSTREAM")
        if not all((original, candidate, upstream)):
            self.skipTest("pinned original, patched ISO and Git upstream required")
        report = verify_stock_imports(Path(original), Path(candidate), Path(upstream))
        self.assertEqual(report["native_guest_execution"], "UNVERIFIED")
        self.assertEqual(report["guest_native_aot"], "UNVERIFIED")
        self.assertEqual(report["import_requests"], 33)
        self.assertEqual(report["source_match_failures"], 0)
        self.assertEqual(report["unique_sources_verified"], 33)
        self.assertEqual(report["byte_exact_sources"], 25)
        self.assertEqual(report["iso_format_marker_only_sources"], 8)
        self.assertEqual(report["format_marker_byte_differences"], 57)
        self.assertEqual(report["compressed_sources_verified"], 33)
        for record in report["sources"].values():
            self.assertIn(record["match_kind"],
                          ("BYTE_EXACT", "ISO_1F_GIT_SPACE_ONLY"))
            if record["match_kind"] == "BYTE_EXACT":
                self.assertEqual(record["iso_expanded_sha256"],
                                 record["pinned_git_sha256"])


if __name__ == "__main__":
    unittest.main()
