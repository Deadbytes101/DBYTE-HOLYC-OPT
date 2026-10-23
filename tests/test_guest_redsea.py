"""Independent host checks for a genuine RedSea guest source disk."""
import hashlib
import json
import os
import re
import tempfile
import unittest
from pathlib import Path

from tools import guest_redsea, check_redsea

BOOT = Path(os.environ.get("DBOPT_BOOT_ISO", "__UNCONFIGURED_REDSEA_BOOT_ISO__"))
STAGE = Path(os.environ.get("DBOPT_STAGE", "__UNCONFIGURED_REDSEA_STAGE__"))


class RedSeaGuestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not BOOT.is_file() or not (STAGE / "DBOPT-STAGE.json").is_file():
            raise unittest.SkipTest("pinned boot ISO and staged tree not configured")
        cls.original = BOOT.read_bytes()
        cls.files = guest_redsea.get_files(STAGE)

    def make_iso(self, directory):
        dst = Path(directory) / "r9.iso"
        receipt = guest_redsea.build(BOOT, STAGE, dst)
        return dst, receipt

    def test_real_directory_and_five_exact_file_extents(self):
        with tempfile.TemporaryDirectory() as root:
            iso, receipt = self.make_iso(root)
            content = iso.read_bytes()
            boot = guest_redsea.REDSEA_BOOT * 512
            self.assertEqual(content[boot + 3], 0x88)
            self.assertEqual(content[boot + 510:boot + 512], b"\x55\xaa")
            self.assertEqual(guest_redsea.i64(content, boot + 16), len(content)//512 - 88)
            self.assertEqual(guest_redsea.i64(content, boot + 24), guest_redsea.ROOT)
            self.assertEqual(guest_redsea.i64(content, boot + 32), 9)
            original_root = self.original[98*512:101*512]
            new_root = content[98*512:101*512]
            self.assertEqual(new_root[:22*64], original_root[:22*64])
            entry = new_root[22*64:23*64]
            self.assertEqual(entry[2:40].split(b"\0")[0], b"DBPATCH")
            self.assertEqual(guest_redsea.i64(entry, 40), receipt["new_directory_sector"])
            self.assertEqual(guest_redsea.i64(entry, 48), 512)
            child = content[receipt["new_directory_sector"]*512: (receipt["new_directory_sector"]+1)*512]
            self.assertEqual(child[2:40].split(b"\0")[0], b".")
            self.assertEqual(guest_redsea.i64(child, 40), receipt["new_directory_sector"])
            self.assertEqual(child[66:104].split(b"\0")[0], b"..")
            self.assertEqual(guest_redsea.i64(child[64:128], 40), 98)
            for n, (source, filename, raw, expected) in enumerate(self.files):
                rec = child[(n+2)*64:(n+3)*64]
                self.assertEqual(rec[2:40].split(b"\0")[0].decode("ascii"), filename)
                self.assertEqual(guest_redsea.i64(rec, 48), len(raw))
                start = guest_redsea.i64(rec, 40)*512
                self.assertEqual(content[start:start+len(raw)], raw)
                self.assertEqual(hashlib.sha256(content[start:start+len(raw)]).hexdigest(), expected)
                for sector in range(guest_redsea.i64(rec, 40), guest_redsea.i64(rec, 40)+(len(raw)+511)//512):
                    bit = sector-guest_redsea.REDSEA_DATA_AREA
                    self.assertTrue(content[guest_redsea.REDSEA_BITMAP*512+bit//8] & (1 << bit%8))
            self.assertEqual(json.loads(iso.with_suffix(".json").read_text())["output_sha256"], guest_redsea.digest(content))

    def test_guest_compiler_include_closure_matches_original_redsea(self):
        root = check_redsea.entries(self.original, 98*512, 3*512)
        originals = {}
        for entry in root:
            if entry["name"] in ("Compiler", "Kernel"):
                sub = check_redsea.entries(
                    self.original, entry["block"]*512, entry["size"])
                originals[entry["name"]] = {item["name"] for item in sub}
        self.assertEqual(set(originals), {"Compiler", "Kernel"})
        delivered = {name: raw for src, name, raw, digest in self.files}
        self.assertIn("GUEST.PRJ", delivered)
        self.assertIn("COMPILER.PRJ", delivered)
        guest = delivered["GUEST.PRJ"]
        self.assertNotEqual(guest, delivered["COMPILER.PRJ"])
        include_paths = re.findall(rb'(?m)^#include "([^"]+)"$', guest)
        self.assertGreater(len(include_paths), 30)
        observed_patch = set()
        for include in include_paths:
            path = include.decode("ascii")
            if path.startswith("/DBPATCH/"):
                base = path.split("/")[-1]
                self.assertIn(base, delivered, path)
                observed_patch.add(base)
            else:
                scope, base = path.strip("/").split("/")
                self.assertIn(scope, originals, path)
                physical = base + (".Z" if "." in base else ".HC.Z")
                self.assertIn(physical, originals[scope], path)
        self.assertEqual(observed_patch,
                         {"PRSLIB.HC", "CEXTS.HC", "DBOPT.HC"})

    def test_historical_four_file_media_is_still_auditable_explicitly(self):
        legacy_path = Path(os.environ.get("DBOPT_LEGACY_REDSEA_ISO",
                                          "__LEGACY_ISO_NOT_CONFIGURED__"))
        if not legacy_path.is_file():
            self.skipTest("historical pinned media not configured")
        legacy = legacy_path.read_bytes()
        result = check_redsea.inspect(legacy, self.original,
                                      expected=check_redsea.EXPECTED_R12)
        self.assertEqual(len(result["files"]), 4)
        with self.assertRaisesRegex(check_redsea.AuditError,
                                    "unexpected patch directory count"):
            check_redsea.inspect(legacy, self.original)

    def test_original_boot_payload_mutations_are_bounded(self):
        with tempfile.TemporaryDirectory() as root:
            iso, _ = self.make_iso(root)
            changed = [i for i, (a,b) in enumerate(zip(self.original, iso.read_bytes())) if a!=b]
            allowed = set(range(88*512+16,88*512+24))
            allowed.update(range(89*512,98*512))
            allowed.update(range(100*512+6*64,100*512+7*64))
            for v in (16, 18):
                allowed.update(range(v*2048+80, v*2048+88))
            self.assertTrue(changed)
            self.assertTrue(set(changed) <= allowed)
            self.assertEqual(self.original[0:16*2048], iso.read_bytes()[0:16*2048])

    def test_reproducible_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            left, m1 = self.make_iso(a)
            right, m2 = self.make_iso(b)
            self.assertEqual(m1, m2)
            self.assertEqual(left.read_bytes(), right.read_bytes())
            with self.assertRaises(ValueError):
                guest_redsea.build(BOOT, STAGE, left)

    def test_reject_wrong_boot_and_tampered_stage(self):
        with tempfile.TemporaryDirectory() as root:
            boot = Path(root)/"wrong.iso"
            boot.write_bytes(self.original[:-2048])
            with self.assertRaises(ValueError):
                guest_redsea.build(boot, STAGE, Path(root)/"out.iso")
            with self.assertRaises(ValueError):
                guest_redsea.build(BOOT, boot.parent, Path(root)/"out.iso")
            stage = Path(root) / "stage"
            stage.mkdir()
            (stage / "DBOPT-STAGE.json").write_bytes((STAGE / "DBOPT-STAGE.json").read_bytes())
            for src, name, data, hash_value in self.files:
                if src.startswith("generated:"):
                    continue
                path = stage / src
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            corrupt = stage / self.files[0][0]
            corrupt.write_bytes(corrupt.read_bytes() + b"X")
            with self.assertRaisesRegex(ValueError, "not byte-pinned"):
                guest_redsea.build(BOOT, stage, Path(root)/"out.iso")


if __name__ == "__main__":
    unittest.main()
