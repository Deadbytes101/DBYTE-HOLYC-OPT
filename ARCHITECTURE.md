# DBYTE-HOLYC-OPT PIPELINE

```mermaid
flowchart LR
    subgraph RESOURCE[READ-ONLY RESOURCE]
        HT[DBYTE-HOLYC-TOOLS]
        MAP[Source maps and compiler contracts]
        ARC[Codegen and fix-up archaeology]
        ID[Corpus identities and evidence limits]
        HT --> MAP
        HT --> ARC
        HT --> ID
    end

    subgraph TARGET[TERRY COMPILER]
        SRC[HolyC source]
        FRONT[Original lexer and parser]
        IC[CIntermediateCode]
        P06[Original OptPass 0 through 6]
        P710[Original OptPass 7 through 10]
        X64[Original x86-64 JIT or AOT output]
        SRC --> FRONT --> IC --> P06
        P710 --> X64
    end

    subgraph DEADBYTE[OVERHEAVEN GATE]
        PRE[IC invariant verifier]
        FACT[Temporary control and value facts]
        RULE[One proved rewrite]
        POST[Post-rewrite verifier]
        PRE --> FACT --> RULE --> POST
    end

    subgraph HARNESS[DIFFERENTIAL HARNESS]
        CASE[Byte-identified test case]
        BASE[Unmodified compiler]
        CAND[Candidate compiler]
        BO[Baseline observation]
        CO[Candidate observation]
        JUDGE[Semantic judge]
        METRIC[Code size and timing report]
        CASE --> BASE --> BO
        CASE --> CAND --> CO
        BO --> JUDGE
        CO --> JUDGE
        JUDGE --> METRIC
    end

    MAP --> PRE
    ARC --> PRE
    ID --> CASE
    P06 --> PRE
    POST --> P710
    X64 --> CAND
```

The resource repository is not linked into the compiler. It supplies pinned
facts and identities. The optimizer operates on Terry's existing intermediate
code and returns control to Terry's backend.

The semantic judge decides correctness. Measurements never override a mismatch.
