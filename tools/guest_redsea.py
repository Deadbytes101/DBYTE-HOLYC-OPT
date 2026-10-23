"""Pinned RedSea source transport for a TempleOS 5.03 guest.

A new ISO contains the original untouched bootable RedSea filesystem content,
apart from its volume descriptors, RedSea metadata, one unused root slot and
new data sectors. Never edit the boot ISO or patch existing source files.
"""
import argparse
import hashlib
import json
from pathlib import Path
from tools.guest_iso import FILES, SOURCE_SHA256, UPSTREAM
from tools.guest_project import rewrite as render_guest_project

BASE_SHA256 = "5d0fc944e5d89c155c0fc17c148646715bc1db6fa5750c0b913772cfec19ba26"
S = 512
ISO = 2048
REDSEA_BOOT = 88
REDSEA_BITMAP = 89
REDSEA_DATA_AREA = 97
ROOT = 98
RS_DIRECTORY = 0x810
RS_FILE = 0x800
GUEST_DIR = "DBPATCH"
GUEST_ENTRY_SHA256 = "6885186129cd67705801f38aceb9cf93dc23a757c8d3cc0c06675e670d6e4231"
VOL_DESC = (16, 18)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def i64(data, offset):
    return int.from_bytes(data[offset:offset + 8], "little")


def put64(data, offset, value):
    data[offset:offset + 8] = value.to_bytes(8, "little")


def directory_entry(name, block, size, attr, timestamp=b"\x00" * 8):
    encoded = name.encode("ascii")
    if not encoded or len(encoded) > 37 or b"/" in encoded or b"\x00" in encoded:
        raise ValueError("unsafe RedSea filename")
    return (attr.to_bytes(2, "little") + encoded.ljust(38, b"\x00")
            + block.to_bytes(8, "little") + size.to_bytes(8, "little") + timestamp)


def get_files(stage):
    stage = Path(stage)
    if not (stage / "DBOPT-STAGE.json").is_file():
        raise ValueError("stage receipt missing")
    receipt = json.loads((stage / "DBOPT-STAGE.json").read_text("utf-8"))
    if receipt.get("upstream_commit") != UPSTREAM:
        raise ValueError("stage upstream mismatch")
    result = []
    for src, name in FILES:
        data = (stage / src).read_bytes()
        actual = digest(data)
        if not data or len(data) > 65536 or actual != SOURCE_SHA256[src] or receipt["sha256"][src] != actual:
            raise ValueError("staged source not byte-pinned: " + src)
        result.append((src, name, data, actual))
    # A separate executable entrypoint resolves original compressed dependencies
    # from /Compiler, and the three patched sources from /DBPATCH. Do not
    # replace the original staged Compiler.PRJ or any boot ISO source file.
    project_source = (stage / "Compiler" / "Compiler.PRJ").read_bytes()
    guest_entry = render_guest_project(project_source)
    entry_hash = digest(guest_entry)
    if entry_hash != GUEST_ENTRY_SHA256:
        raise ValueError("guest entrypoint source closure drift")
    result.append(("generated:Compiler/Compiler.PRJ", "GUEST.PRJ", guest_entry, entry_hash))
    return result


def build(boot_iso, stage, target):
    target = Path(target)
    manifest_path = target.with_suffix(".json")
    if target.exists() or manifest_path.exists():
        raise ValueError("refusing to overwrite artifact")
    original = Path(boot_iso).read_bytes()
    if digest(original) != BASE_SHA256 or len(original) % ISO:
        raise ValueError("boot ISO identity mismatch")
    files = get_files(stage)
    data = bytearray(original)
    boot = REDSEA_BOOT * S
    if data[boot + 3] != 0x88 or data[boot + 510:boot + 512] != b"\x55\xaa":
        raise ValueError("not an actual RedSea boot record")
    if i64(data, boot + 8) != REDSEA_BOOT or i64(data, boot + 32) != 9:
        raise ValueError("unrecognized RedSea layout")
    old_sectors = len(data) // S
    if i64(data, boot + 16) != old_sectors - REDSEA_BOOT or i64(data, boot + 24) != ROOT:
        raise ValueError("unexpected RedSea bounds or root")
    # Root directory has exactly one three-sector extent and a free slot.
    root_pos = ROOT * S
    if i64(data, root_pos + 48) != 3 * S:
        raise ValueError("root directory layout changed")
    root_slots = data[root_pos:root_pos + 3*S]
    existing = []
    empty = None
    for i in range(0, len(root_slots), 64):
        entry = root_slots[i:i + 64]
        name = entry[2:40].split(b"\x00", 1)[0]
        if not name and empty is None:
            empty = i
        elif name:
            existing.append(name)
    if GUEST_DIR.encode("ascii") in existing or empty is None or empty + 128 > len(root_slots):
        raise ValueError("guest directory already exists or no safe root slot")
    if any(root_slots[empty:]):
        raise ValueError("root tail must be wholly empty")
    # Append only to unused absolute sectors after immutable original image.
    next_sector = old_sectors
    parent_dir = next_sector
    next_sector += 1
    placements = []
    for src, name, content, hash_value in files:
        count = (len(content) + S - 1) // S
        placements.append((src, name, next_sector, count, content, hash_value))
        next_sector += count
    new_sectors = ((next_sector + 3) // 4) * 4
    max_bitmap_bits = 9 * S * 8
    if new_sectors - REDSEA_DATA_AREA > max_bitmap_bits:
        raise ValueError("RedSea bitmap capacity exceeded")
    data.extend(bytes((new_sectors - old_sectors) * S))
    root_timestamp = bytes(data[root_pos + 56:root_pos + 64])
    # New child directory, with actual RedSea fixed 64-byte records.
    entries = [directory_entry(".", parent_dir, S, RS_DIRECTORY, root_timestamp),
               directory_entry("..", ROOT, 0, RS_DIRECTORY, root_timestamp)]
    for src, name, sector, count, content, hash_value in placements:
        entries.append(directory_entry(name, sector, len(content), RS_FILE, root_timestamp))
        data[sector*S:sector*S + len(content)] = content
    parent_bytes = b"".join(entries).ljust(S, b"\x00")
    data[parent_dir*S:(parent_dir + 1)*S] = parent_bytes
    data[root_pos + empty:root_pos + empty + 64] = directory_entry(
        GUEST_DIR, parent_dir, S, RS_DIRECTORY, root_timestamp)
    # Bitmap bit n describes the absolute sector (data_area + n).
    for sector in range(old_sectors, next_sector):
        bit = sector - REDSEA_DATA_AREA
        pos = REDSEA_BITMAP*S + bit//8
        mask = 1 << (bit % 8)
        if data[pos] & mask:
            raise ValueError("refusing to claim an allocated bitmap sector")
        data[pos] |= mask
    put64(data, boot + 16, new_sectors - REDSEA_BOOT)
    for descriptor in VOL_DESC:
        loc = descriptor * ISO
        if data[loc] not in (1, 2) or data[loc + 1:loc + 6] != b"CD001":
            raise ValueError("unrecognized original ISO descriptor")
        if int.from_bytes(data[loc + 80:loc + 84], "little") != old_sectors // 4:
            raise ValueError("descriptor size mismatch")
        data[loc + 80:loc + 84] = (new_sectors//4).to_bytes(4, "little")
        data[loc + 84:loc + 88] = (new_sectors//4).to_bytes(4, "big")
    output = bytes(data)
    manifest = {
        "format": "TempleOS V5.03 RedSea native filesystem inside original bootable ISO",
        "upstream": UPSTREAM,
        "boot_iso_sha256": BASE_SHA256,
        "output_sha256": digest(output),
        "bytes": len(output),
        "guest_directory": "/" + GUEST_DIR,
        "root_sector": ROOT,
        "new_directory_sector": parent_dir,
        "files": [{"source": src, "guest_name": GUEST_DIR + "/" + name,
                   "absolute_sector": sector, "bytes": len(content), "sha256": h}
                  for src, name, sector, count, content, h in placements],
        "guest_native_read": "UNVERIFIED",
        "guest_native_compiler": "UNVERIFIED",
    }
    # Re-evaluate on serialized output before producing any artifact.
    for row in manifest["files"]:
        off = row["absolute_sector"]*S
        if digest(output[off:off + row["bytes"]]) != row["sha256"]:
            raise AssertionError("source extent parity failure")
    with target.open("xb") as file:
        file.write(output)
    with manifest_path.open("x", encoding="utf-8", newline="\n") as file:
        json.dump(manifest, file, sort_keys=True, indent=2)
        file.write("\n")
    return manifest


if __name__ == "__main__":
    arg = argparse.ArgumentParser()
    arg.add_argument("--boot", required=True)
    arg.add_argument("--stage", required=True)
    arg.add_argument("--out", required=True)
    a = arg.parse_args()
    print(json.dumps(build(a.boot, a.stage, a.out), sort_keys=True, indent=2))
