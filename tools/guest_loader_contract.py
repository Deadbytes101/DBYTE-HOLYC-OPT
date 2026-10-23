"""Read-only provenance for the pinned TempleOS native include loader.

Source anchors establish the intended lookup algorithm, never guest execution.
"""
import hashlib
import subprocess
from pathlib import Path

from tools.check_redsea import AuditError, UPSTREAM


CONTRACT = {
    "Compiler/Lex.HC": (
        b'fbuf=ExtDft(cc->cur_str,"HC.Z");',
        b'LexIncludeStr(cc,buf2,FileRead(buf2),TRUE);',
    ),
    "Kernel/BlkDev/DskStrA.HC": (
        b'if (!FileExtDot(filename))',
        b'CatPrint(res,".%s",extension);',
        b'if (IsDotZ(name)) {',
        b'res=MStrPrint("%s.Z",name);',
    ),
    "Kernel/BlkDev/DskFile.HC": (
        b'altname=ToggleZorNotZ(absname);',
        b'for (i=0;i<2 && !res;i++) {//Try name, then altname',
        b'if (res && attr & RS_ATTR_COMPRESSED) {',
        b'res=ExpandBuf(arc);',
    ),
}


def inspect_sources(sources):
    """Require all loader stages to have the pinned implementation anchors."""
    if set(sources) != set(CONTRACT):
        raise AuditError("native loader source inventory drift")
    repeat = {b'CatPrint(res,".%s",extension);': 2,
              b'for (i=0;i<2 && !res;i++) {//Try name, then altname': 2}
    hashes = {}
    for path, required in CONTRACT.items():
        source = sources[path]
        if (not isinstance(source, bytes) or
                any(source.count(needle) != repeat.get(needle, 1)
                    for needle in required)):
            raise AuditError("native loader source contract drift: " + path)
        hashes[path] = hashlib.sha256(source).hexdigest()
    return {"upstream_commit": UPSTREAM, "source_sha256": hashes,
            "native_loader_source": "STATIC_CONTRACT_VERIFIED",
            "native_loader_execution": "UNVERIFIED",
            "guest_compilation": "UNVERIFIED"}


def verify(upstream):
    """Read exact objects from a Git checkout pinned to TempleOS archive commit."""
    root = Path(upstream)
    def git(*args):
        result = subprocess.run(["git", "-C", str(root), *args],
                                capture_output=True, check=True)
        return result.stdout
    try:
        sha = git("rev-parse", "HEAD").strip().decode("ascii")
        if sha != UPSTREAM:
            raise AuditError("native loader upstream commit changed")
        sources = {path: git("show", UPSTREAM + ":" + path)
                   for path in CONTRACT}
    except (subprocess.CalledProcessError, UnicodeDecodeError, OSError) as exc:
        raise AuditError("cannot verify pinned native loader source") from exc
    return inspect_sources(sources)
