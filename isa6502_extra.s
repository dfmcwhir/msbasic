; ISA6502-specific overrides for input handling with non-ZP input buffer

.segment "CODE"

; READ A LINE, AND STRIP OFF SIGN BITS
; For non-ZP INPUTBUFFER, we need to handle 16-bit addressing
;INLIN:
;        ldx     #$00
;INLIN2:
;        jsr     GETLN
;        cmp     #$0D            ; CR?
;        beq     L2453
;        cmp     #$20            ; space or control char?
;        bcc     INLIN2
;        cmp     #$7D            ; DEL or higher?
;        bcs     INLIN2
;        cmp     #$40            ; '@' - delete char?
;        beq     L2423
;        cmp     #$5F            ; '_' - delete line?
;        beq     L2420
;L2443:
;        cpx     #$FF            ; max line length (255 chars)?
;        bcs     L244C
;        sta     INPUTBUFFER,x   ; store character
;        inx
;        bne     INLIN2          ; loop if more input
;L244C:
;        lda     #$07            ; BEL
;L244E:
;        jsr     OUTDO
;        bne     INLIN2
L2420:  ; delete line
        dex
        bpl     INLIN2          ; if X >= 0, continue
        jsr     CRDO            ; print CR/LF
        bne     INLIN2          ; always
L2423:  ; delete character
        dex
        jsr     CRDO            ; print CR/LF
;L2453:
;        jmp     L29B9
;
;GETLN:
;        jsr     MONRDKEY
;        rts