; ISA6502-specific print.s overrides for CONFIG_NO_INPUTBUFFER_ZP

.ifdef CONFIG_NO_INPUTBUFFER_ZP

.segment "CODE"

; This replaces the problematic code in print.s line 95-110
; The original uses indexed addressing which doesn't work with non-ZP buffers
L29B9:
  .ifdef CBM2
        lda     #$00
        sta     INPUTBUFFER
        ldx     #<(INPUTBUFFER-1)
        ldy     #>(INPUTBUFFER-1)
  .else
    .ifndef APPLE
        lda     #$00
        ; For non-ZP INPUTBUFFER, we can only do absolute addressing
        ; not indexed addressing. The input is terminated by null anyway.
        sta     INPUTBUFFER
        ldx     #LINNUM+1
    .endif
    .if .def(MICROTAN) || .def(SYM1)
        bne     CRDO2
    .endif
  .endif

.endif
