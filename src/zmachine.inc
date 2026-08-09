; Z-machine shared ZP / constants (v5)

; Operand type codes
ZTYPE_LARGE = 0
ZTYPE_SMALL = 1
ZTYPE_VAR   = 2
ZTYPE_OMIT  = 3

; Max operands / stack
Z_MAX_OPS   = 8
Z_STACK_MAX = 128          ; words in eval stack (internal RAM)

; z_waiting_input modes (0 = not waiting)
ZWAIT_AREAD = 1
ZWAIT_CHAR  = 2

; ZSCII cursor / control (for read_char / HINT)
ZSCII_UP    = 129
ZSCII_DOWN  = 130
ZSCII_LEFT  = 131
ZSCII_RIGHT = 132
ZSCII_ESC   = 27
ZSCII_RET   = 13
