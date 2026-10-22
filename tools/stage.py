import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

UPSTREAM = "c26482bb6ad3f80106d28504ec5db3c6a360732c"
BLOBS = {
    "Compiler/PrsLib.HC": "6f0f6fc0e624bd397db5d9ccc83b769198277922",
    "Compiler/Compiler.PRJ": "72015bdce68bbbb330e56299ca805e665e908fd9",
    "Compiler/CExts.HC": "13d2781ce98e21dd9f9cea1f3c462f78101b9548",
    "Compiler/OptPass6.HC": "0771991824a8029692def23c56395ee05634f77b",
}
PATCHES = {
    "Compiler/PrsLib.HC": (
        b"  OptPass6(cc);\n  COCHeaderPut(cc,7,TRUE);",
        b"  OptPass6(cc);\n  DBOptPass(cc);\n  COCHeaderPut(cc,7,TRUE);",
    ),
    "Compiler/Compiler.PRJ": (
        b'#include "OptPass6"\n#include "BackLib"',
        b'#include "OptPass6"\n#include "DBOptPass"\n#include "BackLib"',
    ),
    "Compiler/CExts.HC": (
        b"extern U0 OptPass6(CCmpCtrl *cc);\nextern I64 OptPass789A(",
        b"extern U0 OptPass6(CCmpCtrl *cc);\nextern U0 DBOptPass(CCmpCtrl *cc);\nextern I64 OptPass789A(",
    ),
}

def run_git(root, *args):
    proc = subprocess.run(
        ["git", "-c", "core.autocrlf=false", "-C", str(root), *args],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if proc.returncode:
        raise RuntimeError("git command failed: " + " ".join(args) +
                           ": " + proc.stderr.decode("utf-8", "replace")[:300])
    return proc.stdout

def splice_exact(original, before, after):
    if original.count(before) != 1 or before == after:
        raise ValueError("missing or ambiguous upstream anchor")
    return original.replace(before, after, 1)

def safe_member(name):
    p = PurePosixPath(name)
    if (p.is_absolute() or not p.parts or str(p) != name or
            any(part in ("..", ".", "") for part in p.parts) or
            ":" in p.parts[0] or "\\" in name):
        raise ValueError("unsafe archive member")
    return p

def check_source(repo):
    head = run_git(repo, "rev-parse", "HEAD").decode().strip()
    if head != UPSTREAM:
        raise ValueError("upstream HEAD is not pinned commit: " + head)
    for path, expected in BLOBS.items():
        actual = run_git(repo, "rev-parse", f"{UPSTREAM}:{path}").decode().strip()
        if actual != expected:
            raise ValueError("upstream blob drift: " + path)
    return head

def stage(repo, out, native):
    repo, out, native = repo.resolve(), out.resolve(), native.resolve()
    if not repo.is_dir() or not native.is_file():
        raise ValueError("missing source repository or native pass")
    if out.exists() or out == repo or repo in out.parents or out in repo.parents:
        raise ValueError("output must be new and separate from upstream")
    check_source(repo)
    replacements = {}
    for name, (old, new) in PATCHES.items():
        data = run_git(repo, "show", f"{UPSTREAM}:{name}")
        replacements[name] = splice_exact(data, old, new)
    original_pass = native.read_bytes()
    if b"U0 DBOptPass(CCmpCtrl *cc)" not in original_pass:
        raise ValueError("invalid native pass signature")
    archive_bytes = run_git(repo, "archive", "--format=tar", UPSTREAM)
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:") as archive:
        members = archive.getmembers()
        if len(members) > 3000 or sum(m.size for m in members) > 134217728:
            raise ValueError("archive exceeds bounded source limits")
        for member in members:
            safe_member(member.name)
            if not (member.isfile() or member.isdir()):
                raise ValueError("archive links and special files rejected")
        out.mkdir(parents=True)
        for member in members:
            dest = out.joinpath(*PurePosixPath(member.name).parts)
            if member.isdir():
                dest.mkdir(parents=True, exist_ok=True)
            else:
                dest.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as src, dest.open("wb") as target:
                    target.write(src.read())
    for name, data in replacements.items():
        target = out.joinpath(*PurePosixPath(name).parts)
        if target.read_bytes() != run_git(repo, "show", f"{UPSTREAM}:{name}"):
            raise ValueError("unexpected stage content: " + name)
        target.write_bytes(data)
    added = out / "Compiler" / "DBOptPass.HC"
    if added.exists():
        raise ValueError("upstream unexpectedly contains DBOptPass")
    added.write_bytes(original_pass)
    checksums = {
        name: hashlib.sha256(out.joinpath(*PurePosixPath(name).parts).read_bytes()).hexdigest()
        for name in (*PATCHES, "Compiler/DBOptPass.HC")
    }
    receipt = {
        "upstream_commit": UPSTREAM,
        "upstream_blobs": BLOBS,
        "modified_files": list(PATCHES),
        "added_files": ["Compiler/DBOptPass.HC"],
        "sha256": checksums,
        "native_compilation_observed": False,
        "semantic_equivalence_observed": False,
        "performance_gain_observed": False,
    }
    (out / "DBOPT-STAGE.json").write_text(
        json.dumps(receipt, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    return receipt

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    receipt = stage(
        args.upstream, args.out,
        Path(__file__).resolve().parents[1] / "native" / "DBOptPass.HC")
    print(json.dumps(receipt, sort_keys=True))
