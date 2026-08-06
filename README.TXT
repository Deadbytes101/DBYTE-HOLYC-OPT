DBYTE-HOLYC-OPT
HOLYC TO OVERHEAVEN

STATUS

0.0.1 RARE PASS BOUNDARY CONTEXT
EXACT TEMPLEOSTS 1.10 CORPUS
LCCCompile PIPELINE OWNER SEALED
EXECUTABLE PASS ORDER SEALED
PASS CONTEXT SEALED DISPLAY
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

Sealed pass-boundary display:

  SHA256      D0D3EE768491C299B072BF3975BD707BA894349633E477D96670A6538E6F44F9

  Compiler/ICLCC.CPP
    SHA256    2F7A5A00947504E1D4D7DCFDBC99B16944D44F6C1DCEDABF2DAE6C60E5CD4873

  Compiler/OptPass6.CPP
    SHA256    1A960B56AB366DC821F1AE26045DC822B8FB81CCD3A653C52ECEADA689902487

  Compiler/OptPass789.CPP
    SHA256    7AEB06CD2850BA6F7CDBC6B9B4076BE26EE14260388EFBD660DA6584B823667F

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

PASS-BOUNDARY DISPLAY RESULT

Host execution on 2026-08-06 passed all exact identity gates and produced:

  D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-pass-boundary.txt

Observed console status:

  PASS CONTEXT    SEALED-DISPLAY
  PIPELINE OWNER  LCCCompile-SEALED
  SEAM            CANDIDATE-NOT-SEALED
  PATCH STATUS    NOT-AUTHORIZED
  VERDICT         PASS CONTEXT COMPLETE

The console proves source identity and deterministic report creation.  It does
not expose the displayed source lines and therefore does not seal the OptPass6,
OptPass789, LCCHeaderPut, or insertion-seam contracts.

The manual pipeline result and pass-display state are recorded in:

  TEMPLEOSTS-1.10-PIPELINE-ADJUDICATION.TXT

CURRENT PIPELINE

  EXACT TEMPLEOSTS.ISO IDENTITY
    -> PINNED HOLYARCHIVE EXTRACTION
    -> HASH ALL 1057 EXPANDED FILES
    -> VERIFY EXACT 31-FILE Compiler/ SET
    -> RAW OptPass TRACE
    -> SEALED SOURCE CONTEXT
    -> MANUAL LCCCompile OWNERSHIP ADJUDICATION
    -> SEALED OptPass6 AND OptPass789 CONTEXT DISPLAY
    -> MANUAL PASS-CONTRACT ADJUDICATION
    -> SEAL INSERTION SEAM
    -> SEAL NO-REWRITE VERIFIER
    -> DIFFERENTIAL HARNESS
    -> FIRST PROVED TRANSFORMATION

NEXT EVIDENCE

Preserve every existing evidence file.  Do not run another parser, tracer,
classifier, source patch, or optimizer experiment.

Manually review the complete contents of:

  D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-pass-boundary.txt

The review must establish from exact displayed source:

  OptPass6 output data and state
  OptPass789 input assumptions
  OptPass789 sizing and convergence invariants
  LCCHeaderPut pass-state transition semantics
  whether the post-label-forward boundary is safe and exact

A successful display report is not seam authorization.

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
  pass-boundary context display                 SEALED-DISPLAY
  post-label-forward boundary                   CANDIDATE
  OptPass6 output contract                      UNRESOLVED
  OptPass789 input contract                     UNRESOLVED
  LCCHeaderPut transition contract              UNRESOLVED
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
