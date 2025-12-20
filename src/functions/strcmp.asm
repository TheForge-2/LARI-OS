; Copyright © 2024-2025 TheForge-2
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; STRCMP:

; Compare two NULL-terminated strings.

; Inputs:
; - SI = address of the first string;
; - DI = address of the second string;
; - BX = number of characters to compare (0 for a 64KiB segment).

; Outputs:
; - ZF = 1 if the strings are equal, 0 if not.
; - All registers are preserved.

strcmp:

	; Save the registers, clear the direction flag and set up the counter (CX).
	pusha
	cld
	mov cx, bx

; Loop for comparing the ASCII characters in SI and DI.
.compare_characters:

	; Load the byte at SI in AL (can't CMP m/m) and increment SI.
	lodsb

	; Compare the character with the one at DI and increment DI, break if not equal.
	scasb
	jne .done ; If it breaks, the ZF is clear.

	; If the characters match and AL is 0x00, the strings both ended.
	test al, al
	jz .done ; If it breaks, the ZF is set.

	; If equal, and the string is not over, continue with the next character.
	loop .compare_characters

	; If the loop breaks, all the requested characters were compared and found to be equal, so set the zero flag.
	cmp al, al ; Guarantees that ZF is set.

; Whether the strings are equal or not, the zero flag has already been toggled by the previous code.
.done:

	; Restore the registers and return.
	popa
	ret
