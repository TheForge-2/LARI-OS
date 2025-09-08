; STRCMP:

; 'strcmp': compare two NULL-terminated strings.

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
	jne .not_equal

	; If the characters match and AL is 0x00, the strings both ended.
	test al, al
	jz .equal

	; If equal, and the string is not over, continue with the next character.
	loop .compare_characters

	; If the loop breaks, all the characters were compared and the strings are equal, so set the zero flag.
	cmp al, al ; Guarantees that ZF is set.

; If the strings are equal, return with the zero flag set.
.equal:

	; Restore the registers and return, the ZF was already set manualy or automatically.
	popa
	ret

; If the strings are not equal, return with the zero flag cleared.
.not_equal:

	; Restore the registers and return, the ZF was already cleared by a JNE.
	popa
	ret
