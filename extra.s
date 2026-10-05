.segment "EXTRA"

.ifdef ISA6502
	.include "bios.s"
	.include "ch376_loadsave.s" 
	.include "ch376_abs.s"

;.include "isa6502_extra.s"
.endif
