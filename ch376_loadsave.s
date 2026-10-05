; ============================================================================
; ch376_loadsave.s - BASIC "LOAD" and "SAVE" for the Eater msbasic build,
; using the CH376 driver in ch376_abs.s (ch_init, ch_mount, ch_file_open,
; ch_file_create, ch_file_close, ch_read, ch_write ...).
;
;   LOAD "NAME"      -> reads /NAME.BAS into the BASIC program area
;   SAVE "NAME"      -> writes the current program to /NAME.BAS
;
;   - The name is any string expression, converted to UPPERCASE.
;   - ".BAS" is appended if the name contains no ".".
;   - A leading "/" is added for you (root directory). "DIR/NAME" works too.
;   - File format = BASIC's in-memory tokenised program (TXTTAB..VARTAB-1).
;
; HOW BASIC CALLS US
;   token.s lists  keyword_rts "LOAD", LOAD  /  keyword_rts "SAVE", SAVE,
;   so the statement dispatcher RTS-jumps to LOAD/SAVE with TXTPTR just past
;   the keyword. We parse the argument with FRMEVL (like LCDPRINT does) and
;   finish with RTS (SAVE) or by re-linking the program and returning to the
;   prompt (LOAD), exactly like the other *_loadsave.s files.
;
; INTEGRATION (bios.s)
;   1. Delete the two stubs   LOAD: rts   and   SAVE: rts
;   2. In their place add:    .include "ch376_abs.s"       ; the driver
;                             .include "ch376_loadsave.s"  ; this file
;      (the driver must NOT contain the demo / RODATA / BSS segments)
;   3. Call  jsr CH_BOOT  once at reset (e.g. next to jsr INIT_BUFFER).
;      The CH376 itself is initialised lazily on the first LOAD/SAVE.
; ============================================================================

.segment "BIOS"

CH_NAME_MAX = 26                    ; longest name typed by the user

; --- extra variables, continuing the block at VARS ($0417) from ch376_abs.s
; (ch_off uses VARS+9..VARS+12)
ch_name   = VARS+13                 ; 32 bytes: "/NAME.BAS",0
ch_ready  = VARS+45                 ; 0 = CH376 not initialised / mounted
ch_dot    = VARS+46                 ; non-zero if the name contained a "."
                                    ; (whole block ends at $0445)

; --- private failure codes (CH376 codes are all < $F0)
CH_E_TOOBIG  = $F0
CH_E_BADFILE = $F1
CH_E_NODISK  = $F2

; continue if A = USB_INT_SUCCESS, otherwise jump to "target" with A intact
.macro CH_OK target
        .local ok
        cmp #USB_INT_SUCCESS
        beq ok
        jmp target
ok:
.endmacro

; ----------------------------------------------------------------------------
; CH_BOOT - call once at power-up/reset
; ----------------------------------------------------------------------------
CH_BOOT:
        lda #0
        sta ch_ready
        rts

; ----------------------------------------------------------------------------
; LOAD "name"
; ----------------------------------------------------------------------------
LOAD:
        jsr ch_get_filename
        jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #<ch_name
        ldx #>ch_name
        jsr ch_file_open            ; $42 = file not found
        CH_OK ch_fail

        sec                         ; ch_len = MEMSIZ - TXTTAB (room available)
        lda MEMSIZ
        sbc TXTTAB
        sta ch_len
        lda MEMSIZ+1
        sbc TXTTAB+1
        sta ch_len+1
        lda TXTTAB                  ; destination = start of program
        sta ch_ptr
        lda TXTTAB+1
        sta ch_ptr+1
        jsr ch_read
        CH_OK ch_fail_close

        lda ch_got+1                ; got >= room?  -> file did not fit
        cmp ch_len+1
        bcc @fits
        bne @toobig
        lda ch_got
        cmp ch_len
        bcc @fits
@toobig:
        lda #CH_E_TOOBIG
        jmp ch_fail_close
@fits:  lda ch_got+1                ; a program is at least 2 bytes ($00 $00)
        bne @sizeok
        lda ch_got
        cmp #2
        bcs @sizeok
        lda #CH_E_BADFILE
        jmp ch_fail_close
@sizeok:
        lda #0
        jsr ch_file_close
        lda ch_ptr                  ; ch_read advanced ch_ptr to end of data
        sta VARTAB
        lda ch_ptr+1
        sta VARTAB+1
        jsr STKINI                  ; clean stack, we are not returning
        jmp FIX_LINKS               ; relink lines, CLEAR vars, back to prompt

; ----------------------------------------------------------------------------
; SAVE "name"
; ----------------------------------------------------------------------------
SAVE:
        jsr ch_get_filename
        jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #<ch_name
        ldx #>ch_name
        jsr ch_file_create          ; creates / replaces the file
        CH_OK ch_fail

        sec                         ; ch_len = VARTAB - TXTTAB
        lda VARTAB
        sbc TXTTAB
        sta ch_len
        lda VARTAB+1
        sbc TXTTAB+1
        sta ch_len+1
        lda TXTTAB                  ; source = start of program
        sta ch_ptr
        lda TXTTAB+1
        sta ch_ptr+1
        jsr ch_write
        CH_OK ch_fail_close

        lda #1                      ; close AND update the file length
        jsr ch_file_close
        CH_OK ch_fail
        rts                         ; back to BASIC

; ----------------------------------------------------------------------------
; ch_get_filename - evaluate the string argument, build "/NAME.BAS",0 in
;                   ch_name. Raises normal BASIC errors for bad arguments.
; ----------------------------------------------------------------------------
ch_get_filename:
        jsr FRMEVL
        bit VALTYP
        bmi @isstr
        ldx #ERR_BADTYPE            ; ?TYPE MISMATCH
        jmp ERROR
@isstr: jsr FREFAC                  ; A = length, (INDEX) -> characters
        sta ch_cnt
        beq @bad
        cmp #CH_NAME_MAX+1
        bcc @ok
        ldx #ERR_STRLONG            ; ?STRING TOO LONG
        jmp ERROR
@bad:   ldx #ERR_ILLQTY             ; empty name -> ?ILLEGAL QUANTITY
        jmp ERROR
@ok:    lda #0
        sta ch_dot
        lda #'/'
        sta ch_name
        ldx #1                      ; X = index into ch_name
        ldy #0                      ; Y = index into the BASIC string
@copy:  lda (INDEX),y
        cmp #'.'
        bne @upper
        lda #1
        sta ch_dot
        lda #'.'
        bne @store                  ; always taken
@upper: cmp #'a'
        bcc @store
        cmp #'z'+1
        bcs @store
        and #$DF                    ; to uppercase
@store: sta ch_name,x
        inx
        iny
        cpy ch_cnt
        bne @copy
        lda ch_dot
        bne @term
        ldy #0                      ; no "." typed: append ".BAS"
@ext:   lda ch_ext,y
        sta ch_name,x
        inx
        iny
        cpy #4
        bne @ext
@term:  lda #0
        sta ch_name,x
        rts

ch_ext: .byte ".BAS"

; ----------------------------------------------------------------------------
; ch_prepare - make sure the CH376 is initialised and the disk is mounted
;   out: carry clear = ready, set = no disk
; ----------------------------------------------------------------------------
ch_prepare:
        lda ch_ready
        bne @ok
        jsr ch_init
        bcs @fail
        jsr ch_mount
        bcs @fail
        lda #1
        sta ch_ready
@ok:    clc
        rts
@fail:  sec
        rts

; ----------------------------------------------------------------------------
; Error exits.  A = CH376 status or one of the CH_E_ codes.
; Prints a message, resets the stack and returns to the BASIC prompt.
; ----------------------------------------------------------------------------
ch_fail_close:                      ; same, but close the open file first
        pha
        lda #0
        jsr ch_file_close
        pla
ch_fail:
        cmp #ERR_MISS_FILE
        beq @nofile
        cmp #ERR_DISK_FULL
        beq @full
        cmp #CH_E_TOOBIG
        beq @toobig
        cmp #CH_E_BADFILE
        beq @badfile
        cmp #CH_E_NODISK
        beq @nodisk
        lda #0                      ; anything else: re-initialise next time
        sta ch_ready
        lda #<msg_io
        ldy #>msg_io
        jmp @print
@nofile:  lda #<msg_nofile
          ldy #>msg_nofile
          jmp @print
@full:    lda #<msg_full
          ldy #>msg_full
          jmp @print
@toobig:  lda #<msg_toobig
          ldy #>msg_toobig
          jmp @print
@badfile: lda #<msg_badfile
          ldy #>msg_badfile
          jmp @print
@nodisk:  lda #<msg_nodisk
          ldy #>msg_nodisk
@print: jsr STROUT                  ; print string at (Y,A)
        jsr STKINI
        jmp RESTART

msg_nofile:  .byte 13,10,"?FILE NOT FOUND",0
msg_full:    .byte 13,10,"?DISK FULL",0
msg_toobig:  .byte 13,10,"?FILE TOO LARGE",0
msg_badfile: .byte 13,10,"?BAD FILE",0
msg_nodisk:  .byte 13,10,"?NO DISK",0
msg_io:      .byte 13,10,"?DISK ERROR",0
