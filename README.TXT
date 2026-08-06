DBYTE-HOLYC-OPT
HOLYC TO OVERHEAVEN

STATUS

0.0.1 RARE COMPILER BUILD ROUTE SEALED
EXACT TEMPLEOSTS 1.10 CORPUS
LCCCompile PIPELINE OWNER SEALED
EXECUTABLE PASS ORDER SEALED
PASS CONTRACTS SEALED
EXACT INSERTION SEAM SEALED
NO-REWRITE ASSERTION INSTALLED
WORKSPACE OBSERVED
COMPILER-ONLY BUILD ROUTE SEALED
BOOT LOAD ROUTE SEALED
MAP LOAD ROUTE SEALED
HOST BUILD GUARD NOT OBSERVED
GUEST DELIVERY UNRESOLVED
BUILD EXECUTION NOT AUTHORIZED
OPTIMIZER TRANSFORMATION DENIED

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
  raw/        original archive containers and identity evidence
  holy/       normalized navigation only

Authorized changes exist only in a separate manifest-verified working tree.

SEALED EVIDENCE

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

  no-rewrite install report SHA256
    59B0BB29AA5C088114E38FE27FCF5CB5E2D3F59120CD6FD2678DF9D566C75E32

  build-route display SHA256
    ED5108F73DE8363E948D559F7625F8752C15B6AD0AED941C40EDD01D0A8488A6

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

SEALED INSERTION SEAM

  after
    LCCHeaderPut(lx,7,FALSE);

  before
    code_size=OptPass789(lx,fun_class,reg_offsets,NULL,NULL);

  original Compiler/ICLCC.CPP lines 410 and 411

INSTALLED PATCH

  if (lx->pass!=7)
    LexExcept(lx,"ST_OPT_INTERNAL_ERROR");

This is a no-rewrite assertion.  It performs no valid-path write and installs no
optimizer transformation.

OBSERVED WORKSPACE

  work root
    D:\TECHNICAL\DBYTE-HOLYC-OPT-WORK\templeosts-1.10-no-rewrite

  files                       1057/1057
  changed files               1
  changed path                Compiler/ICLCC.CPP

  evidence ICLCC SHA256
    2F7A5A00947504E1D4D7DCFDBC99B16944D44F6C1DCEDABF2DAE6C60E5CD4873

  candidate ICLCC bytes       10527
  candidate ICLCC SHA256
    DB1C75A5EE71B07ADAEC32E984146602E73D9A0D606E2B76B8CCCC624E0CDCB8

EXACT PROJECT

  Compiler/Compiler.PRJ
    bytes   858
    SHA256  D82BBFE3B9A75B67D5C3E1B6E5EB03628960B81FAC9E3453212AE1163A47F779

The project imports the historical compiler implementation through CmpMain.
No later project, common mirror, normalized tree, or reconstruction is used.

SEALED COMPILER-ONLY BUILD ROUTE

Exact source-owned guest invocation:

  Cd("/Compiler");
  if (Cmp("Compiler","Compiler",,':'))
    throw;

Resolved objects:

  input     /Compiler/Compiler.PRJ.Z
  map       /Compiler/Compiler.MAP.Z
  binary    /Compiler/Compiler.BIN.Z

MakeAll executes this compiler build and then builds the kernel.  It is broader
than the first no-rewrite proof and remains unauthorized.

MakeOSPrtBootInstall calls MakeAll and continues into boot installation.  It is
not the first compiler-only route.

WRITE ORDER

Observed caller-visible order:

  compile and link Compiler.PRJ.Z
  write Compiler.MAP.Z
  construct the binary module and checksum
  write Compiler.BIN.Z
  return compiler error count

No temporary output name, backup copy, rename-based commit, or explicit rollback
appears in the displayed Cmp, CmpJoin, MakeAll, or MakeOSPrtBootInstall chain.
This makes a verified backup and restore contract mandatory before execution.

BOOT LOAD ROUTE

Kernel boot executes:

  ChgDsk(':');
  Cd("/Compiler");
  Load("Compiler",LDF_SILENT);

Load resolves Compiler.BIN.Z, validates module alignment and TEMPLEOS_XSUM, then
runs LoadPass1 and LoadPass2.

MAP LOAD ROUTE

Adam package initialization later executes:

  MapFileLoad("::/Compiler/Compiler");

Compiler.MAP.Z is source and symbol mapping data.  It is not the compiler module
loaded by the kernel.

Adjudication record:

  TEMPLEOSTS-1.10-COMPILER-BUILD-ROUTE-ADJUDICATION.TXT

NEXT COMMAND

Prepare a host-only guard snapshot.  This does not touch a VM or execute HolyC:

  Set-Location D:\TECHNICAL\DBYTE-HOLYC-OPT
  git pull

  .\tools\PREPARE-TEMPLEOSTS-COMPILER-BUILD-GUARD.ps1 `
      -ExtractRoot D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-1.10-internal `
      -ManifestPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-expanded-manifest.txt `
      -WorkRoot D:\TECHNICAL\DBYTE-HOLYC-OPT-WORK\templeosts-1.10-no-rewrite `
      -InstallReportPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-no-rewrite-seam.txt `
      -BuildRouteReportPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-compiler-build-route.txt `
      -GuardRoot D:\TECHNICAL\DBYTE-HOLYC-OPT-GUARD\templeosts-1.10-no-rewrite `
      -OutPath D:\TECHNICAL\DBYTE-HOLYC-OPT-EVIDENCE\templeosts-compiler-build-guard.txt

The guard contains:

  exact original Compiler.PRJ.Z
  exact original Compiler.BIN.Z
  exact original Compiler.MAP.Z
  exact original ICLCC.CPP.Z
  matching expanded baseline objects
  candidate expanded ICLCC.CPP
  a non-executable build contract
  a hash manifest

Expected status:

  HOST GUARD       PREPARED
  GUEST DELIVERY   UNRESOLVED
  BUILD            NOT-AUTHORIZED
  VERDICT          HOST GUARD SNAPSHOT COMPLETE

The tool is statically reviewed only.  Windows PowerShell execution is not yet
observed.

RULE

EXACT BUILD ROUTE IS NOT BUILD AUTHORIZATION.
HOST RECOVERY FILES ARE NOT A GUEST RESTORE PROOF.
NO OBSERVED DELIVERY, NO GUEST SOURCE CLAIM.
NO VERIFIED GUEST BACKUP AND RESTORE, NO BUILD.
NO OBSERVED BUILD, NO COMPILER CLAIM.
NO GUEST DIFFERENTIAL, NO SEMANTIC CLAIM.
REPORTS ARE CLAIMS, NOT EVIDENCE.
NO COSTUME RIGOR.
