DBYTE-HOLYC-OPT
HOLYC TO OVERHEAVEN

STATUS

0.0.1 RARE NO-REWRITE WORKSPACE
EXACT TEMPLEOSTS 1.10 CORPUS
LCCCompile PIPELINE OWNER SEALED
EXECUTABLE PASS ORDER SEALED
PASS CONTRACTS SEALED
EXACT INSERTION SEAM SEALED
NO-REWRITE ASSERTION INSTALLED
WORKSPACE OBSERVED
OPTIMIZER TRANSFORMATION DENIED
BUILD ROUTE UNRESOLVED
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

  expanded/   exact historical bytes; immutable evidence
  raw/        identity and archive evidence
  holy/       normalized navigation only

Authorized changes exist only in a new manifest-verified working tree.

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

SEALED PIPELINE

  file      Compiler/ICLCC.CPP
  function  LCCCompile

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

Compiler/CmpExts.CPP is an extern declaration surface only.

SEALED SEAM

  after
    LCCHeaderPut(lx,7,FALSE);

  before
    code_size=OptPass789(lx,fun_class,reg_offsets,NULL,NULL);

  original Compiler/ICLCC.CPP lines 410 and 411

At this point passes 0 through 6 and jump-table forwarding are complete,
lx->pass is 7, and OptPass789 first-time finalization has not started.

INSTALLED PATCH

  if (lx->pass!=7)
    LexExcept(lx,"ST_OPT_INTERNAL_ERROR");

This is a no-rewrite assertion.  It performs no valid-path write and installs no
optimizer transformation.

OBSERVED WORKSPACE INSTALL

  work root
    D:\TECHNICAL\DBYTE-HOLYC-OPT-WORK\templeosts-1.10-no-rewrite

  manifest files             1057/1057
  copied files               1057/1057
  changed files              1

  evidence Compiler/ICLCC.CPP SHA256
    2F7A5A00947504E1D4D7DCFDBC99B16944D44F6C1DCEDABF2DAE6C60E5CD4873

  patched Compiler/ICLCC.CPP SHA256
    DB1C75A5EE71B07ADAEC32E984146602E73D9A0D606E2B76B8CCCC624E0CDCB8

  install report SHA256
    59B0BB29AA5C088114E38FE27FCF5CB5E2D3F59120CD6FD2678DF9D566C75E32

  workspace status
    EXACT-COPY-PLUS-ONE-ASSERTION

  optimizer transformations
    NONE

Install record:

  TEMPLEOSTS-1.10-NO-REWRITE-INSTALL.TXT

EXACT BUILD ARTIFACTS

  Compiler/Compiler.PRJ
    bytes   858
    SHA256  D82BBFE3B9A75B67D5C3E1B6E5EB03628960B81FAC9E3453212AE1163A47F779

  Compiler/CmpMain.CPP
    bytes   15275
    SHA256  B4F1DE8EC776EAE47E3FBB77A7E6E23A50FEB9F4EEED6605986D4736283E4B8B

  Compiler/Compiler.BIN
    bytes   206512
    SHA256  010F06358F26B5804600EE5BD6E6D313209C006C606E5F72C1E68D4028825AD1

  Compiler/Compiler.MAP
    bytes   202757
    SHA256  8509A6224474915233209975E9D56598FA79E005F616B31B878D4350CED247A5

These identities prove the rare build artifacts exist.  They do not yet prove
the build command, loader route, output replacement sequence, or guest run.

NEXT COMMAND

Preserve the installed workspace.  Display the exact 1.10 build-route context:

  Set-Location D:\TECHNICAL\DBYTE-HOLYC-OPT
  git pull

  .\tools\DISPLAY-TEMPLEOSTS-COMPILER-BUILD-ROUTE.ps1 `
      -ExtractRoot D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-1.10-internal `
      -ManifestPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-expanded-manifest.txt `
      -WorkRoot D:\TECHNICAL\DBYTE-HOLYC-OPT-WORK\templeosts-1.10-no-rewrite `
      -InstallReportPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-no-rewrite-seam.txt `
      -OutPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-compiler-build-route.txt

The display tool:

  re-verifies all 1057 evidence files
  re-verifies all 1057 workspace files
  requires exactly one changed workspace path
  requires the observed patched ICLCC hash
  binds to the observed install report hash
  displays Compiler/Compiler.PRJ and Compiler/CmpMain.CPP
  reports raw exact references to Compiler.PRJ, Compiler.BIN, and Compiler.MAP
  does not build, load, execute, replace output, or modify the workspace

Expected status:

  WORKSPACE       EXACT-COPY-PLUS-ONE-ASSERTION
  BUILD ROUTE     RAW-DISPLAY-ONLY
  BUILD           NOT-OBSERVED
  VERDICT         BUILD ROUTE CONTEXT COMPLETE

RULE

WORKSPACE INSTALL IS NOT A BUILD.
NO EXACT BUILD ROUTE, NO BUILD COMMAND.
NO OBSERVED BUILD, NO COMPILER CLAIM.
NO GUEST DIFFERENTIAL, NO SEMANTIC CLAIM.
REPORTS ARE CLAIMS, NOT EVIDENCE.
NO COSTUME RIGOR.
