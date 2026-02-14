; Copyright © 2024-2026 Alessandro Meles (TheForge-2)
; This file is part of the LARI OS project.
; Use is restricted to personal, non-commercial, educational and experimental purposes only.
; See 'LICENSE.txt' in the project root for full terms.




; RTC_READ:

; Read the contents of RTC time and date registers.
; Store the results in a 6-byte structure, which must not cross a segment boundary.

; Inputs:
; - ES:DI = address of structure where to store read data (with DI <= 65530).

; Outputs:
; - ES:[DI] = read register data;
; - All registers are preserved.

rtc_read:

	; Save the registers.
	pusha
	push di ; Save the DI register (which contains the function input), as it will be used.

; Try to get two coherent consecutive reads; fallback to the safe method as soon as an update is detected.
.fast_try:

	; Check whether an update is in progress.
	call .check_uip
	jnz .wait_end_update ; If yes, wait for it to finish.

	; Perform the first read.
	mov di, .buffer_1
	call .read_registers

	; Check for UIP again.
	call .check_uip
	jnz .wait_end_update

	; Perform the second read.
	call .read_registers ; DI already points to the second buffer.

; Comapre the two reads stored in buffers 1 and 2; fallback to the safe method as soon as two different values are detected.
.compare_buffers:

	; Set up the source (SI), the destination (DI) and the counter (CX).
	mov si, .buffer_1
	mov di, .buffer_2
	mov cx, 6 ; The buffers are 6 bytes long.

	; Compare the two sets of values.
	cld ; Clear the direction flag, to assure SI and DI are incremented.
	repe cmpsb
	je .convert ; If they are equal, then proceed to process the data.

; Wait for the update in progress to finish.
.wait_end_update:

	call .check_uip
	jnz .wait_end_update

; Begin reading the registers as soon as the update is over.
.safe_try:

	mov di, .buffer_1
	call .read_registers

; After a valid set of data has been read, convert it into the standard format.
.convert:

	; Check whether the values are in BCD or binary.
	test byte [cmos_status_b], 0x04 ; Check status register B bit 2 (binary form).
	jnz .hour_format ; If they are already in binary, skip over the conversion.

	; Strip the PM bit (bit 7) from the hours value and save it in BL.
	mov bl, [.buffer_1 + 2]
	and bl, 0x80
	and byte [.buffer_1 + 2], 0x7F

; Convert the numbers from BCD to binary (the standard data format).
.data_format:

	; Set up the source (SI), the destination (DI) and the counter (CX).
	mov si, .buffer_1
	mov di, si ; To save the converted values.
	mov cx, 6

; Loop for converting one value at a time to binary.
.convert_to_bin:

	; Load each value to AL, then call the BCD to binary convertion function.
	cld ; Clear the direction flag, for safety.
	lodsb
	call bcd_to_bin
	stosb

	; Loop again if not all 6 values were converted.
	loop .convert_to_bin

.hour_format:

	; Check whether the hours value is in 12-hour or 24-hour format.
	test byte [cmos_status_b], 0x02 ; Check status register B bit 1 (24-hour mode).
	jnz .transfer ; If it is already in 24h, skip over the conversion.

	; Get the hours value to modulo 12.
	movzx ax, byte [.buffer_1 + 2]
	mov cl, 12
	div cl ; The remainder (modulo) is stored in AH.
	mov [.buffer_1 + 2], ah ; Save it to the buffer.

	; If the PM bit is set, add 12, else leave as-is.
	; The two edge cases, midnight (12AM) and noon (12PM) are handled correctly:
	; they got both reduced to 0 by the modulo 12 and only 12PM is incremented by 12.
	cmp bl, 0x00
	jz .transfer ; If the time was AM, don't add 12 (12AM stays 00).
	add byte [.buffer_1 + 2], 12 ; Else add 12 (12PM becomes 12).

; Transfer the valid and correctly formatted values from buffer 1 to the caller-provided structure.
.transfer:

	; Set up the source (SI), the destination (DI) and the counter (CX).
	mov si, .buffer_1
	pop di
	mov cx, 6

	; Transfer the buffer (while keeping interrupts temporarily disabled, to avoid exposing half-updated data).
	cld ; Clear the direction flag, for safety.
	cli
	rep movsb
	sti

; Restore the registers and return.
.done:

	popa
	ret

; Internal subfunction, for reading the RTC registers one at a time and storing them in the structure at DI.
.read_registers:

	mov al, 0x00 ; Seconds.
	call cmos_read
	stosb
	mov al, 0x02 ; Minutes.
	call cmos_read
	stosb
	mov al, 0x04 ; Hours.
	call cmos_read
	stosb
	mov al, 0x07 ; Day.
	call cmos_read
	stosb
	mov al, 0x08 ; Month.
	call cmos_read
	stosb
	mov al, 0x09 ; Year.
	call cmos_read
	stosb ; DI is incremented, so it already points to buffer 2 (if it was storing to buffer 1).
	ret

; Internal subfunction, for checking whether an update is in progress (UIP flag at bit 7 of status register A).
.check_uip:

	mov al, 0x0A
	call cmos_read
	and al, 0x80 ; Keep only bit 7 (UIP).
	ret

; Define two buffers for intermediate reads
.buffer_1: times 6 db 0x00 ; Reserve 6 bytes (seconds, minutes, hours, day, month, year).
.buffer_2: times 6 db 0x00 ; Same as buffer 1.

; END OF RTC_READ.
