; Copyright © 2024-2025 TheForge-2
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; CHANGE_PAGE:

; Change the currently displayed page.

; Inputs:
; - AL = new page number (0-7).

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
