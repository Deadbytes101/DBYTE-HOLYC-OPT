"""Generate a guest-side compiler project without overwriting stock source.

The existing TempleOS ISO has compressed /Compiler/*.HC.Z and /Kernel/*.HH.Z
files. Patched source stays only in /DBPATCH. This file is generated,
not a claim that native guest execution was observed.
"""
import re

INCLUDE = re.compile(rb'(?m)^(#include[ \t]+)"([^"\r\n]+)"([ \t]*)$')
PATCHED = {b"CExts": b"CEXTS.HC", b"PrsLib": b"PRSLIB.HC", b"DBOptPass": b"DBOPT.HC"}
SOURCE_ROOT = b"/Compiler/"
PATCH_ROOT = b"/DBPATCH/"


def rewrite(source):
    if not isinstance(source, bytes) or not source or b"\r" in source:
        raise ValueError("guest source must be nonempty canonical LF bytes")
    counts = {name: 0 for name in PATCHED}

    def replace(match):
        name = match.group(2)
        if name.startswith(b"/Kernel/") or name.startswith(b"/Compiler/"):
            return match.group(0)
        if (name.startswith(b"/") or b"\\" in name or b":" in name
                or b"." in name or b".." in name or b"/" in name):
            raise ValueError("unsafe or unknown include path")
        if not re.fullmatch(rb"[A-Za-z][A-Za-z0-9_]*", name):
            raise ValueError("unsafe guest compiler include")
        if name in counts:
            counts[name] += 1
            path = PATCH_ROOT + PATCHED[name]
        else:
            path = SOURCE_ROOT + name
        return match.group(1) + b'"' + path + b'"' + match.group(3)

    result, matched = INCLUDE.subn(replace, source)
    if matched < len(counts) or any(n != 1 for n in counts.values()):
        raise ValueError("missing or duplicated patched include anchor")
    if result.count(b"#include") != matched:
        raise ValueError("unknown include syntax or stray include")
    return result
