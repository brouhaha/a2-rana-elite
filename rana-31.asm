; Reverse-engineered firmware of Rana Elite floppy disk
; controller for Apple II.

; Assembly source code copyright 2014, 2016 Eric Smith <spacewar@gmail.com>
; The author of this assembly source code does not claim copyright on the
; executable object code as found in the EPROM chip of the Rana Elite
; floppy disk controller.

; Cross-assemble with Macro Assembler AS:
;   http://john.ccac.rwth-aachen.de:8000/as/

fillto	macro	endaddr,value,{noexpand}
	ifnb	value
v	set	value
	else
v	set	$00
	endif
	while	*<endaddr
	if	(endaddr-*)>1024
	fcb	[1024] v
	else
	fcb	[endaddr-*] v
	endif
	endm
	endm

fcstrm	macro	s
	irpc	c,s
	fcb	'c'|$80
	endm
	endm


Z00	equ	$00
bufptr	equ	$26
denib_counter	equ	$2a
slot16	equ	$2b
temp	equ	$3c
sector	equ	$3d
Z40	equ	$40
Z41	equ	$41

D0100	equ	$0100

D02d6	equ	$02d6

D0300	equ	$0300
L0301	equ	$0301
D0356	equ	$0356

tramp_0801	equ	$0376	; trampoline for 16-sector boot

D0399	equ	$0399
D03c6	equ	$03c6
D03c7	equ	$03c7
D03cc	equ	$03cc
D03ce	equ	$03ce

D0800	equ	$0800	; 16-sector boot: additional sector count
L0801	equ	$0801	; 16-sector boot: jump address

tramp_0301	equ	$08e0	; trampoline for 13-sector boot
D08e3	equ	$08e3
D08e6	equ	$08e6
D08e7	equ	$08e7

; Woz controller addresses (index by slot * 16)
phoff	equ	$c080	; phase off
phon	equ	$c081	; phase on
mtroff	equ	$c088	; motor off
mtron	equ	$c089	; motor on
drv0en	equ	$c08a	; drive 0 enable
drv1en	equ	$c08b	; drive 1 enable
q6l	equ	$c08c	; set Q6 low
q6h	equ	$c08d	; set Q6 high
q7l	equ	$c08e	; set Q7 low
q7h	equ	$c08f	; set Q7 high

seld12	equ	$c800	; write to select drive bank for drives 1 and 2
seld34	equ	$c801	; write to select drive bank for drives 3 and 4
romoff	equ	$cfff	; access to turn off shared ROM

monwait	equ	$fca8	; monitor wait subroutine

	org	$c800

	fillto	$cc00

Lcc00:	jmp	Lcde2

; build 13-sector denibblization table - D0800[nib] = 5-bit data
; starting with ($08ff) = $1f, and descending to ($08ab) = $00
; duplicates code in Apple 13-sector boot ROM stating at Cx00
Lcc03:	ldx	#$20
	ldy	#$00
Lcc07:	lda	#$03
	sta	temp
	clc
	dey
	tya
Lcc0e:	bit	temp
	beq	Lcc07
	rol	temp
	bcc	Lcc0e

	cpy	#$d5		; skip $d5, used for marks
	beq	Lcc07

	dex			; Y is a valid nibble, set table[Y] to index
	txa
	sta	D0800,y
	bne	Lcc07

; Copy two instruction trampoline (six bytes) from tramp_0301_rom to tramp_0301.
Lcc21:	ldy	#tramp_0301_len-1
Lcc23:	lda	tramp_0301_rom,y
	sta	tramp_0301,y
	dey
	bpl	Lcc23

	lda	#$40
	sta	D08e6
	lda	#$03
	sta	bufptr+1
	lda	#$ff
	sta	D0300
	sta	D08e7
	ldx	slot16

Lcc3f:	ldy	D08e6
	iny
	beq	read_sector_13
	dec	D08e6
	beq	Lcc00

read_sector_13:
	clc			; flag clear, look for address mark
read_something_13:
	php			; save flag

; read first byte of mark
Lcc4c:	lda	q6l,x		; read disk
	bpl	Lcc4c
Lcc51:	eor	#$d5		; first byte of mark?
	bne	Lcc4c		;   no

; read second byte of mark
Lcc55:	lda	q6l,x
	bpl	Lcc55
	cmp	#$aa
	bne	Lcc51
	nop

; read third byte of mark
Lcc5f:	lda	q6l,x
	bpl	Lcc5f
	cmp	#$b5		; address mark?
	beq	found_address_mark_13

	plp			; retrieve flag - looking for address mark?
	bcc	Lcc3f		;   yes, try again

; check for a data mark
	eor	#$ad
	beq	found_data_mark_13
	bne	Lcc3f
found_address_mark_13:
	ldy	#$03		; read volume, track, sector
				;   volume and track ignored, presumed OK
				;   checksum not read

Lcc73:	lda	q6l,x
	bpl	Lcc73
	rol			; save upper slice
	sta	temp

Lcc7b:	lda	q6l,x
	bpl	Lcc7b
	and	temp		; merge slices
	dey			; 3rd byte yet?
	bne	Lcc73		;   no, get another

	plp			; throw away flag

	cmp	sector		; correct sector?
	bne	Lcc3f		;   no, get another
	bcs	read_something_13	;   yes. carry is set, go back and look for data mark

found_data_mark_13:
; read 154 nibbles, denibblize with running xor,
; and store from $0899 down to $0800
	ldy	#$9a
Lcc8e:	sty	temp
Lcc90:	ldy	q6l,x
	bpl	Lcc90
	eor	D0800,y
	ldy	temp
	dey
	sta	D0800,y
	bne	Lcc8e

; Y now zero
; read 256 nibbles, denibblize with running xor,
; and store in buffer in ascending order
Lcca0:	sty	temp
Lcca2:	ldy	q6l,x
	bpl	Lcca2
	eor	D0800,y
	ldy	temp
	sta	(bufptr),y
	iny
	bne	Lcca0

; read checksum nibble, xor, and verify zero
Lccb1:	ldy	q6l,x
	bpl	Lccb1
	eor	D0800,y
	bne	Lcc3f			; checksum fail?

	lda	D08e7
	beq	Lcced

	lda	#$03
	sta	denib_counter

; special 13-sector boot sector denibblize, equivalent to
; 13-sector boot ROM code at $cnd1
	ldy	#$00
Lccc6:	ldx	#$00

Lccc8:	lda	D0800,y
	lsr
	rol	D03cc,x
	lsr
	rol	D0399,x
	sta	temp

	lda	(bufptr),y		; merge in the extra bits
	asl
	asl
	asl
	ora	temp
	sta	(bufptr),y

	iny
	inx
	cpx	#$33
	bne	Lccc8

	dec	denib_counter
	bne	Lccc6

	cpy	D0300
	bne	Lccf0

Lcced:	jmp	tramp_0301		; jump via trampoline to $0301

Lccf0:	jmp	Lcde2

; The following two instruction trampoline (six bytes) is copied to tramp_0301
; by loop at Lcc21.
tramp_0301_rom:
	bit	romoff	; turn off shared ROM
	jmp	L0301	; jump into 13-sector stage 2 boot
tramp_0301_len	equ	*-tramp_0301_rom

	fillto	$cd00

Scd00:	jsr	Scd4e
	ldx	slot16
	lda	#$40
	sta	D03ce
	lda	#$00
	sta	bufptr
	sta	sector
	sta	Z41
	lda	#$08
	sta	bufptr+1
	rts

Scd17:	tsx
	inx
	inx
	lda	D0100,x
	asl
	asl
	asl
	asl
	sta	slot16
	tax

	sta	seld12		; select drive bank for drives 1 and 2

	lda	q7l,x		; set up to read drive
	lda	q6l,x
	lda	drv0en,x
	lda	mtron,x

	jsr	Scd00

; move to track 0 (assume worst case
; initial position of track 40)

	ldy	#80		; 80 half tracks
Lcd38:	lda	phoff,x		; stepper motor phase off
	tya			; compute next phase
	and	#$03		; yields 3,2,1,0
	asl			; yields 6,4,2,0
	ora	slot16		; merge with slot*16
	tax
	lda	phon,x		; stepper motoro phase on		
	lda	#$56		; wait (13 sector boot rom had $86)
	jsr	monwait
	dey
	bpl	Lcd38
	rts

; generate 16-sector post-nybble conversion table
; From 16-sector boot ROM, c602..??
; See 16-sector ROM disassembly in Apple Assembly Line V1N11, August 1981
Scd4e:	ldx	#$03
	ldy	#$00
Lcd52:	stx	temp
	txa
	asl
	bit	temp
	beq	Lcd6a
	ora	temp
	eor	#$ff
	and	#$7e
Lcd60:	bcs	Lcd6a
	lsr
	bne	Lcd60
	tya
	sta	D0356,x
	iny
Lcd6a:	inx
	bpl	Lcd52

; Copy two instruction trampoline (six bytes) from tramp_0801_rom to tramp_0801.
Lcd6d:	ldy	#tramp_0801_len-1
Lcd6f:	lda	tramp_0801_rom,y
	sta	tramp_0801,y
	dey
	bpl	Lcd6f

	lda	#$40
	sta	D03ce

Scd7d:	ldy	#$55
	lda	#$00
Lcd81:	sta	D0300,y
	dey
	bpl	Lcd81
	rts

Lcd88:	bcs	Lcda1
	lda	#$ff
	sta	D03ce
	lda	#Lc64c & $ff
Lcd91:	sta	D03c6
	txa
	lsr
	lsr
	lsr
	lsr
	ora	#$c0
	sta	D03c7
	jmp	(D03c6)
Lcda1:	jmp	tramp_0801

; The following two instruction trampoline (six bytes) is copied to tramp_0801
; by loop at Lcd6d.
tramp_0801_rom:
	bit	romoff	; turn off shared ROM
	jmp	L0801	; jump into 16-sector stage 2 boot
tramp_0801_len	equ	*-tramp_0801_rom

Scdaa:	lda	#$00
	ldy	#$55
Lcdae:	ora	D0300,y
	dey
	bpl	Lcdae
	and	#$f0
	bne	Lcdbe
	lda	#$ff
	sta	D03ce
	rts

Lcdbe:	pla
	pla
	pla
	ldy	#$60
	sty	D08e3
	ldy	#$00
	sty	D08e7
	dey
	sty	D08e6
	jmp	read_sector_13

Scdd2:	ldy	D03ce
	iny
	beq	Lcddd
	dec	D03ce
	beq	Lcddf
Lcddd:	clc
	rts

Lcddf:	jmp	Lcc03

Lcde2:	jsr	Scd00
	lda	#$25
	bne	Lcd91

	fillto	$cec2
	fcb	"COPYR. 1982 RANA SYSTEMS - KSB"

	fcstrm	"COPYR. 1982 RANA SYSTEMS - KSB"

	fcb	$01,$03

	org	$cf00
	phase	$c600

Pc600:	ldx	#$20
	ldy	#$00
	ldx	#$03
	ldx	#$3c
	bit	romoff
	jsr	Scd17
	bne	Lc625

Lc610:	bit	romoff
	jsr	Scdaa
	bne	Lc627
Lc618:	jsr	Scdd2
	bcc	Lc625

	fcb	$00,$00,$00,$00,$00
	
Lc622:	jsr	Scd7d
Lc625:	clc
Lc626:	php
Lc627:	lda	q6l,x
	bpl	Lc627
Lc62c:	eor	#$d5		; first byte of mark
	bne	Lc627
Lc630:	lda	q6l,x
	bpl	Lc630
	cmp	#$aa		; second byte of mark
	bne	Lc62c
	nop
Lc63a:	lda	q6l,x
	bpl	Lc63a
	cmp	#$96		; third byte of address mark (16-sector)
	beq	Lc683
	plp
	bcc	Lc618
	eor	#$ad		; third byte of data mark
	beq	Lc6a6
	bne	Lc618

Lc64c:	ldy	D03ce
	iny
	beq	Lc622
	dec	D03ce
	bne	Lc622
	jmp	Lcddf
	
; DOS 3.3 boot reenters the PROM via jmp to $Cn5C 
; DOS 3.2.1 boot reenters the PROM via jsr (effectively) to $Cn5D
	fillto	$c65c
Pc65c:	clc
Pc65d:	php
	sec
	bcs	Lc610

	bpl	Lc627
Lc663:	eor	#$d5		; first byte of mark
	bne	Lc627
Lc667:	lda	q6l,x
	bpl	Lc667
	cmp	#$aa		; second byte of mark
	bne	Lc663
	nop
Lc671:	lda	q6l,x
	bpl	Lc671
	cmp	#$96		; third byte of address mark
	beq	Lc683
	plp
	bcc	Lc618
	eor	#$ad		; third byte of data mark
	beq	Lc6a6

Lc681:	bne	Lc618
Lc683:	ldy	#$03
Lc685:	sta	Z40
Lc687:	lda	q6l,x
	bpl	Lc687
	rol
	sta	temp
Lc68f:	lda	q6l,x
	bpl	Lc68f
	and	temp
	dey
	bne	Lc685
	plp
	cmp	sector
	bne	Lc681
	lda	Z40
	cmp	Z41
Lc6a2:	bne	Lc64c
	bcs	Lc626
Lc6a6:	ldy	#$56
Lc6a8:	sty	temp
Lc6aa:	ldy	q6l,x
	bpl	Lc6aa
	eor	D02d6,y
	ldy	temp
	dey
	sta	D0300,y
	bne	Lc6a8
Lc6ba:	sty	temp
Lc6bc:	ldy	q6l,x
	bpl	Lc6bc
	eor	D02d6,y
	ldy	temp
	sta	(bufptr),y
	iny
	bne	Lc6ba
Lc6cb:	ldy	q6l,x
	bpl	Lc6cb
	eor	D02d6,y
	bne	Lc6a2
	ldy	#$00
Lc6d7:	ldx	#$56
Lc6d9:	dex
	bmi	Lc6d7
	lda	(bufptr),y
	lsr	D0300,x
	rol
	lsr	D0300,x
	rol
	sta	(bufptr),y
	iny
	bne	Lc6d9
	inc	bufptr+1
	inc	sector
	lda	sector
	cmp	D0800
	ldx	slot16
	nop
	nop
	bit	romoff
	jmp	Lcd88

	fillto	$c700

	dephase
