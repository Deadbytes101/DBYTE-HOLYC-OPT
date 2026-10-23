DBYTE-HOLYC-OPT
HOLYC TO OVERHEAVEN

STATUS

FOUNDATION / ZERO FALSE CLAIMS

PURPOSE

Extend Terry A. Davis's native HolyC compiler optimizer without replacing
HolyC, translating it into another language, routing it through LLVM, or
turning TempleOS into a conventional hosted toolchain.

This project works with Terry's CIntermediateCode pipeline and original x86-64
backend.  It adds narrowly proved transformations between original optimizer
pass 6 and the original sizing/fix-up/code-emission passes 7 through 10.

THE COMPILER REMAINS HOLYC.
THE INTERMEDIATE CODE REMAINS TERRY'S.
THE BACKEND REMAINS TERRY'S.
THE MACHINE CODE REMAINS NATIVE.

NON-GOALS

NO LLVM.
NO GCC BACKEND.
NO HOLYC-TO-C TRANSPILER.
NO NEW LANGUAGE DIALECT.
NO POSIX PORT.
NO WINDOWS ABI PORT.
NO PERMANENT SSA UNIVERSE.
NO FRAMEWORK-SHAPED PASS MANAGER.
NO PERFORMANCE CLAIM WITHOUT OBSERVED EVIDENCE.

TARGET LINE

The first target is the preserved TempleOS compiler source represented by the
cia-foundation/TempleOS archive commit:

  c26482bb6ad3f80106d28504ec5db3c6a360732c

That repository is used as a preservation mirror and byte-reference only.
Terry-authored source and matching historical packages remain the authority.

PIPELINE

  HOLYC SOURCE
    -> ORIGINAL LEXER AND PARSER
    -> CIntermediateCode
    -> ORIGINAL OPTPASS 0 THROUGH 6
    -> DEADBYTE VERIFY / ANALYZE / REWRITE GATE
    -> ORIGINAL OPTPASS 7 THROUGH 10
    -> ORIGINAL X86-64 JIT OR AOT OUTPUT

RULE

A transformation is not accepted because it looks correct.
It is accepted only after baseline and candidate executions produce equivalent
semantic observations under the differential harness.

REPORTS ARE CLAIMS, NOT EVIDENCE.
NO COSTUME RIGOR.

VERSION

0.0.1 FOUNDATION

ENGINEERING STATUS
native gate r1 is staged and host-tested, not guest-compiled
see VERIFY.txt for the pinned source and verification steps
no IR rewrite or performance benefit is claimed at r1

CURRENT ENGINEERING GATE — r18
native HolyC IR dead-move rewrite is implemented, not yet guest proven
r13 adds /DBPATCH/GUEST.PRJ for absolute imports of the pinned compiler patch
and stock /Compiler dependencies on the preserved TempleOS boot ISO
host unit tests and independent RedSea audits pass
native AOT, differential semantics and measured optimization remain unverified
do not call this a working or released optimizer until those gates pass
see VERIFY.txt for exact evidence and SHA-256 records

r17 checks all 36 guest compiler include paths against the pinned
TempleOS RedSea ISO directories without modifying the boot media.
this proves 33 stock and 3 patched file entries exist on disc.
compressed source loading and native HolyC compiler AOT still require
guest execution evidence before any optimizer release.

r18 fixes the import-closure checker to follow TempleOS's real loader
priority: bare names default to HC.Z; explicit extensions remain intact;
FileRead tries that exact path then its .Z toggled counterpart.
source anchors are checked from the pinned original TempleOS Git commit.
this is source-level verification only, not guest file read or native AOT.

r19 compressed-source provenance (host-only)
exact native TempleOS ArcExpandBuf dictionary replacement verified against
33 actual compiler imports from the unmodified original RedSea ISO.
25 expanded files match pinned upstream byte-for-byte; 8 differ in
57 positions, every ISO 0x1F against upstream ASCII space (0x20).
this is a distinct on-disc editor-format difference, NOT byte identity.
the kernel and compiler source provenance check still is NOT native AOT.
