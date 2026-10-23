"""Self-contained RedSea format checks for Linux CI, independent of local ISOs."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import guest_redsea as g
from tools import check_redsea as audit


def sha(data):
    return hashlib.sha256(data).hexdigest()


class SyntheticRedSeaTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.boot = self.dir / "baseline.iso"
        self.stage = self.dir / "stage"
        (self.stage / "Compiler").mkdir(parents=True)
        self.sources = {}
        for i, (src, name) in enumerate(g.FILES):
            data = bytes((0x41 + i,)) * (130 + 103*i)
            if src == "Compiler/Compiler.PRJ":
                data = (b'#include "Templates"\n#include "CExts"\n'
                        b'#include "PrsLib"\n#include "OptPass6"\n'
                        b'#include "DBOptPass"\n')
            (self.stage / src).write_bytes(data)
            self.sources[src] = sha(data)
        from tools.guest_project import rewrite
        guest = rewrite((self.stage / "Compiler/Compiler.PRJ").read_bytes())
        self.sources["generated:Compiler/Compiler.PRJ"] = sha(guest)
        self.guest_pin = patch.object(g, "GUEST_ENTRY_SHA256", sha(guest))
        self.guest_pin.start()
        self.addCleanup(self.guest_pin.stop)
        (self.stage / "DBOPT-STAGE.json").write_text(
            json.dumps({"upstream_commit": g.UPSTREAM, "sha256": self.sources}),
            encoding="utf-8")
        self.pin = patch.dict(g.SOURCE_SHA256, self.sources, clear=True)
        self.pin.start()
        self.addCleanup(self.pin.stop)
        total = 256
        image = bytearray(total * g.S)
        at = g.REDSEA_BOOT * g.S
        image[at+3] = 0x88
        image[at+510:at+512] = b"\x55\xaa"
        for offset, value in ((8, g.REDSEA_BOOT), (16, total-g.REDSEA_BOOT),
                              (24, g.ROOT), (32, 9)):
            g.put64(image, at+offset, value)
        # Fill 22 root slots, leaving two zero slots for a new directory.
        root = g.ROOT * g.S
        for i in range(22):
            record = g.directory_entry("." if i==0 else (".." if i==1 else "F"+str(i)),
                                       g.ROOT, 3*g.S if i==0 else 0, g.RS_DIRECTORY)
            image[root+i*64:root+(i+1)*64] = record
        for sector, kind in ((16,1),(18,2)):
            begin = sector * g.ISO
            image[begin] = kind
            image[begin+1:begin+6] = b"CD001"
            image[begin+80:begin+84] = (total//4).to_bytes(4, "little")
            image[begin+84:begin+88] = (total//4).to_bytes(4, "big")
        self.boot.write_bytes(image)
        self.original = bytes(image)
        self.old_hash = patch.object(g, "BASE_SHA256", sha(image))
        self.old_hash.start()
        self.addCleanup(self.old_hash.stop)

    def test_valid_redsea_layout_and_preservation(self):
        out = self.dir / "candidate.iso"
        receipt = g.build(self.boot, self.stage, out)
        data = out.read_bytes()
        self.assertGreater(len(data), len(self.original))
        self.assertEqual(data[:16*g.ISO], self.original[:16*g.ISO])
        self.assertEqual(data[g.ROOT*g.S:g.ROOT*g.S+22*64],
                         self.original[g.ROOT*g.S:g.ROOT*g.S+22*64])
        self.assertEqual(g.i64(data, 88*512+16), len(data)//512-88)
        self.assertEqual(len(receipt["files"]), 5)
        for row in receipt["files"]:
            off = row["absolute_sector"]*512
            self.assertEqual(sha(data[off:off+row["bytes"]]), self.sources[row["source"]])
        self.assertEqual(sha(data), receipt["output_sha256"])

    def test_byte_pin_rejection_without_partial_output(self):
        path = self.stage / g.FILES[0][0]
        path.write_bytes(path.read_bytes() + b"\xff")
        output = self.dir / "cannot-build.iso"
        with self.assertRaisesRegex(ValueError, "not byte-pinned"):
            g.build(self.boot, self.stage, output)
        self.assertFalse(output.exists())

    def test_drifted_boot_rejected_without_partial_output(self):
        contents = bytearray(self.boot.read_bytes())
        contents[9000] ^= 1
        self.boot.write_bytes(contents)
        output = self.dir / "cannot-build.iso"
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            g.build(self.boot, self.stage, output)
        self.assertFalse(output.exists())


    def verified_candidate(self):
        output = self.dir / "verified.iso"
        g.build(self.boot, self.stage, output)
        return output.read_bytes()

    def audit(self, content):
        expected = {name: (src, self.sources[src]) for src, name in g.FILES}
        expected["GUEST.PRJ"] = ("generated:Compiler/Compiler.PRJ",
                                 self.sources["generated:Compiler/Compiler.PRJ"])
        with patch.object(audit, "BASE_SHA256", sha(self.original)):
            with patch.dict(audit.EXPECTED, expected, clear=True):
                return audit.inspect(bytes(content), self.original)

    def test_independent_reader_accepts_complete_redsea_image(self):
        image = self.verified_candidate()
        result = self.audit(image)
        self.assertEqual(result["candidate_sha256"], sha(image))
        self.assertEqual({f["name"] for f in result["files"]},
                         {name for src, name in g.FILES} | {"GUEST.PRJ"})
        self.assertEqual(result["native_guest_read"], "UNVERIFIED")
        self.assertEqual(result["native_compiler"], "UNVERIFIED")

    def test_independent_reader_rejects_bitmap_bit_removed(self):
        image = bytearray(self.verified_candidate())
        new_dir = len(self.original)//512
        bit = new_dir - 97
        image[89*512 + bit//8] &= ~(1 << bit%8)
        with self.assertRaisesRegex(audit.AuditError, "bitmap allocation"):
            self.audit(image)

    def test_independent_reader_rejects_modified_original_boot_byte(self):
        image = bytearray(self.verified_candidate())
        image[12345] ^= 1
        with self.assertRaisesRegex(audit.AuditError, "modified original"):
            self.audit(image)

    def test_independent_reader_rejects_wrong_source_content(self):
        image = bytearray(self.verified_candidate())
        image[(len(self.original)//512+1)*512] ^= 1
        with self.assertRaisesRegex(audit.AuditError, "source SHA mismatch"):
            self.audit(image)

    def test_independent_reader_rejects_wrong_source_extent(self):
        image = bytearray(self.verified_candidate())
        parent = len(self.original)//512
        a = parent*512+2*64+40
        b = parent*512+3*64+40
        image[b:b+8] = image[a:a+8]
        with self.assertRaisesRegex(audit.AuditError, "extents overlap"):
            self.audit(image)

    def test_independent_reader_rejects_modified_descriptor_count(self):
        image = bytearray(self.verified_candidate())
        image[16*2048+80] ^= 1
        with self.assertRaisesRegex(audit.AuditError, "ISO descriptor"):
            self.audit(image)

    def test_independent_reader_rejects_directory_name_corruption(self):
        image = bytearray(self.verified_candidate())
        parent = len(self.original)//512
        image[parent*512+2*64+2] = ord("X")
        with self.assertRaisesRegex(audit.AuditError, "patch file inventory"):
            self.audit(image)

    def test_independent_reader_rejects_root_metadata_corruption(self):
        image = bytearray(self.verified_candidate())
        root_insert = 98*512+22*64
        image[root_insert] ^= 1
        with self.assertRaisesRegex(audit.AuditError, "missing/misplaced"):
            self.audit(image)


    def test_independent_reader_detects_original_bitmap_damage(self):
        image = bytearray(self.verified_candidate())
        allocated_root_bit = 98-97
        image[89*512] ^= 1 << allocated_root_bit
        with self.assertRaisesRegex(audit.AuditError, "bitmap"):
            self.audit(image)

    def test_independent_reader_detects_hidden_nonzero_unused_tail(self):
        image = bytearray(self.verified_candidate())
        image[-1] = 0x7f
        with self.assertRaisesRegex(audit.AuditError, "unallocated sector"):
            self.audit(image)

    def test_independent_reader_detects_file_padding_damage(self):
        image = bytearray(self.verified_candidate())
        parent_sector = len(self.original)//512
        first_file = parent_sector + 1
        first_file_bytes = len((self.stage / g.FILES[0][0]).read_bytes())
        image[first_file*512 + first_file_bytes] = 0xa5
        with self.assertRaisesRegex(audit.AuditError, "source padding"):
            self.audit(image)


if __name__ == "__main__":
    unittest.main()
