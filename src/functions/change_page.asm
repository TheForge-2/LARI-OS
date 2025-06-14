; CHANGE_PAGE:

; 'change_page': change the currently displayed page.

; Inputs:
; - AL = new page number.

; Outputs nothing, all registers are preserved.

change_page:

	; Save the registers.
	pusha

	; Change the page to the one in AL.
	mov ah, 0x05
	int 0x10

	; Update the displayed page number.
	mov [displayed_page], al

	; Restore the registers and return.
	popa
	ret

; END OF CHANGE_PAGE.
