; Copyright © 2024-2026 Alessandro Meles (TheForge-2)
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; BCD_TO_BIN:

; Convert a BCD (byte coded decimal) 8-bit number back to binary.

; Inputs:
; - AL = BCD number.

; Outputs:
; - AL = number after binary conversion.

bcd_to_bin:

	; Save the registers that will be used.
	push cx
	push dx
	push bx
	mov bl, ah ; Temporarily save the contents of AH.

	; Convert from BCD to binary using the following formula:
	; BIN = (BCD / 16) * 10 + BCD & 0x0F
	mov ah, al ; Copy the BCD value to AH.
	and al, 0x0F ; Keep the units (lower 4 bits).
	shr ah, 4 ; Shift the higher 4 bits right by 4 places (same as dividing by 16).
	movzx cx, ah ; Move AH to CX (zero extend).
	mov dx, 10 ; Set up the divisor to 10.
	imul cx, dx ; Multiply the higher 4 bits by 10 to get the tens.
	add al, cl ; Add the tens to the units to get the binary expression.

	; Rostore the used registers and return.
	mov ah, bl
	pop bx
	pop dx
	pop cx
	ret
