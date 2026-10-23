"""Read-only independent audit of a pinned TempleOS RedSea guest ISO.

No imports from the ISO builder. Checks structural traversal, allocated
sectors, source bytes and exact change surface against an original image.
"""
import argparse
import hashlib
import json
from pathlib import Path

SECTOR = 512
ISO_SECTOR = 2048
BASE_SHA256 = "5d0fc944e5d89c155c0fc17c148646715bc1db6fa5750c0b913772cfec19ba26"
UPSTREAM = "c26482bb6ad3f80106d28504ec5db3c6a360732c"
EXPECTED = {
    "PRSLIB.HC": ("Compiler/PrsLib.HC", "5539b9233b1120869fa18a1fa0dfab4e036e6b24d3dc69ca3a4ba37791cfa5e8"),
    "CEXTS.HC": ("Compiler/CExts.HC", "7169087e4064185e6ea703842a9a57003a0609973807aca191c574a265871e06"),
    "COMPILER.PRJ": ("Compiler/Compiler.PRJ", "c3339f08f451a2eef4d0afa32d05236b59b09f907ce70e44b649877f856ddb85"),
    "DBOPT.HC": ("Compiler/DBOptPass.HC", "ba1d234e27f9e60242511d20bcfbbd88643d56fbe4d8c2b4ad3c7de52261293a"),
}
DIRECTORY_ATTR = 0x810
FILE_ATTR = 0x800
META_BOOT = 88
META_BITMAP = 89
ROOT_BLOCK = 98
NEW_FOLDER = "DBPATCH"


class AuditError(ValueError):
    pass


def require(condition, reason):
    if not condition:
        raise AuditError(reason)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def u16(data, p):
    return int.from_bytes(data[p:p + 2], "little")


def u32(data, p):
    return int.from_bytes(data[p:p + 4], "little")


def u64(data, p):
    return int.from_bytes(data[p:p + 8], "little")


def entries(data, start, size):
    require(size > 0 and size % SECTOR == 0 and start >= 0
            and start + size <= len(data), "directory out of bounds")
    names = []
    seen_empty = False
    for pos in range(start, start + size, 64):
        buf = data[pos:pos + 64]
        name = buf[2:40].split(b"\0", 1)[0]
        if not name:
            seen_empty = True
            require(not any(buf), "nonzero trailing directory slot")
            continue
        require(not seen_empty, "nonempty entry after terminator")
        require(b"\0" in buf[2:40], "unterminated filename")
        require(all(32 <= byte <= 126 for byte in name), "non-ASCII filename")
        key = name.decode("ascii")
        require(key not in [e["name"] for e in names], "duplicate filename")
        names.append({"name": key, "attr": u16(buf, 0),
                      "block": u64(buf, 40), "size": u64(buf, 48),
                      "raw": bytes(buf)})
    return names


def inspect(candidate, original, expected=EXPECTED):
    require(isinstance(candidate, bytes) and isinstance(original, bytes), "require binary images")
    require(sha(original) == BASE_SHA256, "original boot ISO hash differs")
    require(len(original) % ISO_SECTOR == 0 and len(candidate) % ISO_SECTOR == 0
            and len(candidate) > len(original), "candidate size or alignment invalid")
    old_n, new_n = len(original)//SECTOR, len(candidate)//SECTOR
    boot_offset = META_BOOT*SECTOR
    for blob, count in ((original, old_n), (candidate, new_n)):
        require(blob[boot_offset+3] == 0x88 and blob[boot_offset+510:boot_offset+512] == b"\x55\xaa", "RedSea signature invalid")
        require(u64(blob, boot_offset+8) == META_BOOT
                and u64(blob, boot_offset+16) == count-META_BOOT
                and u64(blob, boot_offset+24) == ROOT_BLOCK
                and u64(blob, boot_offset+32) == 9, "RedSea layout/count mismatch")
        for sector, kind in ((16, 1), (18, 2)):
            pos = sector*ISO_SECTOR
            require(blob[pos] == kind and blob[pos+1:pos+6] == b"CD001"
                    and u32(blob, pos+80) == count//4
                    and int.from_bytes(blob[pos+84:pos+88], "big") == count//4,
                    "ISO descriptor invalid")
    start = ROOT_BLOCK*SECTOR
    orig_root = entries(original, start, 3*SECTOR)
    root = entries(candidate, start, 3*SECTOR)
    require(len(root) == len(orig_root)+1 and root[:-1] == orig_root, "original root directory changed")
    require(root[0]["name"] == "." and root[0]["attr"] == DIRECTORY_ATTR
            and root[0]["block"] == ROOT_BLOCK and root[0]["size"] == 3*SECTOR,
            "root self entry invalid")
    require(root[1]["name"] == ".." and root[1]["block"] == ROOT_BLOCK,
            "root parent entry invalid")
    folder = root[-1]
    require(folder["name"] == NEW_FOLDER and folder["attr"] == DIRECTORY_ATTR
            and folder["size"] == SECTOR and folder["block"] >= old_n,
            "missing/misplaced DBPATCH RedSea directory")
    folder_off = folder["block"]*SECTOR
    children = entries(candidate, folder_off, folder["size"])
    require(len(children) == len(expected)+2, "unexpected patch directory count")
    require(children[0]["name"] == "." and children[0]["attr"] == DIRECTORY_ATTR
            and children[0]["block"] == folder["block"] and children[0]["size"] == SECTOR
            and children[1]["name"] == ".." and children[1]["attr"] == DIRECTORY_ATTR
            and children[1]["block"] == ROOT_BLOCK, "child dot entries invalid")
    require({x["name"] for x in children[2:]} == set(expected), "patch file inventory mismatch")

    # No future sector is shared, gaps are unallocated and all payloads are byte pinned.
    allocations = {folder["block"]}
    verified = []
    for child in children[2:]:
        name = child["name"]
        source, expected_hash = expected[name]
        size = child["size"]
        start_block = child["block"]
        require(child["attr"] == FILE_ATTR and 0 < size <= 65536
                and start_block >= old_n, "unsafe source file extent or attributes")
        blocks = (size + SECTOR - 1)//SECTOR
        require(start_block + blocks <= new_n, "source extent exceeds image")
        blocks_used = set(range(start_block, start_block+blocks))
        require(not allocations.intersection(blocks_used), "source extents overlap")
        allocations.update(blocks_used)
        data = candidate[start_block*SECTOR:start_block*SECTOR+size]
        require(sha(data) == expected_hash, "source SHA mismatch: "+name)
        padding = candidate[start_block*SECTOR+size:(start_block+blocks)*SECTOR]
        require(not any(padding), "source padding contains unverified bytes")
        verified.append({"name": name, "source": source, "bytes": size,
                         "sha256": expected_hash, "start_block": start_block})

    # Allocation bitmap: original bits retained, one bit per appended in-use sector.
    bitmap = META_BITMAP*SECTOR
    data_area = META_BOOT+9
    require(new_n-data_area <= 9*SECTOR*8, "bitmap cannot address end of image")
    for sector in range(old_n, new_n):
        bit = sector-data_area
        allocated = bool(candidate[bitmap+bit//8] & (1 << (bit%8)))
        require(allocated == (sector in allocations), "bitmap allocation disagreement")
    # All original bitmap bits, not just newly allocated bits, must survive.
    # A damaged original allocation bit can make stock TempleOS unreadable.
    expected_bitmap = bytearray(original[bitmap:bitmap+9*SECTOR])
    for sector in allocations:
        bit = sector-data_area
        pos, mask = bit//8, 1 << (bit%8)
        require(not (expected_bitmap[pos] & mask), "new extent overwrites original bitmap")
        expected_bitmap[pos] |= mask
    require(candidate[bitmap:bitmap+9*SECTOR] == expected_bitmap,
            "original RedSea bitmap changed outside appended allocations")
    for sector in range(old_n, new_n):
        if sector not in allocations:
            require(not any(candidate[sector*SECTOR:(sector+1)*SECTOR]),
                    "unallocated sector contains unverified bytes")
    # Exact byte-preservation against the verified original. Only the minimum
    # metadata may differ in the legacy image.
    allowed = set(range(boot_offset+16, boot_offset+24))
    allowed.update(range(bitmap, (META_BITMAP+9)*SECTOR))
    root_entry_offset = start + len(orig_root)*64
    allowed.update(range(root_entry_offset, root_entry_offset+64))
    for sector in (16, 18):
        allowed.update(range(sector*ISO_SECTOR+80, sector*ISO_SECTOR+88))
    for i, (old_byte, new_byte) in enumerate(zip(original, candidate)):
        if old_byte != new_byte:
            require(i in allowed, "modified original boot/media byte offset "+str(i))
    return {"original_sha256": sha(original), "candidate_sha256": sha(candidate),
            "guest_path": "T:/"+NEW_FOLDER,
            "files": sorted(verified, key=lambda row: row["name"]),
            "original_blocks": old_n, "candidate_blocks": new_n,
            "native_guest_read": "UNVERIFIED",
            "native_compiler": "UNVERIFIED"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(inspect(args.candidate.read_bytes(), args.original.read_bytes()),
                     indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
