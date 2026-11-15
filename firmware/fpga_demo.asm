; SPDX-License-Identifier: GPL-3.0-or-later
; Bare-metal program for Interrupt Debugger's FPGA-hosted memory map.
BITS 16
CPU 8086
ORG 0
%ifndef SCENARIO
    %define SCENARIO 0
%endif
%if SCENARIO < 0 || SCENARIO > 3
    %error "SCENARIO must be 0 normal, 1 IRQ1 masked, 2 IRQ3 masked, 3 missing EOI"
%endif

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 01FFEh
    mov word [021h * 4], isr_ir1
    mov word [021h * 4 + 2], 0F000h
    mov word [023h * 4], isr_ir3
    mov word [023h * 4 + 2], 0F000h
    mov al, 013h
    out 020h, al
    mov al, 020h
    out 021h, al
    mov al, 001h
    out 021h, al
%if SCENARIO = 1
    mov al, 0F7h
%elif SCENARIO = 2
    mov al, 0FDh
%else
    mov al, 0F5h
%endif
    out 021h, al
    mov al, 0A0h            ; Program initialized: release the request sequencer.
    out 080h, al
    sti
idle:
    hlt
    mov al, 0D0h            ; Reached only after the CPU returns from an interrupt.
    out 080h, al
    jmp idle

isr_ir1:
    push ax
    mov al, 0B1h
    out 080h, al
%if SCENARIO != 3
    mov al, 061h
    out 020h, al
%endif
    pop ax
    iret

isr_ir3:
    push ax
    mov al, 0B3h
    out 080h, al
    mov al, 063h
    out 020h, al
    pop ax
    iret
