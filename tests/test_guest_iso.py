"""check the native guest transfer image by inspecting raw sectors, not PASS labels."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import guest_iso

def sha(buf):
    return hashlib.sha256(buf).hexdigest()

def decode_entries(blob, root):
    buf = blob[root*guest_iso.S:(root+1)*guest_iso.S]
    pos, rows = 0, []
    while pos < len(buf) and buf[pos]:
        length = buf[pos]
        if length < 34 or pos+length > len(buf):
            raise ValueError("bad entry length")
        ent = buf[pos:pos+length]
        size = ent[32]
        rows.append((ent[33:33+size],int.from_bytes(ent[2:6],"little"),
                     int.from_bytes(ent[10:14],"little")))
        pos += length
    return rows

class GuestIsoTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.stage = self.root/"stage"
        (self.stage/"Compiler").mkdir(parents=True)
        self.data = {}
        for idx,(path,name) in enumerate(guest_iso.FILES):
            data = bytes([0x40+idx])*(((idx+1)*511)+idx)
            (self.stage/path).write_bytes(data)
            self.data[path] = data
        self.receipt = {"upstream_commit": guest_iso.UPSTREAM,
                        "sha256": {path:sha(data) for path,data in self.data.items()}}
        (self.stage/"DBOPT-STAGE.json").write_text(json.dumps(self.receipt),encoding="utf-8")
        self.pins = patch.dict(guest_iso.SOURCE_SHA256,self.receipt["sha256"],clear=True)
        self.pins.start()
        self.addCleanup(self.pins.stop)

    def make(self, name="transfer.iso"):
        dest = self.root/name
        manifest = guest_iso.build(self.stage,dest)
        return dest,manifest,dest.read_bytes()

    def test_primary_and_joliet_names_and_extents(self):
        dest,receipt,buf = self.make()
        self.assertEqual(sha(buf),receipt["sha256"])
        p = buf[16*2048:17*2048]
        s = buf[17*2048:18*2048]
        t = buf[18*2048:19*2048]
        self.assertEqual((p[0],s[0],t[0]),(1,2,255))
        self.assertEqual(p[1:6],b"CD001")
        self.assertEqual(s[88:91],b"%/@")
        self.assertEqual(int.from_bytes(p[158:162],"little"),23)
        self.assertEqual(int.from_bytes(s[158:162],"little"),24)
        primary = decode_entries(buf,23)[2:]
        supplementary = decode_entries(buf,24)[2:]
        self.assertEqual(len(primary),4)
        self.assertEqual(len(supplementary),4)
        for idx,((src,short),a,b) in enumerate(zip(guest_iso.FILES,primary,supplementary)):
            self.assertEqual(a[0],(short+";1").encode("ascii"))
            self.assertEqual(b[0],(short+";1").encode("utf-16-be"))
            self.assertEqual(a[1:],b[1:])
            sector,amount = b[1:]
            self.assertGreaterEqual(sector,25)
            self.assertEqual(amount,len(self.data[src]))
            self.assertEqual(buf[sector*2048:sector*2048+amount],self.data[src])
            self.assertEqual(receipt["files"][idx]["sha256"],sha(self.data[src]))

    def test_reproducibility(self):
        _,first,a = self.make("first.iso")
        _,second,b = self.make("second.iso")
        self.assertEqual(a,b)
        self.assertEqual(first["sha256"],second["sha256"])

    def test_fail_closed_on_bad_receipt(self):
        self.receipt["sha256"][guest_iso.FILES[0][0]] = "0"*64
        (self.stage/"DBOPT-STAGE.json").write_text(json.dumps(self.receipt),encoding="utf-8")
        with self.assertRaisesRegex(ValueError,"checksum/size"):
            guest_iso.build(self.stage,self.root/"fail.iso")
        self.assertFalse((self.root/"fail.iso").exists())

    def test_fail_closed_when_source_and_receipt_both_changed(self):
        source = guest_iso.FILES[0][0]
        modified = self.data[source]+b"changed"
        (self.stage/source).write_bytes(modified)
        self.receipt["sha256"][source] = sha(modified)
        (self.stage/"DBOPT-STAGE.json").write_text(json.dumps(self.receipt),encoding="utf-8")
        with self.assertRaisesRegex(ValueError,"checksum/size"):
            guest_iso.build(self.stage,self.root/"fail.iso")
        self.assertFalse((self.root/"fail.iso").exists())

    def test_refuse_overwrite_image_or_receipt(self):
        image = self.root/"known.iso"
        image.write_bytes(b"known-good")
        with self.assertRaisesRegex(ValueError,"exists"):
            guest_iso.build(self.stage,image)
        self.assertEqual(image.read_bytes(),b"known-good")
        other = self.root/"receipt.iso"
        other.with_suffix(".json").write_text("known-good",encoding="utf-8")
        with self.assertRaisesRegex(ValueError,"exists"):
            guest_iso.build(self.stage,other)
        self.assertFalse(other.exists())

    def test_malformed_input_missing_source_is_rejected(self):
        (self.stage/guest_iso.FILES[0][0]).unlink()
        with self.assertRaises(FileNotFoundError):
            guest_iso.build(self.stage,self.root/"fail.iso")
        self.assertFalse((self.root/"fail.iso").exists())

    def test_external_readback_if_7z_available(self):
        if not shutil.which("7z"):
            self.skipTest("7z not installed")
        image,_,_ = self.make()
        out = self.root/"out"
        p = subprocess.run(["7z","x","-y","-o"+str(out),str(image)],
                           capture_output=True,text=True,check=False)
        self.assertEqual(p.returncode,0,p.stdout[-1000:]+p.stderr[-1000:])
        for src,name in guest_iso.FILES:
            self.assertEqual((out/name).read_bytes(),self.data[src])

if __name__ == "__main__":
    unittest.main(verbosity=2)
