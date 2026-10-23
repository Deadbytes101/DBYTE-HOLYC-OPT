"""Self-contained RedSea format checks for Linux CI, independent of local ISOs."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools import guest_redsea as g


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
            (self.stage / src).write_bytes(data)
            self.sources[src] = sha(data)
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
        self.assertEqual(len(receipt["files"]), 4)
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


if __name__ == "__main__":
    unittest.main()
