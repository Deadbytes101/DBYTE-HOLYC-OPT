DBYTE-HOLYC-OPT
HOLYC TO OVERHEAVEN

STATUS

0.0.1 FOUNDATION
NO REWRITE ENABLED
NO PERFORMANCE CLAIM

PURPOSE

Extend Terry A. Davis's native HolyC optimizer without replacing HolyC,
translating it into another language, routing it through LLVM, or turning
TempleOS into a conventional hosted toolchain.

THE COMPILER REMAINS HOLYC.
THE INTERMEDIATE CODE REMAINS TERRY'S.
THE BACKEND REMAINS TERRY'S.
THE MACHINE CODE REMAINS NATIVE.

RESOURCE

DBYTE-HOLYC-TOOLS is the read-only evidence and archaeology resource:

  repository  Deadbytes101/DBYTE-HOLYC-TOOLS
  commit      37b0457e8735ab8cc34a23f2717fcfb808e6a7a8

It supplies source maps, compiler contracts, codegen archaeology, corpus
identities, and accepted evidence limits.  It is not linked into the compiler
and is not a runtime dependency.

TARGET

  repository  cia-foundation/TempleOS
  commit      c26482bb6ad3f80106d28504ec5db3c6a360732c
  seam        after OptPass6, before OptPass789A

The mirror identifies bytes. Terry-authored source and matching historical
packages remain the semantic authority.

PIPELINE

  HOLYC SOURCE
    -> ORIGINAL LEXER AND PARSER
    -> CIntermediateCode
    -> ORIGINAL OPTPASS 0 THROUGH 6
    -> DEADBYTE VERIFY / ANALYZE / REWRITE GATE
    -> ORIGINAL OPTPASS 7 THROUGH 10
    -> ORIGINAL X86-64 JIT OR AOT OUTPUT

FOUNDATION COMMANDS

  .\tools\VERIFY-HOLYC-TOOLS-RESOURCE.ps1 -Path D:\src\DBYTE-HOLYC-TOOLS

  .\tools\VERIFY-TEMPLEOS-TARGET.ps1 -Path D:\src\TempleOS

  .\tools\INSTALL-FOUNDATION.ps1 -TempleOS D:\src\TempleOS

CURRENT EVIDENCE

  resource manifest present
  exact resource verifier present
  exact target verifier present
  integration patch present
  intermediate-code list verifier present
  rewrite gate defaults to FALSE
  semantic observation contract present
  baseline/candidate judge present
  host PowerShell execution not yet observed
  patched HolyC compiler rebuild not yet observed
  guest semantic run not yet observed

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

RULE

A transformation is not accepted because it looks correct.
Baseline and candidate must produce equivalent semantic observations.
Measurements never override a mismatch.

REPORTS ARE CLAIMS, NOT EVIDENCE.
NO COSTUME RIGOR.
