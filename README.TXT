DBYTE-HOLYC-OPT
HOLYC TO OVERHEAVEN

STATUS

0.0.1 RARE NO-REWRITE SEAM
EXACT TEMPLEOSTS 1.10 CORPUS
LCCCompile PIPELINE OWNER SEALED
EXECUTABLE PASS ORDER SEALED
PASS CONTRACTS SEALED
EXACT INSERTION SEAM SEALED
NO-REWRITE ASSERTION AUTHORIZED
OPTIMIZER TRANSFORMATION DENIED
BUILD NOT OBSERVED

ONLY TARGET

  artifact    TempleOSTS.iso
  role        TempleOS 1.10 T.S. internal distro
  bytes       30558208
  SHA256      DD3709A0D43FF25439D2284B2F19F1DFA70BDE5B5A58A3733C5B1B244DDA37EC

RESOURCE

  repository  Deadbytes101/DBYTE-HOLYC-TOOLS
  commit      37b0457e8735ab8cc34a23f2717fcfb808e6a7a8

PATCH AUTHORITY

  expanded/   exact expanded historical bytes
  raw/        identity and archive evidence
  holy/       navigation only

The evidence tree is never modified.  Authorized changes go only into a new
manifest-verified working tree.

EVIDENCE

  expanded files              1057/1057
  expanded manifest SHA256
    6556485E4425386687C53F4F626146A2136AE12F38E075E2646C98147D61CB68

  compiler files              31/31
  compiler set SHA256
    2F840DD07625B71F55256AF29A6F4FCC263E0AA7301714AC4A36101FBDEEF261

  pipeline trace SHA256
    E32A0F2EF8A68B12ED7C4EC74E08ACCAAC405212A515B25EB32F21470E606924

  pipeline context SHA256
    D9C7C4DFB1B8F5CE78CEA0EA3C6F2B56E5274387D6CE3CE3914C2057B1760FC5

  pass-boundary context SHA256
    D0D3EE768491C299B072BF3975BD707BA894349633E477D96670A6538E6F44F9

  Compiler/ICLCC.CPP SHA256
    2F7A5A00947504E1D4D7DCFDBC99B16944D44F6C1DCEDABF2DAE6C60E5CD4873

  Compiler/OptPass6.CPP SHA256
    1A960B56AB366DC821F1AE26045DC822B8FB81CCD3A653C52ECEADA689902487

  Compiler/OptPass789.CPP SHA256
    7AEB06CD2850BA6F7CDBC6B9B4076BE26EE14260388EFBD660DA6584B823667F

PIPELINE

Compiler/CmpExts.CPP contains extern declarations only.

Compiler/ICLCC.CPP defines LCCCompile and owns:

  OptPass012
  OptPass012
  OptPass3
  OptPass4
  OptPass5
  OptPass6
  jump-table label forwarding
  OptPass789 sizing until stable
  AOT or JIT allocation
  OptPass789 final emission

PASS CONTRACTS

LCCHeaderPut optionally emits existing trace output and always assigns
lx->pass=pass.  It performs no displayed intermediate-code rewrite.

OptPass6 mutates the existing lx->lcc chain in place, maps selected stack
temporaries to registers, normalizes selected flags, propagates clobber state,
and writes fun_class register masks when applicable.

OptPass789 declares:

  pass 7  first-time finalization and sizing
  pass 8  repeated sizing until size stops shrinking
  pass 9  final emission

LCCCompile rejects pass-8 size growth and stops on stable size.

SEALED SEAM

  file      Compiler/ICLCC.CPP
  function  LCCCompile

  after
    LCCHeaderPut(lx,7,FALSE);

  before
    code_size=OptPass789(lx,fun_class,reg_offsets,NULL,NULL);

  original source lines 410 and 411

At this point passes 0 through 6 and jump-table forwarding are complete,
lx->pass is 7, and OptPass789 finalization, sizing, allocation, and emission
have not started.

Contract record:

  TEMPLEOSTS-1.10-PASS-CONTRACT-ADJUDICATION.TXT

FIRST AUTHORIZED PATCH

Only this no-rewrite assertion is authorized:

  if (lx->pass!=7)
    LexExcept(lx,"ST_OPT_INTERNAL_ERROR");

It reads pass state and performs no valid-path write.  No optimizer
transformation is authorized.

NEXT COMMAND

  Set-Location D:\TECHNICAL\DBYTE-HOLYC-OPT
  git pull

  .\tools\INSTALL-TEMPLEOSTS-NO-REWRITE-SEAM.ps1 `
      -ExtractRoot D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-1.10-internal `
      -ManifestPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-expanded-manifest.txt `
      -WorkRoot D:\TECHNICAL\DBYTE-HOLYC-OPT-WORK\templeosts-1.10-no-rewrite `
      -OutPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-no-rewrite-seam.txt

The installer verifies and copies all 1057 files, patches one exact source
needle, verifies that only Compiler/ICLCC.CPP differs, and confirms the evidence
source hash remains unchanged.  It does not build or execute the compiler.

Expected status:

  WORKSPACE       EXACT-COPY-PLUS-ONE-ASSERTION
  SEAM            SEALED
  PATCH CLASS     NO-REWRITE-ASSERTION
  OPT TRANSFORMS  NONE
  BUILD           NOT-OBSERVED
  VERDICT         INSTALL COMPLETE

The installer is statically reviewed.  Windows PowerShell execution is not yet
observed.

RULE

SEALED SEAM AUTHORIZES ONLY THE NAMED PATCH.
NO OBSERVED WORKSPACE, NO PATCH INSTALL CLAIM.
NO OBSERVED BUILD, NO COMPILER CLAIM.
NO GUEST DIFFERENTIAL, NO SEMANTIC CLAIM.
REPORTS ARE CLAIMS, NOT EVIDENCE.
NO COSTUME RIGOR.
