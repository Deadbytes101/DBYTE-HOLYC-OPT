; Host-only x86-64 Win64 witness. NASM assembly, not HolyC guest AOT.
; The body bytes show one redundant register MOV removed.
bits 64
section .text
global dbopt_stock_loop
global dbopt_candidate_loop
global dbopt_stock_inner_begin
global dbopt_stock_inner_end
global dbopt_candidate_inner_begin
global dbopt_candidate_inner_end

dbopt_stock_loop:
    mov rdx, rcx
    mov ecx, 10000000
stock_repeat:
dbopt_stock_inner_begin:
    mov r8, rdx
    mov r9, r8
    mov r8, rdx
dbopt_stock_inner_end:
    dec ecx
    jnz stock_repeat
    mov rax, r8
    add rax, r9
    ret

dbopt_candidate_loop:
    mov rdx, rcx
    mov ecx, 10000000
candidate_repeat:
dbopt_candidate_inner_begin:
    mov r8, rdx
    mov r9, r8
dbopt_candidate_inner_end:
    dec ecx
    jnz candidate_repeat
    mov rax, r8
    add rax, r9
    ret
