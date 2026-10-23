"""R6 read-only ISO9660/Joliet transport for the byte-pinned HolyC source overlay.
The TempleOS 5.03 ISO1FromName() reads UTF-16BE names in the supplementary tree.
Leave the historical ISO and all upstream and stage sources untouched.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

S = 2048
UPSTREAM = "c26482bb6ad3f80106d28504ec5db3c6a360732c"
# Independent expected hashes: changing the stage and its receipt together must fail.
SOURCE_SHA256 = {
    "Compiler/PrsLib.HC": "5539b9233b1120869fa18a1fa0dfab4e036e6b24d3dc69ca3a4ba37791cfa5e8",
    "Compiler/CExts.HC": "7169087e4064185e6ea703842a9a57003a0609973807aca191c574a265871e06",
    "Compiler/Compiler.PRJ": "c3339f08f451a2eef4d0afa32d05236b59b09f907ce70e44b649877f856ddb85",
    "Compiler/DBOptPass.HC": "4be1688a2a0a720fe8f168c6603ff57c8f195f7d404ce23a77baac3b6d964abd",
}
FILES = (
    ("Compiler/PrsLib.HC", "PRSLIB.HC"),
    ("Compiler/CExts.HC", "CEXTS.HC"),
    ("Compiler/Compiler.PRJ", "COMPILER.PRJ"),
    ("Compiler/DBOptPass.HC", "DBOPT.HC"),
)

def d16(n):
    return struct.pack("<H", n) + struct.pack(">H", n)

def d32(n):
    return struct.pack("<I", n) + struct.pack(">I", n)

def record(name, extent, size, directory=False):
    if not 0 < len(name) <= 128:
        raise ValueError("invalid ISO filename length")
    length = 33 + len(name) + (not len(name) % 2)
    r = bytearray(length)
    r[0] = length
    r[2:10] = d32(extent)
    r[10:18] = d32(size)
    r[18:25] = bytes((126, 10, 22, 0, 0, 0, 0))
    r[25] = 2 if directory else 0
    r[28:32] = d16(1)
    r[32] = len(name)
    r[33:33 + len(name)] = name
    return bytes(r)

def path_table(extent, big=False):
    return bytes((1, 0)) + struct.pack(">I" if big else "<I", extent) + (
        struct.pack(">H" if big else "<H", 1)) + bytes((0, 0))

def build(stage, output):
    stage, output = Path(stage), Path(output)
    if output.exists() or output.with_suffix(".json").exists():
        raise ValueError("output or manifest exists")
    receipt = json.loads((stage / "DBOPT-STAGE.json").read_text("utf-8"))
    if receipt.get("upstream_commit") != UPSTREAM:
        raise ValueError("wrong pinned upstream")
    entries = []
    cursor = 25
    for source, short in FILES:
        content = (stage / source).read_bytes()
        digest = hashlib.sha256(content).hexdigest()
        if (not content or len(content) > 65536 or
                receipt["sha256"][source] != digest or
                SOURCE_SHA256[source] != digest):
            raise ValueError("source checksum/size failure: " + source)
        entries.append((source, short, cursor, content, digest))
        cursor += (len(content) + S - 1) // S
    blocks = max(64, cursor + 1)
    image = bytearray(blocks * S)
    for source, short, extent, content, digest in entries:
        pos = extent * S
        image[pos:pos + len(content)] = content

    # Primary ASCII directory, for standard ISO9660 host readers.
    primary = [record(b"\x00", 23, S, True), record(b"\x01", 23, S, True)]
    # Supplementary UCS-2BE directory, for HolyC ISO1FromName().
    supplementary = [record(b"\x00", 24, S, True), record(b"\x01", 24, S, True)]
    for source, short, extent, content, digest in entries:
        primary.append(record((short + ";1").encode("ascii"), extent, len(content)))
        supplementary.append(record((short + ";1").encode("utf-16-be"), extent, len(content)))
    primary_data, secondary_data = b"".join(primary), b"".join(supplementary)
    if len(primary_data) > S or len(secondary_data) > S:
        raise ValueError("directory overflow")
    image[23*S:23*S + len(primary_data)] = primary_data
    image[24*S:24*S + len(secondary_data)] = secondary_data

    # Independent root paths for primary and supplementary trees.
    for sector, root, big in ((19, 23, False), (20, 23, True),
                              (21, 24, False), (22, 24, True)):
        table = path_table(root, big)
        image[sector*S:sector*S + len(table)] = table
    for sector, typ, root, pt_le, pt_be in (
        (16, 1, 23, 19, 20), (17, 2, 24, 21, 22), (18, 255, 0, 0, 0)
    ):
        base = sector*S
        image[base] = typ
        image[base+1:base+6] = b"CD001"
        image[base+6] = 1
        if typ == 255:
            continue
        h = memoryview(image)[base:base+S]
        h[8:40] = b"DEADBYTE".ljust(32, b" ")
        h[40:72] = b"DBOPT_R6".ljust(32, b" ")
        h[80:88] = d32(blocks)
        h[120:124] = d16(1)
        h[124:128] = d16(1)
        h[128:132] = d16(S)
        h[132:140] = d32(10)
        h[140:144] = struct.pack("<I", pt_le)
        h[148:152] = struct.pack(">I", pt_be)
        h[156:190] = record(b"\x00", root, S, True)
        h[318:446] = b"DBYTE TEST TRANSPORT".ljust(128, b" ")
        h[881] = 1
        if typ == 2:
            h[88:91] = b"%/@"  # Joliet level 1, UCS-2 big-endian names.
    manifest = {
        "format": "ISO9660 + supplementary UCS2BE",
        "upstream": UPSTREAM,
        "sha256": hashlib.sha256(image).hexdigest(),
        "bytes": len(image),
        "primary_root_sector": 23,
        "supplementary_root_sector": 24,
        "files": [
            {"source": source, "guest_name": short, "sector": extent,
             "bytes": len(content), "sha256": digest}
            for source, short, extent, content, digest in entries
        ],
        "guest_native_compile": "UNVERIFIED",
        "guest_read": "UNVERIFIED",
    }
    # Extent-level identity check over the completed image.
    for entry in manifest["files"]:
        start = entry["sector"]*S
        if hashlib.sha256(image[start:start + entry["bytes"]]).hexdigest() != entry["sha256"]:
            raise AssertionError("extent digest mismatch")
    with output.open("xb") as f:
        f.write(image)
    with output.with_suffix(".json").open("x", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    return manifest

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--stage", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    a = p.parse_args()
    print(json.dumps(build(a.stage, a.out), sort_keys=True))
