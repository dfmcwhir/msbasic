; ============================================================================
; ch376_loadsave.s - BASIC "LOAD" and "SAVE" for the Eater msbasic build,
; using the CH376 driver in ch376_abs.s (ch_init, ch_mount, ch_file_open,
; ch_file_create, ch_file_close, ch_read, ch_write ...).
;
;   LOAD "NAME"      -> reads /NAME.BAS into the BASIC program area
;   SAVE "NAME"      -> writes the current program to /NAME.BAS
;   LOAD "$"         -> lists the files in the root directory (the program in
;                       memory is NOT touched)
;   LOAD "$T*"       -> lists only matching files (the CH376's own wildcard
;                       matching, e.g. "$*.BAS" or "$GAME*")
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
ch_dir    = VARS+47                 ; non-zero: LOAD "$..." (directory listing)
ch_ent    = VARS+48                 ; 32 bytes: directory entry from the chip
ch_num    = VARS+80                 ; 4 bytes: number being printed
ch_col    = VARS+84                 ; column counter while printing a name
ch_started = VARS+85                ; leading-zero suppression flag
ch_nfiles = VARS+86                 ; 2 bytes: files listed
ch_sx     = VARS+88                 ; saved X / Y around OUTDO
ch_sy     = VARS+89
                                    ; (whole block ends at VARS+89; check it
                                    ;  stays below RAMSTART2)

CMD_FILE_ENUM_GO = $33              ; next directory entry

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
        lda ch_dir                  ; LOAD "$..." -> directory listing
        beq @file
        jmp ch_dirlist
@file:  jsr ch_prepare
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
        lda ch_dir                  ; SAVE "$..." makes no sense
        beq @ok1
        ldx #ERR_ILLQTY
        jmp ERROR
@ok1:   jsr ch_prepare
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
        sta ch_dir
        lda #'/'
        sta ch_name
        ldx #1                      ; X = index into ch_name
        ldy #0                      ; Y = index into the BASIC string
        lda (INDEX),y
        cmp #'$'
        bne @copy
        lda #1                      ; "$..." = directory request
        sta ch_dir
        sta ch_dot                  ; (so no ".BAS" is appended)
        iny                         ; skip the "$"
        cpy ch_cnt
        bne @copy                   ; "$pattern": copy the pattern
        lda #'*'                    ; plain "$": match everything
        sta ch_name,x
        inx
        bne @term                   ; always taken
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
; ch_dirlist - LOAD "$" : list the directory named by ch_name ("/*" etc.)
;
; CH376 enumeration: SET_FILE_NAME "/*", FILE_OPEN. For every match the chip
; interrupts with USB_INT_DISK_READ and the 32-byte FAT directory entry can
; be read with RD_USB_DATA0.  FILE_ENUM_GO fetches the next one; ERR_MISS_FILE
; ($42) means there are no more.
;
; Entry layout: 0-7 name, 8-10 extension (space padded), 11 attributes,
;               28-31 file size (little endian)
; ----------------------------------------------------------------------------
ch_dirlist:
        jsr ch_prepare
        bcc @ready
        lda #CH_E_NODISK
        jmp ch_fail
@ready: lda #0
        sta ch_nfiles
        sta ch_nfiles+1
        lda #<ch_name
        ldx #>ch_name
        jsr ch_set_name
        lda #CMD_FILE_OPEN
        jsr ch_cmd
@next:  jsr ch_wait_status
        cmp #USB_INT_DISK_READ      ; $1D = an entry is available
        bne @end
        lda #CMD_RD_USB_DATA0
        jsr ch_cmd
        jsr ch_rd                   ; length (normally 32)
        sta ch_cnt
        ldy #0
@rd:    cpy ch_cnt
        bcs @got
        jsr ch_rd
        cpy #32
        bcs @skip                   ; never overflow ch_ent
        sta ch_ent,y
@skip:  iny
        bne @rd
@got:   lda ch_cnt
        cmp #32
        bcc @more                   ; short entry: ignore it
        jsr ch_print_entry
@more:  lda #CMD_FILE_ENUM_GO
        jsr ch_cmd
        jmp @next
@end:   cmp #ERR_MISS_FILE          ; $42 = end of directory
        beq @done
        jmp ch_fail                 ; anything else is a real error
@done:  lda ch_nfiles
        ora ch_nfiles+1
        bne @ret
        lda #<msg_nofiles
        ldy #>msg_nofiles
        jsr STROUT
@ret:   rts                         ; back to BASIC ("OK")

; ch_print_entry - print one line for the entry in ch_ent, or nothing if it is
; a volume label / hidden / system entry
ch_print_entry:
        lda ch_ent+11
        and #$0E                    ; volume label, hidden, system
        beq @show
        rts
@show:  inc ch_nfiles
        bne @c1
        inc ch_nfiles+1
@c1:    ldy #0
@name:  lda ch_ent,y
        cmp #' '
        beq @namedone
        jsr ch_putc
        iny
        cpy #8
        bcc @name
@namedone:
        sty ch_col                  ; characters printed so far
        lda ch_ent+8
        cmp #' '
        beq @pad                    ; no extension
        lda #'.'
        jsr ch_putc
        inc ch_col
        ldy #8
@ext:   lda ch_ent,y
        cmp #' '
        beq @pad
        jsr ch_putc
        inc ch_col
        iny
        cpy #11
        bcc @ext
@pad:   lda #' '                    ; pad the name field to 13 columns
        jsr ch_putc
        inc ch_col
        lda ch_col
        cmp #13
        bcc @pad
        lda ch_ent+11
        and #$10                    ; directory?
        beq @size
        lda #<msg_dir
        ldy #>msg_dir
        jsr STROUT
        jmp @eol
@size:  ldx #3                      ; size -> ch_num
@cp:    lda ch_ent+28,x
        sta ch_num,x
        dex
        bpl @cp
        jsr ch_print_num
@eol:   jmp CRDO                    ; end of line (tail call)

; ch_print_num - print the 32-bit number in ch_num right-aligned in 10 columns
ch_print_num:
        lda #0
        sta ch_started
        ldy #0                      ; Y = 4 * index into ch_pow10
@digit: ldx #0                      ; X = this digit
@sub:   sec
        lda ch_num
        sbc ch_pow10,y
        sta ch_num
        lda ch_num+1
        sbc ch_pow10+1,y
        sta ch_num+1
        lda ch_num+2
        sbc ch_pow10+2,y
        sta ch_num+2
        lda ch_num+3
        sbc ch_pow10+3,y
        sta ch_num+3
        bcc @undo                   ; went negative: digit is complete
        inx
        jmp @sub
@undo:  clc                         ; add the power back
        lda ch_num
        adc ch_pow10,y
        sta ch_num
        lda ch_num+1
        adc ch_pow10+1,y
        sta ch_num+1
        lda ch_num+2
        adc ch_pow10+2,y
        sta ch_num+2
        lda ch_num+3
        adc ch_pow10+3,y
        sta ch_num+3
        lda ch_started
        bne @pr
        txa
        bne @pr
        cpy #36                     ; last digit is always printed
        beq @pr
        lda #' '                    ; leading zero -> space
        jmp @out
@pr:    lda #1
        sta ch_started
        txa
        clc
        adc #'0'
@out:   jsr ch_putc
        tya
        clc
        adc #4
        tay
        cpy #40
        beq @fin
        jmp @digit
@fin:   rts

ch_pow10:
        .dword 1000000000, 100000000, 10000000, 1000000, 100000
        .dword 10000, 1000, 100, 10, 1

; ch_putc - OUTDO that preserves X and Y
ch_putc:
        stx ch_sx
        sty ch_sy
        jsr OUTDO
        ldx ch_sx
        ldy ch_sy
        rts

msg_dir:     .byte "     <DIR>",0
msg_nofiles: .byte "NO FILES",13,10,0

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
