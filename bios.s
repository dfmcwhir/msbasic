.setcpu "6502"
.debuginfo

.zeropage
                .org ZP_START0
READ_PTR:       .res 1
WRITE_PTR:      .res 1
LAST_CHAR: 		.res 1


.segment "INPUT_BUFFER"
INPUT_BUFFER:   .res $100
TEMP:			.res $2

.segment "BIOS"

ACIA_DATA       = $7f14
ACIA_STATUS     = $7f15
ACIA_CMD        = $7f16
ACIA_CTRL       = $7f17
KBD_DATA		=$7f18
KBD_STATUS		=$7f19
KBD_CMD			=$7f1a
KBD_CTRL		=$7f1b
PORTB			=$7f00
PORTA			=$7f01
DDRB			=$7f02
DDRA			=$7f03
IFR				=$7f0d
IER				=$7f0e
IRQPORT			= $7fff

LOAD:
                rts

SAVE:
                rts

; Initialize the IO port
; modifies A, flags
INIT_IO:
	lda #$7f
	sta IER
	lda #$80
	sta IFR
	lda #$ff
	sta DDRB
	rts

; modifies A, flags
INIT_DISPLAY:
	lda #$00
	sta KBD_STATUS
	lda #$10 ; N-8-1 115.2K BAUD
	sta KBD_CTRL
	lda #$89 ; no parity, no echo, interrupts
	sta KBD_CMD
	rts


; Input a character from the serial interface.
; On return, carry flag indicates whether a key was pressed
; If a key was pressed, the key value will be in the A register
;
; Modifies: flags, A
MONRDKEY:
CHRIN:
    txa             ; save X
    pha

    jsr BUFFER_SIZE
    beq @no_keypressed

    jsr READ_BUFFER ; returns character in A
    jsr CHROUT      ; echo, but destroys A

    pla             ; restore X
    tax

    lda LAST_CHAR   ; restore the character READ_BUFFER produced
    sec             ; success
    rts

@no_keypressed:
    pla
    tax
    clc             ; no character
    rts


; Output a character (from the A register) to the serial interface.
;
; Modifies: flags
MONCOUT:
CHROUT:
	sta KBD_DATA
	pha
tx_wait:
	lda KBD_STATUS
	and #$10
	beq tx_wait
	pla
	rts

; Initialize the circular input buffer
; Modifies: flags, A
INIT_BUFFER:
                lda READ_PTR
                sta WRITE_PTR
                rts

; Write a character (from the A register) to the circular input buffer
; Modifies: flags, X
WRITE_BUFFER:
                ldx WRITE_PTR
                sta INPUT_BUFFER,x
                inc WRITE_PTR
                rts

; Read a character from the circular input buffer and put it in the A register
; Modifies: flags, A, X
READ_BUFFER:
                ldx READ_PTR
                lda INPUT_BUFFER,x
				sta LAST_CHAR
                inc READ_PTR
                rts

; Return (in A) the number of unread bytes in the circular input buffer
; Modifies: flags, A
BUFFER_SIZE:
                lda WRITE_PTR
                sec
                sbc READ_PTR
                rts


irq: ; reads the IRQ priority register and jmps to the appropriate interrupt routine
	sei
	PHA
    TXA
    PHA
    LDX IRQPORT
    LDA IRQTABLE,X
    STA TEMP
    INX
    LDA IRQTABLE,X
	STA TEMP+1
    JMP (TEMP)



IRQTABLE:   ; Order of the IRQ subroutines is reversed in the IRQ table due to a schematic error (?). The physical IRQ0 line reads 14 			 ;on the IRQ port which is 2x7 and correct. It may not be an actual wiring defect, but a feature becuase it makes it so
			; IRQ0 has the highest priority and IRQ7 has the lowest. either way, this IRQ table should work.
	.word IRQ7
	.word IRQ6
	.word IRQ5
	.word IRQ4
	.word IRQ3
	.word IRQ2
	.word IRQ1
	.word IRQ0

IRQ0:
	lda IRQPORT
	ora #$F0
	STA PORTB
	PLA
	TAX
	PLA
	cli
	rti
IRQ1:
	lda IRQPORT
	ora #$10
	STA PORTB
	PLA
	TAX
	PLA
	cli
	rti
IRQ2:
	lda IRQPORT
	ora #$20
	STA PORTB
	PLA
	TAX
	PLA
	cli
	rti
IRQ3:      ;SERIAL in interrupt
	lda IRQPORT
	ora #$30
	STA PORTB
	PLA
	TAX
	PLA
	cli
	rti

IRQ4:
	lda IRQPORT
	ora #$40
	STA PORTB
	PLA
	TAX
	PLA
	cli
	rti
IRQ5:
	lda IRQPORT
	ora #$50
	STA PORTB
	lda KBD_STATUS
	lda KBD_DATA
	jsr WRITE_BUFFER
	PLA
	TAX
	PLA
	cli
	rti
	
IRQ6:
	lda IRQPORT
	STA PORTB
	PLA
	TAX
	PLA
	cli
	rti
IRQ7:
	lda IRQPORT
	STA PORTB
	PLA
	TAX
	PLA
	cli
	rti

.include "wozmon.s"

.segment "RESETVEC"
                .word   $0F00           ; NMI vector
                .word   RESET           ; RESET vector
                .word   irq     ; IRQ vector

