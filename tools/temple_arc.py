"""Bounded host port of the pinned TempleOS ArcExpandBuf read path.

Original source: Kernel/Compress.HC and Kernel/KernelA.HH at
c26482bb6ad3f80106d28504ec5db3c6a360732c. This runs on
the Windows/Python host. It does NOT run the HolyC guest compiler.
"""
import hashlib
import json
import subprocess
from pathlib import Path

from tools import check_redsea as audit
from tools.guest_closure import check_closure

HEADER_SIZE = 17
MAX_EXPANDED = 4 * 1024 * 1024
MAX_BITS = 12


def expand(src):
    """Port the on-disc compressed buffer expansion with bounded output."""
    audit.require(isinstance(src, bytes) and len(src) >= HEADER_SIZE,
                  "truncated TempleOS arc header")
    packed = int.from_bytes(src[:8], "little")
    expanded = int.from_bytes(src[8:16], "little")
    kind = src[16]
    audit.require(packed == len(src) and 0 < expanded <= MAX_EXPANDED,
                  "invalid packed/expanded Arc header")
    audit.require(kind in (1, 2, 3), "invalid TempleOS compression kind")
    if kind == 1:
        audit.require(len(src) == HEADER_SIZE + expanded, "uncompressed Arc extent")
        return src[HEADER_SIZE:]

    min_bits = 7 if kind == 2 else 8
    minimum = 1 << min_bits
    width = min_bits + 1
    free_idx = minimum
    limit = 1 << width
    table = {}
    buckets = {}
    entry_used = True
    cur_entry = None
    next_entry = None
    bitpos = HEADER_SIZE * 8

    def readbits(bits):
        nonlocal bitpos
        audit.require(bitpos + bits <= len(src) * 8, "compressed stream truncated")
        v = int.from_bytes(src[bitpos//8:bitpos//8+4], "little")
        v = (v >> (bitpos % 8)) & ((1 << bits) - 1)
        bitpos += bits
        return v

    def advance():
        nonlocal free_idx, entry_used, cur_entry, next_entry, width, limit
        if not entry_used:
            return
        entry_used = False
        cur_entry = next_entry
        if width < MAX_BITS:
            next_entry = free_idx
            free_idx += 1
            if free_idx == limit:
                width += 1
                limit = 1 << width
        else:
            # ArcEntryGet begins reusing entries when its *next* width
            # reaches 12; it skips hash buckets in use before eviction.
            for _ in range(limit - minimum + 1):
                free_idx += 1
                if free_idx == limit:
                    free_idx = minimum
                if not buckets.get(free_idx):
                    break
            else:
                raise audit.AuditError("Arc codebook cannot find replacement slot")
            next_entry = free_idx
            if free_idx in table:
                previous = table[free_idx][0]
                bucket = buckets.get(previous)
                audit.require(bucket is not None and free_idx in bucket,
                              "Arc dictionary ownership corruption")
                bucket.remove(free_idx)
                del table[free_idx]

    def phrase(code):
        chars = []
        for _ in range(1 << MAX_BITS):
            if code < minimum:
                audit.require(code >= 0, "negative Arc literal")
                chars.append(code)
                return bytes(reversed(chars))
            audit.require(code in table, "unknown Arc backreference")
            code, ch = table[code]
            chars.append(ch)
        raise audit.AuditError("cyclic Arc backreference")

    advance()
    entry_used = True
    first = readbits(width)
    audit.require(first < minimum, "first Arc code must be literal")
    out = bytearray([first])
    last_code = first
    last_ch = first
    advance()

    while len(out) < expanded:
        code = readbits(width)
        if code == cur_entry:
            chunk = phrase(last_code) + bytes([last_ch])
        else:
            chunk = phrase(code)
        audit.require(bool(chunk) and len(out) + len(chunk) <= expanded,
                      "Arc stream overproduced bytes")
        out.extend(chunk)
        last_ch = chunk[0]
        audit.require(cur_entry is not None and cur_entry not in table,
                      "Arc entry assigned twice before eviction")
        table[cur_entry] = (last_code, last_ch)
        buckets.setdefault(last_code, set()).add(cur_entry)
        entry_used = True
        advance()
        last_code = code

    audit.require(len(out) == expanded, "Arc expanded size mismatch")
    return bytes(out)


def verify_stock_imports(original_path, candidate_path, upstream):
    """Check every stock source actually requested by the guest project."""
    original = Path(original_path).read_bytes()
    patched = Path(candidate_path).read_bytes()
    coverage = check_closure(original, patched)
    root = {e["name"]: e for e in
            audit.entries(original, audit.ROOT_BLOCK * audit.SECTOR,
                          3 * audit.SECTOR)}
    directories = {name: {e["name"]: e for e in
                   audit.entries(original, root[name]["block"] * audit.SECTOR,
                                 root[name]["size"])}
                   for name in ("Compiler", "Kernel")}
    repo = Path(upstream)
    def git(*args):
        p = subprocess.run(["git", "-c", "core.autocrlf=false", "-C",
                            str(repo), *args], capture_output=True)
        if p.returncode:
            raise audit.AuditError("pinned stock Git source unavailable")
        return p.stdout
    audit.require(git("rev-parse", "HEAD").strip().decode("ascii") == audit.UPSTREAM,
                  "wrong source commit for stock decompression proof")
    stock = [r for r in coverage["resolved"] if r["source"] == "original"]
    audit.require(len(stock) == 33, "unexpected original import count")
    checked = {}
    for row in stock:
        path = row["on_disc"].lstrip("/")
        folder, name = path.split("/")
        if path in checked:
            continue
        entry = directories[folder][name]
        audit.require((entry["attr"] & audit.FILE_ATTR) == audit.FILE_ATTR
                      and not (entry["attr"] & 0x10),
                      "stock include is not a file")
        audit.require(0 < entry["size"] <= MAX_EXPANDED,
                      "stock include compressed extent too large")
        start = entry["block"] * audit.SECTOR
        end = start + entry["size"]
        audit.require(end <= len(original), "stock source extends beyond ISO")
        stored = original[start:end]
        uncompressed = expand(stored) if name.endswith(".Z") else stored
        source_name = path[:-2] if path.endswith(".Z") else path
        expected = git("show", audit.UPSTREAM + ":" + source_name)
        # The original RedSea ISO stores some editor format spaces as 0x1F,
        # while the exact pinned Git blob records 0x20. This is NOT byte
        # identity. Accept only this one proven, length-preserving difference
        # and report it separately, without claiming semantic equivalence.
        differences = [(a, b) for a, b in zip(uncompressed, expected) if a != b]
        audit.require(len(uncompressed) == len(expected) and
                      all(pair == (0x1f, 0x20) for pair in differences),
                      "stock compressed source differs beyond format markers: "
                      + source_name + " actual_sha256="
                      + hashlib.sha256(uncompressed).hexdigest()
                      + " expected_sha256=" + hashlib.sha256(expected).hexdigest())
        match_kind = "BYTE_EXACT" if not differences else "ISO_1F_GIT_SPACE_ONLY"
        checked[path] = {"source": source_name, "expanded_bytes": len(uncompressed),
                         "iso_expanded_sha256": hashlib.sha256(uncompressed).hexdigest(),
                         "pinned_git_sha256": hashlib.sha256(expected).hexdigest(),
                         "format_marker_differences": len(differences),
                         "match_kind": match_kind,
                         "is_compressed": name.endswith(".Z")}
    exact = sum(row["match_kind"] == "BYTE_EXACT" for row in checked.values())
    format_only = sum(row["match_kind"] == "ISO_1F_GIT_SPACE_ONLY"
                      for row in checked.values())
    marker_count = sum(row["format_marker_differences"] for row in checked.values())
    audit.require(len(checked) == 33 and exact == 25 and
                  format_only == 8 and marker_count == 57,
                  "unexpected stock source provenance profile")
    return {"upstream_commit": audit.UPSTREAM,
            "base_iso_sha256": hashlib.sha256(original).hexdigest(),
            "candidate_iso_sha256": hashlib.sha256(patched).hexdigest(),
            "import_requests": len(stock),
            "unique_sources_verified": len(checked),
            "byte_exact_sources": exact,
            "iso_format_marker_only_sources": format_only,
            "format_marker_byte_differences": marker_count,
            "compressed_sources_verified":
                sum(1 for v in checked.values() if v["is_compressed"]),
            "source_match_failures": 0, "sources": checked,
            "native_guest_execution": "UNVERIFIED",
            "guest_native_aot": "UNVERIFIED"}


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--original", required=True, type=Path)
    ap.add_argument("--candidate", required=True, type=Path)
    ap.add_argument("--upstream", required=True, type=Path)
    a = ap.parse_args()
    print(json.dumps(verify_stock_imports(a.original, a.candidate, a.upstream),
                     indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
