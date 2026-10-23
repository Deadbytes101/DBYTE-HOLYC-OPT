"""Read-only filesystem evidence for native compiler includes in pinned RedSea.

This proves file presence and byte provenance. It does NOT execute TempleOS
or prove that its #include resolver supports compressed file suffixes.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

from tools import check_redsea as audit

_COMPONENT = re.compile(r"[A-Za-z][A-Za-z0-9_.]*\Z")
_INCLUDE = re.compile(rb'(?m)^#include[ \t]+"([^"\r\n]+)"[ \t]*$')
_PATCHED = frozenset(("CEXTS.HC", "PRSLIB.HC", "DBOPT.HC"))


def resolve_name(name, available):
    """Resolve the only candidates supported by this pinned source format."""
    if not _COMPONENT.fullmatch(name) or ".." in name:
        raise audit.AuditError("unsafe include component: " + repr(name))
    # Lex.HC #include calls ExtDft(name,"HC.Z") first.
    # DskFile.HC FileRead then tries the exact name before ToggleZorNotZ.
    # This is loader *priority*, not a general extension search.
    first = name if "." in name else name + ".HC.Z"
    second = first[:-2] if first.endswith(".Z") else first + ".Z"
    if first in available:
        return first
    if second in available:
        return second
    raise audit.AuditError("include not present at native loader paths: " + name)


def _directory(data, node):
    audit.require(node["attr"] == audit.DIRECTORY_ATTR, "import root is not a directory")
    return {item["name"]: item for item in
            audit.entries(data, node["block"] * audit.SECTOR, node["size"])}


def check_closure(original, candidate):
    """Cross-check every guest entrypoint import against on-disc directories."""
    media = audit.inspect(candidate, original, expected=audit.EXPECTED)
    old_root = {item["name"]: item for item in
                audit.entries(original, audit.ROOT_BLOCK * audit.SECTOR, 3 * audit.SECTOR)}
    new_root = {item["name"]: item for item in
                audit.entries(candidate, audit.ROOT_BLOCK * audit.SECTOR, 3 * audit.SECTOR)}
    old_dirs = {name: _directory(original, old_root[name])
                for name in ("Compiler", "Kernel")}
    patched = _directory(candidate, new_root["DBPATCH"])
    entry = patched["GUEST.PRJ"]
    audit.require(entry["attr"] == audit.FILE_ATTR, "guest entrypoint not a file")
    data = candidate[entry["block"] * audit.SECTOR:
                     entry["block"] * audit.SECTOR + entry["size"]]
    audit.require(hashlib.sha256(data).hexdigest() ==
                  audit.EXPECTED["GUEST.PRJ"][1], "guest entrypoint bytes changed")
    raw = _INCLUDE.findall(data)
    audit.require(data.count(b"#include") == len(raw), "unknown include syntax")
    audit.require(len(raw) == 36, "unexpected compiler import count")
    resolved = []
    patched_count = 0
    for encoded in raw:
        try:
            path = encoded.decode("ascii")
        except UnicodeDecodeError as exc:
            raise audit.AuditError("non-ASCII guest include") from exc
        parts = path.split("/")
        audit.require(len(parts) == 3 and parts[0] == ""
                      and parts[1] in ("Compiler", "Kernel", "DBPATCH"),
                      "unsafe or relative include: " + path)
        directory, base = parts[1:]
        names = patched if directory == "DBPATCH" else old_dirs[directory]
        actual = resolve_name(base, names)
        if directory == "DBPATCH":
            patched_count += 1
            audit.require(base in _PATCHED and actual == base,
                          "unexpected patched source: " + path)
        resolved.append({"requested": path,
                         "on_disc": "/" + directory + "/" + actual,
                         "source": "appended" if directory == "DBPATCH" else "original"})
    audit.require(patched_count == 3 and
                  {row["requested"] for row in resolved if row["source"] == "appended"}
                  == {"/DBPATCH/" + name for name in _PATCHED},
                  "patched compiler closure incomplete")
    return {"candidate_sha256": media["candidate_sha256"],
            "guest_entry_sha256": hashlib.sha256(data).hexdigest(),
            "total_includes": len(raw), "stock_includes": len(raw) - patched_count,
            "patched_includes": patched_count, "resolved": resolved,
            "native_guest_read": "UNVERIFIED",
            "compressed_suffix_runtime_resolution": "UNVERIFIED",
            "native_compiler_aot": "UNVERIFIED"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--upstream", type=Path)
    a = parser.parse_args()
    result = check_closure(a.original.read_bytes(), a.candidate.read_bytes())
    if a.upstream is not None:
        from tools.guest_loader_contract import verify
        result["native_loader_source_contract"] = verify(a.upstream)
    print(json.dumps(result, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
