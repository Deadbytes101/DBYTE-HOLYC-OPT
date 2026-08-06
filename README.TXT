DBYTE-HOLYC-OPT
HOLYC TO OVERHEAVEN

STATUS

0.0.1 RARE-CORPUS FOUNDATION
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

It supplies exact package identity, HolyArchive extraction, compiler
archaeology, source navigation, and accepted evidence limits.  It is not linked
into the compiler and is not a runtime dependency.

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

The later 5.03 compiler may explain architecture, but no line from that common
source tree is accepted as a patch base for the internal 1.10 compiler.

CURRENT PIPELINE

  TEMPLEOSTS.ISO EXACT IDENTITY
    -> PINNED DBYTE-HOLYC-TOOLS HOLYARCHIVE
    -> RAW AND EXPANDED HISTORICAL BYTES
    -> RARE COMPILER FILE MANIFEST
    -> BOUNDED SEAM INSPECTION
    -> MANUAL SEAM ADJUDICATION
    -> NO-REWRITE VERIFIER
    -> DIFFERENTIAL HARNESS
    -> FIRST PROVED TRANSFORMATION

PREFERRED COMMAND

Run from the checked-out overheaven-foundation branch:

  Set-Location D:\TECHNICAL\DBYTE-HOLYC-OPT
  git pull
  .\tools\RUN-RARE-FOUNDATION.ps1

The runner derives this repository path from its own location.  It first looks
for the sibling resource repository:

  D:\TECHNICAL\DBYTE-HOLYC-TOOLS

ISO SELECTION

The first automatic candidate is the canonical acquisition source:

  DBYTE-HOLYC-TOOLS\legacy-input\templeos-v1.10\TempleOSTS.iso

If that file exists, its byte count and SHA256 must match exactly.  A failed
canonical identity stops the run; a VM baseline copy is not substituted.

Only when the canonical acquisition file is absent does the runner search the
repository parent, Downloads, Desktop, and Documents.  A discovered candidate
is accepted only when both its byte count and SHA256 match.  Multiple exact
non-canonical candidates require an explicit -IsoPath decision.

Default evidence output is outside Git:

  D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE

WINDOWS POWERSHELL

The corpus tools support Windows PowerShell by using ISO-8859-1 code page 28591,
a local expanded-path containment routine, and BitConverter SHA256 formatting.
They do not require Encoding.Latin1, Path.GetRelativePath, or Convert.ToHexString.

INCOMPLETE EXTRACTION RECOVERY

A failed post-extraction scan may leave:

  templeosts-1.10-internal\   PRESENT
  templeosts-compiler-manifest.txt   ABSENT

Nothing is deleted automatically.  After reviewing that this is the observed
state, revalidate and continue with:

  .\tools\RUN-RARE-FOUNDATION.ps1 -ResumeIncompleteExtraction

The resume switch does not trust the directory blindly.  It repeats resource
and ISO identity checks, requires raw, expanded, and holy directories, scans the
expanded corpus for all compiler markers, inventories compiler files, hashes
them, and only then writes the manifest.

If the ISO is elsewhere, give its real path:

  .\tools\RUN-RARE-FOUNDATION.ps1 `
      -IsoPath D:\actual\location\TempleOSTS.iso

If DBYTE-HOLYC-TOOLS is not beside this repository, give both paths:

  .\tools\RUN-RARE-FOUNDATION.ps1 `
      -HolyTools D:\actual\location\DBYTE-HOLYC-TOOLS `
      -IsoPath D:\actual\location\TempleOSTS.iso

MANUAL COMMANDS

  .\tools\VERIFY-HOLYC-TOOLS-RESOURCE.ps1 `
      -Path D:\actual\location\DBYTE-HOLYC-TOOLS

  .\tools\SEAL-TEMPLEOSTS-COMPILER.ps1 `
      -HolyTools D:\actual\location\DBYTE-HOLYC-TOOLS `
      -IsoPath D:\actual\location\TempleOSTS.iso `
      -ExtractRoot D:\actual\evidence\templeosts-1.10-internal `
      -ManifestPath D:\actual\evidence\templeosts-compiler-manifest.txt

  .\tools\INSPECT-TEMPLEOSTS-SEAM.ps1 `
      -ExtractRoot D:\actual\evidence\templeosts-1.10-internal `
      -ManifestPath D:\actual\evidence\templeosts-compiler-manifest.txt `
      -OutPath D:\actual\evidence\templeosts-compiler-seam.txt

The inspector verifies every compiler file against the sealed manifest before
reading it.  It tokenizes the expanded historical bytes directly, excludes
comments and quoted literals from the code stream, requires one COCCompile
definition, and proves only whether OptPass6 occurs before OptPass789A.

A PASS report does not authorize a patch.

CURRENT EVIDENCE

  rare ISO identity exists in DBYTE-HOLYC-TOOLS
  resource verification observed PASS on Windows: commit, 9/9 blobs, clean tree
  canonical legacy-input ISO selection observed PASS
  fresh extraction reached expanded-byte scanning
  partial extraction preserved after Windows PowerShell API incompatibility
  Windows PowerShell compatibility correction present
  explicit incomplete-extraction resume gate present
  exact-input foundation runner present
  rare corpus sealer present
  bounded rare seam inspector present
  semantic observation contract present
  baseline/candidate judge present
  common 5.03 patch prototype removed
  rare compiler manifest not yet observed in this project
  rare compiler insertion seam not yet sealed
  patched compiler rebuild not yet observed
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

NO RARE BYTE IDENTITY, NO TARGET.
NO SEALED SEAM, NO PATCH.
A TRANSFORMATION IS NOT ACCEPTED BECAUSE IT LOOKS CORRECT.
BASELINE AND CANDIDATE MUST PRODUCE EQUIVALENT SEMANTIC OBSERVATIONS.
MEASUREMENTS NEVER OVERRIDE A MISMATCH.

REPORTS ARE CLAIMS, NOT EVIDENCE.
NO COSTUME RIGOR.
