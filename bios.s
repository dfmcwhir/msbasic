.setcpu "65C02"
.debuginfo

.zeropage
                .org ZP_START0
READ_PTR:       .res 1
WRITE_PTR:      .res 1
TEMP_IRQ_ADDR:	.res 2



.segment "INPUT_BUFFER"
INPUT_BUFFER:   .res $100
LAST_CHAR: 		.res 1
DEVSTAT:		.res 1
UI_DATA_OFF:		.res 1
UI_STATUS_OFF:		.res 1
UI_CMD_OFF:			.res 1
UI_CTRL_OFF:		.res 1


.segment "BIOS"


;IO address offsets from IO_BASE
IO_BASE				= $7f00
ACIA_DATA_OFF:		.byte $14
ACIA_STATUS_OFF:	.byte $15
ACIA_CMD_OFF:		.byte $16
ACIA_CTRL_OFF:		.byte $17
KEYBDISP_DATA_OFF:	.byte $18
KEYBDISP_STATUS_OFF:	.byte $19
KEYBDISP_CMD_OFF:	.byte $1a
KEYBDISP_CTRL_OFF:	.byte $1b
PORTB_OFF:			.byte $00
PORTA_OFF:			.byte $01
DDRB_OFF:			.byte $02
DDRA_OFF:			.byte $03
IFR_OFF:			.byte $0d
IER_OFF:			.byte $0e
IRQPORT_OFF:		.byte $ff



;ACIA_DATA       = $7f14
;ACIA_STATUS     = $7f15
;ACIA_CMD        = $7f16
;ACIA_CTRL       = $7f17
;KEYBDISP_DATA		=$7f18
;KEYBDISP_STATUS		=$7f19
;KEYBDISP_CMD			=$7f1a
;KEYBDISP_CTRL		=$7f1b
PORTB			=$7f00
PORTA			=$7f01
DDRB			=$7f02
DDRA			=$7f03
IFR				=$7f0d
IER				=$7f0e
IRQPORT			= $7fff

; Initialize the IO port
; modifies A, Y, flags
INIT_IO:
	ldy IER_OFF
	lda #$7f
	sta IO_BASE,Y
	eor IO_BASE,Y       ;check if IER was set to value as a check to see if device is present
	bne IO_INIT_DONE ;device not present
	lda #1
	ora DEVSTAT
	sta DEVSTAT   ; set bit 0 of device status indicator
	ldy IFR_OFF
	lda #$80
	sta IO_BASE,Y
	ldy DDRB_OFF
	lda #$ff
	sta IO_BASE,Y
	lda #$1
	ldy PORTB_OFF
	sta IO_BASE,y
IO_INIT_DONE:
	rts

	
;Initializes the serial port
; modifies A, Y, flags
INIT_SERIAL:
	ldy ACIA_STATUS_OFF
	lda #$00
	sta IO_BASE,Y
	ldy ACIA_CTRL_OFF
	lda #$1a ; N-8-1 2400 BAUD
	sta IO_BASE,Y
	eor IO_BASE,Y	;check if serial control register was set to value as a check to see if device is present
	bne SERIAL_INIT_DONE ;device not present
	lda #2
	ora DEVSTAT
	sta DEVSTAT	; set bit 1 of device status indicator
	ldy ACIA_CMD_OFF
	lda #$89 ; no parity, no echo, interrupts
	sta IO_BASE,Y

SERIAL_INIT_DONE:
	lda DEVSTAT
	ldy PORTB_OFF
	sta IO_BASE,y
	rts

;Initializes the KB_MONITOR_TERMINAL Card
; modifies A, Y, flags
INIT_DISPLAY:
	ldy KEYBDISP_STATUS_OFF
	lda #$00
	sta IO_BASE,Y
	ldy KEYBDISP_CTRL_OFF
	lda #$10 ; N-8-1 115.2K BAUD
	sta IO_BASE,Y
	eor IO_BASE,Y	;check if kb display control register was set to value as a check to see if device is present
	bne KEYBDISP_INIT_DONE	 ;device not present
	lda #4
	ora DEVSTAT
	sta DEVSTAT		; set bit 2 of device status indicator
	ldy KEYBDISP_CMD_OFF
	lda #$89 ; no parity, no echo, interrupts
	sta IO_BASE,Y

KEYBDISP_INIT_DONE:
	lda DEVSTAT
	ldy PORTB_OFF
	sta IO_BASE,y
	rts
	
; modifies A,X,Y flags
SET_UI_DEVICE:

	lda #4
	and DEVSTAT
	beq SET_SERIAL_UI
	lda KEYBDISP_CMD_OFF
	sta UI_CMD_OFF
	lda KEYBDISP_CTRL_OFF
	sta UI_CTRL_OFF
	lda KEYBDISP_DATA_OFF
	sta UI_DATA_OFF
	lda KEYBDISP_STATUS_OFF
	sta UI_STATUS_OFF
	;lda #$4
	;ldy PORTB_OFF
	;sta IO_BASE,y
	rts
SET_SERIAL_UI:
	lda ACIA_CMD_OFF
	sta UI_CMD_OFF
	lda ACIA_CTRL_OFF
	sta UI_CTRL_OFF
	lda ACIA_DATA_OFF
	sta UI_DATA_OFF
	lda ACIA_STATUS_OFF
	sta UI_STATUS_OFF
	;lda #$5
	;ldy PORTB_OFF
	;sta IO_BASE,y
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
	lda #0
    clc             ; no character
    rts


; Output a character (from the A register) to the UI interface.
;
; Modifies: flags
MONCOUT:
CHROUT:
	sta LAST_CHAR
	tya
	pha
	ldy UI_DATA_OFF
	lda LAST_CHAR
	sta IO_BASE,Y
	pha
tx_wait:
	ldy UI_STATUS_OFF
	lda IO_BASE,Y
	and #$10
	beq tx_wait
	pla
	pla
	tay
	rts

; Initialize the circular input buffer
; Modifies: flags, A
INIT_BUFFER:
                lda #0
				sta READ_PTR
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
	TYA
	PHA
    LDX IRQPORT
    LDA IRQTABLE,X
    STA TEMP_IRQ_ADDR
    INX
    LDA IRQTABLE,X
	STA TEMP_IRQ_ADDR+1
    JMP (TEMP_IRQ_ADDR)



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

IRQ0:   ; Not used
	PLA
	TAY
	PLA
	TAX
	PLA
	cli
	rti
IRQ1:  ; Not used
	PLA
	TAY
	PLA
	TAX
	PLA
	cli
	rti
IRQ2:  ;IO Card VIA
	PLA
	TAY
	PLA
	TAX
	PLA
	cli
	rti
IRQ3:      ;SERIAL in interrupt
	ldy ACIA_STATUS_OFF
	lda IO_BASE,Y
	ldy ACIA_DATA_OFF
	lda IO_BASE,Y
	jsr WRITE_BUFFER
	PLA
	TAY
	PLA
	TAX
	PLA
	cli
	rti

IRQ4:    ;IO Card I2C
	PLA
	TAY
	PLA
	TAX
	PLA
	cli
	rti
IRQ5:	; Keyboard/Display Card
	ldy KEYBDISP_STATUS_OFF
	lda IO_BASE,Y
	ldy KEYBDISP_DATA_OFF
	lda IO_BASE,Y
	jsr WRITE_BUFFER
	PLA
	TAY
	PLA
	TAX
	PLA
	cli
	rti
	
IRQ6:	;spare
	PLA
	TAY
	PLA
	TAX
	PLA
	cli
	rti
IRQ7:	;spare
	PLA
	TAY
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

