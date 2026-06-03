; configuration
CONFIG_2A := 1
;CONFIG_EASTER_EGG := 1
CONFIG_SCRTCH_ORDER := 2

; zero page
ZP_START0 = $00
ZP_START1 = $03
ZP_START2 = $0D
ZP_START3 = $63
ZP_START4 = $6E

; extra/override ZP variables
USR				:= GORESTART ; XXX

; constants
SPACE_FOR_GOSUB := $3E
STACK_TOP		:= $FA
WIDTH			:= 40
WIDTH2			:= 30
RAMSTART2		:= $0403
