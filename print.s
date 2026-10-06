.segment "CODE"

PRSTRING:
        jsr     STRPRT
L297E:
        jsr     CHRGOT

; ----------------------------------------------------------------------------
; "PRINT" STATEMENT
; ----------------------------------------------------------------------------
PRINT:
        beq     CRDO
PRINT2:
        beq     L29DD
        cmp     #TOKEN_TAB
        beq     L29F5
        cmp     #TOKEN_SPC
.ifdef CONFIG_2
        clc	; also AppleSoft II
.endif
        beq     L29F5
        cmp     #','
; Pre-KIM had no CLC. KIM added the CLC
; here. Post-KIM moved the CLC up...
; (makes no sense on KIM, liveness = 0)
.if .def(CONFIG_11A) && (!.def(CONFIG_2))
        clc
.endif
        beq     L29DE
        cmp     #$3B
        beq     L2A0D
        jsr     FRMEVL
        bit     VALTYP
        bmi     PRSTRING
        jsr     FOUT
        jsr     STRLIT
.ifndef CONFIG_NO_CR
        ldy     #$00
        lda     (FAC_LAST-1),y
        clc
        adc     POSX
        cmp     Z17
        bcc     L29B1
        jsr     CRDO
L29B1:
.endif
        jsr     STRPRT
        jsr     OUTSP
       bne     L297E ; branch always


L29B9:
        ldy     #$00
        sty     INPUTBUFFER,x
        ldx     #LINNUM+1
  .ifdef CONFIG_FILE
        lda     CURDVC
        bne     L29DD
  .endif


CRDO:
.if .def(CONFIG_PRINTNULLS) && .def(CONFIG_FILE)
        lda     CURDVC
        bne     LC9D8
        sta     POSX
LC9D8:
.endif
        lda     #CRLF_1
        sta     POSX
        jsr     OUTDO
CRDO2:
        lda     #CRLF_2
        jsr     OUTDO

PRINTNULLS:
  .if .def(CONFIG_NULL) || .def(CONFIG_PRINTNULLS)
    .ifdef CONFIG_FILE
    ; Although there is no statement for it,
    ; CBM1 had NULL support and ignores
    ; it when not targeting the screen,
    ; CBM2 dropped it completely.
        lda     CURDVC
        bne     L29DD
    .endif
        txa
        pha
        ldx     Z15
        beq     L29D9
        lda     #$00
L29D3:
        jsr     OUTDO
        dex
        bne     L29D3
L29D9:
        stx     POSX
        pla
        tax
  .else
    ;.ifndef CONFIG_2
	.if (!.def(CONFIG_2)) || .def(ISA6502)    ; was:  .ifndef CONFIG_2
        lda     #$00
        sta     POSX
    .endif
        eor     #$FF
  .endif
L29DD:
        rts
L29DE:
        lda     POSX
.ifndef CONFIG_NO_CR
        cmp     Z18
        bcc     L29EA
        jsr     CRDO
        jmp     L2A0D
L29EA:
.endif
        sec
L29EB:
        sbc     #$0E
        bcs     L29EB
        eor     #$FF
        adc     #$01
        bne     L2A08
L29F5:
.ifdef CONFIG_11A
        php
.else
        pha
.endif
        jsr     GTBYTC
        cmp     #')'
.ifdef CONFIG_11A
  .ifdef CONFIG_2
        bne     SYNERR4
  .else
        jne     SYNERR
  .endif
        plp
        bcc     L2A09
.else
  .ifdef CONFIG_11
        jne     SYNERR
  .else
        bne     SYNERR4
  .endif
        pla
        cmp     #TOKEN_TAB
  .ifdef CONFIG_11
        bne     L2A09
  .else
        bne     L2A0A
  .endif
.endif
        txa
        sbc     POSX
        bcc     L2A0D
.ifndef CONFIG_11
        beq     L2A0D
.endif
L2A08:
        tax
.ifdef CONFIG_11
L2A09:
        inx
.endif
L2A0A:
.ifndef CONFIG_11
        jsr     OUTSP
.endif
        dex
.ifndef CONFIG_11
        bne     L2A0A
.else
        bne     L2A13
.endif
L2A0D:
        jsr     CHRGET
        jmp     PRINT2
.ifdef CONFIG_11
L2A13:
        jsr     OUTSP
        bne     L2A0A
.endif

; ----------------------------------------------------------------------------
; PRINT STRING AT (Y,A)
; ----------------------------------------------------------------------------
STROUT:
        jsr     STRLIT

; ----------------------------------------------------------------------------
; PRINT STRING AT (FACMO,FACLO)
; ----------------------------------------------------------------------------
STRPRT:
        jsr     FREFAC
        tax
        ldy     #$00
        inx
L2A22:
        dex
        beq     L29DD
        lda     (INDEX),y
        jsr     OUTDO
        iny
        cmp     #$0D
        bne     L2A22
        jsr     PRINTNULLS
        jmp     L2A22
; ----------------------------------------------------------------------------
OUTSP:
.ifdef CONFIG_FILE
; on non-screen devices, print SPACE
; instead of CRSR RIGHT
        lda     CURDVC
        beq     LCA40
        lda     #$20
        .byte   $2C
LCA40:
        lda     #$1D ; CRSR RIGHT
.else
        lda     #$20
.endif
        .byte   $2C
OUTQUES:
        lda     #$3F

; ----------------------------------------------------------------------------
; PRINT CHAR FROM (A)
; ----------------------------------------------------------------------------
OUTDO:
        bit     Z14
        bmi     L2A56
.if .def(CONFIG_PRINT_CR)
; Commodore forgot to remove this in CBM1
        pha
.endif
        cmp     #$20
        bcc     L2A4E
LCA6A:
.ifdef CONFIG_PRINT_CR
        lda     POSX
        cmp     Z17
        bne     L2A4C
        jsr     CRDO
L2A4C:
.endif
        inc     POSX
L2A4E:
.if .def(CONFIG_PRINT_CR)
; Commodore forgot to remove this in CBM1
        pla
.endif
.ifdef CONFIG_MONCOUT_DESTROYS_Y
        sty     DIMFLG
.endif
.ifdef CONFIG_IO_MSB
        ora     #$80
.endif
        jsr     MONCOUT
.ifdef CONFIG_IO_MSB
        and     #$7F
.endif
.ifdef CONFIG_MONCOUT_DESTROYS_Y
        ldy     DIMFLG
.endif
L2A56:
        and     #$FF
LE8F2:
        rts
