; Copyright © 2024-2026 Alessandro Meles (TheForge-2)
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; CMOS_READ:

; Read the contents of a CMOS register.

; Inputs:
; - AL = register address.

; Outputs:
; - AL = read register contents.

cmos_read:

	; Save the registers that will be used.
	push bx

	; Preserve the current state of the NMI bit on port 0x70.
	and al, 0x7F ; Remove bit 7 (NMI) from the input value.
	push ax ; Save the register address.
	in al, 0x70 ; Take the last input on the CMOS address port.
	and al, 0x80 ; Keep only bit 7 (NMI).
	pop bx ; Restore the register address.
	or al, bl ; Combine the two sets of bits in AL

	; Read the CMOS register.
	out 0x70, al ; Output the register address to port 0x70.
	in al, 0x71 ; Read the register contents from port 0x71 to AL.

	; Restore the used registers (AH was not modified and AL is used as output) and return.
	pop bx
	ret

; END OF CMOS_READ.
