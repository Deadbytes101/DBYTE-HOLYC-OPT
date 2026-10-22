import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import tarfile

from stage import BLOBS, PATCHES, UPSTREAM, check_source, run_git, safe_member, splice_exact


def digest(data):
    return hashlib.sha256(data).hexdigest()


def expected_files(upstream, native):
    check_source(upstream)
    archive_bytes = run_git(upstream, "archive", "--format=tar", UPSTREAM)
    result = {}
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:") as archive:
        members = archive.getmembers()
        if len(members) > 3000 or sum(m.size for m in members) > 134217728:
            raise ValueError("source exceeds fixed archive limits")
        for member in members:
            name = str(safe_member(member.name))
            if not (member.isdir() or member.isfile()):
                raise ValueError("unsupported source member: " + name)
            if member.isfile():
                if name in result:
                    raise ValueError("duplicate source file: " + name)
                with archive.extractfile(member) as src:
                    result[name] = digest(src.read())
    for name, (old, new) in PATCHES.items():
        raw = run_git(upstream, "show", f"{UPSTREAM}:{name}")
        if result.get(name) != digest(raw):
            raise ValueError("patch base mismatch: " + name)
        result[name] = digest(splice_exact(raw, old, new))
    added = "Compiler/DBOptPass.HC"
    if added in result:
        raise ValueError("source already contains native pass")
    native_data = native.read_bytes()
    if b"U0 DBOptPass(CCmpCtrl *cc)" not in native_data:
        raise ValueError("native pass signature missing")
    result[added] = digest(native_data)
    return result


def verify_stage(upstream, stage_root, native):
    upstream = Path(upstream).resolve()
    native = Path(native).resolve()
    stage_root = Path(stage_root)
    if stage_root.is_symlink() or not stage_root.is_dir():
        raise ValueError("missing or linked stage root")
    stage_root = stage_root.resolve()
    if stage_root == upstream or upstream in stage_root.parents or stage_root in upstream.parents:
        raise ValueError("stage must be separate from source")
    expected = expected_files(upstream, native)
    found = {}
    for directory, dirs, files in os.walk(stage_root, followlinks=False):
        root = Path(directory)
        for name in dirs:
            if (root / name).is_symlink():
                raise ValueError("linked stage directory: " + name)
        for name in files:
            target = root / name
            if target.is_symlink() or not target.is_file():
                raise ValueError("nonregular stage file: " + name)
            relative = target.relative_to(stage_root).as_posix()
            safe_member(relative)
            if relative in found:
                raise ValueError("duplicate stage path: " + relative)
            found[relative] = digest(target.read_bytes())
    receipt_path = "DBOPT-STAGE.json"
    if receipt_path not in found:
        raise ValueError("missing stage receipt")
    actual = {name: sha for name, sha in found.items() if name != receipt_path}
    if actual.keys() != expected.keys():
        missing = sorted(expected.keys() - actual.keys())
        extra = sorted(actual.keys() - expected.keys())
        raise ValueError("stage inventory drift missing=" + str(missing[:4]) +
                         " extra=" + str(extra[:4]))
    for name, sha in expected.items():
        if actual[name] != sha:
            raise ValueError("stage byte drift: " + name)
    receipt = json.loads((stage_root / receipt_path).read_bytes())
    required = {
        "upstream_commit": UPSTREAM,
        "upstream_blobs": BLOBS,
        "modified_files": list(PATCHES),
        "added_files": ["Compiler/DBOptPass.HC"],
        "sha256": {name: expected[name] for name in (*PATCHES, "Compiler/DBOptPass.HC")},
        "native_compilation_observed": False,
        "semantic_equivalence_observed": False,
        "performance_gain_observed": False,
    }
    if receipt != required:
        raise ValueError("stage receipt differs from independently reconstructed claims")
    inventory_hash = hashlib.sha256()
    for name in sorted(actual):
        inventory_hash.update(name.encode("utf-8") + b"\0" + bytes.fromhex(actual[name]))
    return {
        "upstream_commit": UPSTREAM,
        "files_checked": len(actual),
        "inventory_sha256": inventory_hash.hexdigest(),
        "native_compilation_observed": False,
        "semantic_equivalence_observed": False,
        "performance_gain_observed": False,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True, type=Path)
    parser.add_argument("--stage", required=True, type=Path)
    parser.add_argument("--native", type=Path,
                        default=Path(__file__).resolve().parents[1] / "native" / "DBOptPass.HC")
    args = parser.parse_args()
    print(json.dumps(verify_stage(args.upstream, args.stage, args.native),
                     sort_keys=True))
