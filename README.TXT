DBYTE-HOLYC-OPT
HOLYC TO OVERHEAVEN

STATUS

0.0.1 RARE PIPELINE OWNER SEALED
EXACT TEMPLEOSTS 1.10 CORPUS
LCCCompile PIPELINE OWNER SEALED
EXECUTABLE PASS ORDER SEALED
SEAM CANDIDATE NOT SEALED
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

ONLY TARGET

  artifact    TempleOSTS.iso
  version     TempleOS 1.10
  role        T.S. internal distro
  bytes       30558208
  SHA256      DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC

RESOURCE

  repository  Deadbytes101/DBYTE-HOLYC-TOOLS
  commit      37b0457e8735ab8cc34a23f2717fcfb808e6a7a8

DBYTE-HOLYC-TOOLS is read-only evidence and extraction infrastructure.  It is
not linked into the compiler and is not a runtime dependency.

PATCH AUTHORITY

  expanded/   exact expanded historical bytes
  raw/        identity and archive evidence
  holy/       navigation only; never patch authority

COMMON MIRRORS ARE NOT TARGETS.
PUBLIC STANDARD ISO IS NOT THE TARGET.
LATER FORKS AND PORTS ARE NOT TARGETS.

OBSERVED EVIDENCE

Expanded manifest:

  files       1057/1057
  SHA256      6556485E4425386687C53F4F626146A2136AE12F38E075E2646C98147D61CB68

Compiler discovery:

  text files  777
  candidates  45
  SHA256      66DEED7083CABB292064477ECE15F8AA368A86B47FED1C45C097BFAC0A0F6348

Exact Compiler/ set:

  files       31/31
  SHA256      2F840DD07625B71F55256AF29A6F4FCC263E0AA7301714AC4A36101FBDEEF261

Raw pipeline trace:

  occurrences 25
  files       9
  SHA256      E32A0F2EF8A68B12ED7C4EC74E08ACCAAC405212A515B25EB32F21470E606924

Sealed pipeline context:

  SHA256      D9C7C4DFB1B8F5CE78CEA0EA3C6F2B56E5274387D6CE3CE3914C2057B1760FC5

  Compiler/CmpExts.CPP
    SHA256    002367120BFE4C97F8DCAAD23CE549BB407949558A0BE15076ADD4EF3AEA9CA2

  Compiler/ICLCC.CPP
    SHA256    2F7A5A00947504E1D4D7DCFDBC99B16944D44F6C1DCEDABF2DAE6C60E5CD4873

MANUAL PIPELINE ADJUDICATION

Compiler/CmpExts.CPP lines 30 through 36 are extern declarations.  They expose
pass interfaces but execute no pass.  CmpExts.CPP is not the pipeline owner.

Compiler/ICLCC.CPP lines 377 through 444 define LCCCompile.  The displayed
source proves that LCCCompile owns the low-level optimizer, sizing, allocation,
and final-emission sequence.

Executable order observed inside LCCCompile:

  line 387  OptPass012
  line 389  OptPass012
  line 391  OptPass3
  line 393  OptPass4
  line 395  OptPass5
  line 397  OptPass6

  lines 400-408
    forward jump-table labels through OptLabelFwd

  line 411  OptPass789 sizing
  line 415  OptPass789 sizing until stable
  lines 422-425
    allocate AOT or JIT output storage
  line 427  OptPass789 final emission

LCCCompile is sealed as the owner of this optimizer-to-emission pipeline.  This
does not claim that it is the top-level parser or language frontend entrypoint.

CANDIDATE SEAM

The strongest semantic boundary is:

  after jump-table label forwarding completes at source line 408
  before the first OptPass789 sizing call at source line 411

At that point passes 0 through 6 and label forwarding are complete, while
OptPass789 sizing and emission have not started.

Existing source line 410 calls LCCHeaderPut(lx,7,FALSE).  Its pass-state and
trace contract must be preserved or explicitly accounted for.  The exact
insertion point is therefore not sealed and no patch is authorized.

The manual result is recorded in:

  TEMPLEOSTS-1.10-PIPELINE-ADJUDICATION.TXT

CURRENT PIPELINE

  EXACT TEMPLEOSTS.ISO IDENTITY
    -> PINNED HOLYARCHIVE EXTRACTION
    -> HASH ALL 1057 EXPANDED FILES
    -> VERIFY EXACT 31-FILE Compiler/ SET
    -> RAW OptPass TRACE
    -> SEALED SOURCE CONTEXT
    -> MANUAL LCCCompile OWNERSHIP ADJUDICATION
    -> DISPLAY EXACT OptPass6 AND OptPass789 CONTRACT CONTEXT
    -> MANUAL PASS-BOUNDARY ADJUDICATION
    -> SEAL NO-REWRITE VERIFIER
    -> DIFFERENTIAL HARNESS
    -> FIRST PROVED TRANSFORMATION

NEXT COMMAND

Preserve every existing evidence file.  Pull and display only the exact pass
boundary context:

  Set-Location D:\TECHNICAL\DBYTE-HOLYC-OPT
  git pull

  .\tools\DISPLAY-TEMPLEOSTS-PASS-BOUNDARY.ps1 `
      -ExtractRoot D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-1.10-internal `
      -ManifestPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-expanded-manifest.txt `
      -OutPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-pass-boundary.txt

The display tool:

  verifies the observed manifest hash
  verifies exact ICLCC.CPP identity
  verifies OptPass6.CPP and OptPass789.CPP against the manifest
  re-displays the ICLCC transition between OptPass6 and OptPass789
  displays raw definition context from OptPass6.CPP and OptPass789.CPP
  uses no function parser, comment filter, quote filter, or classifier
  does not authorize an insertion seam or source patch

Expected final status:

  PASS CONTEXT       SEALED-DISPLAY
  PIPELINE OWNER     LCCCompile-SEALED
  SEAM               CANDIDATE-NOT-SEALED
  PATCH STATUS       NOT-AUTHORIZED

CURRENT EVIDENCE STATUS

  canonical ISO identity                         PASS
  pinned DBYTE-HOLYC-TOOLS resource             PASS
  full expanded manifest                        PASS
  exact Compiler/ set                           PASS
  raw pipeline trace                            PASS
  sealed pipeline source context                PASS
  CmpExts declaration classification            SEALED
  LCCCompile pipeline ownership                 SEALED
  executable pass order                         SEALED
  post-label-forward boundary                   CANDIDATE
  OptPass6 output contract                      NOT YET ADJUDICATED
  OptPass789 input contract                     NOT YET ADJUDICATED
  insertion seam                                NOT SEALED
  compiler rebuild                              NOT OBSERVED
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
NO SEALED PASS CONTRACT, NO SEAM.
NO SEALED SEAM, NO PATCH.
UNKNOWN MEANS DO NOT TRANSFORM.
A SMALLER BINARY IS NOT PROOF.
A FASTER RUN IS NOT PROOF.
BASELINE AND CANDIDATE MUST AGREE.

REPORTS ARE CLAIMS, NOT EVIDENCE.
NO COSTUME RIGOR.
