DBYTE-HOLYC-OPT
HOLYC TO OVERHEAVEN

STATUS

0.0.1 RARE RAW PIPELINE TRACE
COMPILER DIRECTORY CANDIDATE OBSERVED
PIPELINE UNRESOLVED
SEAM UNRESOLVED
NO PATCH AUTHORIZED
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

DBYTE-HOLYC-TOOLS is the read-only evidence and archive resource:

  repository  Deadbytes101/DBYTE-HOLYC-TOOLS
  commit      37b0457e8735ab8cc34a23f2717fcfb808e6a7a8

It supplies exact package identity and HolyArchive extraction.  It is not
linked into the compiler and is not a runtime dependency.

ONLY TARGET

  artifact    TempleOSTS.iso
  version     TempleOS 1.10
  role        T.S. internal distro
  bytes       30558208
  SHA256      DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC

PATCH AUTHORITY

  expanded/   YES: exact files expanded from the rare ISO
  raw/        identity and archive evidence
  holy/       navigation only; extensions are normalized

COMMON MIRRORS ARE NOT TARGETS.
PUBLIC STANDARD ISO IS NOT THE TARGET.
LATER FORKS AND PORTS ARE NOT TARGETS.

OBSERVED CORRECTIONS

The later TempleOS 5.03 compiler uses names including COCCompile, OptPass6,
OptPass789A, and CIntermediateCode.  Those names were architecture clues only.

The exact TempleOSTS 1.10 expanded corpus was scanned on Windows on 2026-08-06.
COCCompile was absent, while OptPass6 and CIntermediateCode were present.
Therefore later-era entrypoint and late-pass names are not accepted as 1.10
contracts, but the original 1.10 optimizer and intermediate-code vocabulary are
now directly observed in the rare bytes.

The first pipeline tracer attempted to mask C-style comments and quoted
literals.  Exact 1.10 Compiler/ bytes rejected that assumed quote grammar with:

  unterminated quoted literal at offset 205686

The failure occurred before report creation.  No source or prior evidence was
modified.  A partial HolyC lexer is not accepted as evidence, so quote and
comment inference was removed.  The current tracer performs raw Latin-1 text
matching and labels every result LEXICAL-UNFILTERED.

OBSERVED CORPUS FOUNDATION

  expanded files                 1057/1057
  text-like files                777
  discovery candidates           45

  expanded manifest SHA256
    6556485E4425386687C53F4F626146A2136AE12F38E075E2646C98147D61CB68

  compiler discovery SHA256
    66DEED7083CABB292064477ECE15F8AA368A86B47FED1C45C097BFAC0A0F6348

  COCCompile                     0
  OptPass6                       10
  OptPass789A                    0
  CIntermediateCode             169

Highest-scoring exact paths included:

  Compiler/StmtParser.CPP
  Compiler/ExpParser.CPP
  Compiler/CmpExts.CPP
  Compiler/Assembler.CPP
  Compiler/ICLCC.CPP
  Compiler/OptPass6.CPP
  Compiler/OptPass012.CPP
  Compiler/OptPass3.CPP
  Compiler/CmpMain.CPP
  Compiler/OptPass4.CPP

These paths are evidence-backed candidates.  Scores are navigation aids only.

CURRENT PIPELINE

  TEMPLEOSTS.ISO EXACT IDENTITY
    -> PINNED DBYTE-HOLYC-TOOLS HOLYARCHIVE
    -> RAW AND EXPANDED HISTORICAL BYTES
    -> HASH ALL 1057 EXPANDED FILES
    -> DISCOVER COMPILER-LIKE PATHS AND SYMBOLS
    -> VERIFY THE EXACT Compiler/ FILE SET
    -> TRACE RAW OptPass* TEXT OCCURRENCES PER FILE
    -> DISPLAY CmpMain.CPP RAW SOURCE CONTEXT
    -> MANUAL CODE VS NON-CODE ADJUDICATION
    -> MANUAL PIPELINE ADJUDICATION
    -> MANUAL SEAM ADJUDICATION
    -> NO-REWRITE VERIFIER
    -> DIFFERENTIAL HARNESS
    -> FIRST PROVED TRANSFORMATION

NEXT COMMAND

The manifest and discovery report already exist.  Preserve them and run only
the read-only raw pipeline tracer:

  Set-Location D:\TECHNICAL\DBYTE-HOLYC-OPT
  git pull

  .\tools\ADJUDICATE-TEMPLEOSTS-PIPELINE.ps1 `
      -ExtractRoot D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-1.10-internal `
      -ManifestPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-expanded-manifest.txt `
      -DiscoveryPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-compiler-discovery.txt `
      -OutPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-pipeline-adjudication.txt

The tracer:

  rechecks every Compiler/ file against the expanded manifest
  requires the observed CmpMain.CPP and OptPass6.CPP candidates
  hashes the sorted exact Compiler/ file set
  decodes exact bytes with ISO-8859-1 one byte to one character
  records every raw OptPass* occurrence by path, line, and byte offset
  reports raw lexical order for each candidate file
  includes line-numbered context around CmpMain.CPP occurrences
  explicitly allows declarations, definitions, comments, and quoted text
  does not claim that an occurrence is executable code
  does not infer function ownership
  does not select an insertion seam
  does not modify source or prior evidence

Expected final status:

  SCAN MODE           RAW-TEXT-LATIN1
  COMPILER SET        EXACT-CANDIDATE
  PIPELINE            RAW-TRACE-ONLY
  SEAM                UNRESOLVED
  PATCH STATUS        NOT AUTHORIZED

CURRENT EVIDENCE

  canonical ISO identity                         PASS
  pinned DBYTE-HOLYC-TOOLS commit               PASS
  pinned resource blobs                         9/9 PASS
  resource tracked tree                         CLEAN
  HolyArchive extraction                        PASS
  full expanded manifest                        PASS
  compiler discovery report                     PASS
  Compiler/ directory candidates                OBSERVED
  C-style quote-mask assumption                 REJECTED
  raw pipeline trace report                     NOT YET OBSERVED
  rare compiler pipeline identity               UNRESOLVED
  rare compiler insertion seam                  UNRESOLVED
  patched compiler rebuild                      NOT OBSERVED
  guest semantic run                            NOT OBSERVED

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

NO RARE BYTE IDENTITY, NO TARGET.
NO COMPILER IDENTITY, NO SEAM.
NO SEALED SEAM, NO PATCH.
UNKNOWN MEANS DO NOT TRANSFORM.
A SMALLER BINARY IS NOT PROOF.
A FASTER RUN IS NOT PROOF.
BASELINE AND CANDIDATE MUST AGREE.

REPORTS ARE CLAIMS, NOT EVIDENCE.
NO COSTUME RIGOR.
