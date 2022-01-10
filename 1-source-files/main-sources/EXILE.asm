OSBYTE = &FFF4          \ The address for the OSBYTE routine
OSWRCH = &FFEE          \ The address for the OSWRCH routine
OSCLI = &FFF7           \ The address for the OSCLI routine

CODE% = &3000           \ Load address for EXILE program

ORG &70

.write
.wLo                    \ Screen memory write cursor
 SKIP 1
.wHi
 SKIP 1
.read
.rLo                    \ Compressed image data read cursor
 SKIP 1
.rHi
 SKIP 1
.count
 SKIP 1

ORG CODE%

INCBIN "loadscreen.bin" \ Compressed loading screen data

.vducodes
 EQUB &16,&05                    \ Switch to MODE 5
 EQUB &17,0,&0A,&20,0,0,0,0,0,0  \ 6845 R10 (cursor start)
 EQUB &13,1,5,0,0,0              \ Palette change logical color 1 to Magenta
 EQUB &13,2,4,0,0,0              \ Palette change logical color 2 to Blue
 EQUB &17,0,1,0,0,0,0,0,0,0      \ 6845 R1 (horizontal displayed chars)
                                 \ sets count to 0 so no text is shown on screen
 EQUB &FF                        \ End of this list
 
 SKIP 5                          \ Padding
 
 EQUB &17,0,1,&28,0,0,0,0,0,0    \ 6845 R1 (horizontal displayed chars) = 40
 EQUB &FF                        \ End of this list
 
 SKIP 5                          \ Padding

\ ******************************************************************************
\
\        Name: showLoadingScreen
\        Type: Subroutine
\     Summary: Decompresses the loading screen into screen memory. The
\              compressed data is at the top of the program.
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\ ******************************************************************************

\ The compressed data is a set of token pairs (count, data) where count is a
\ signed byte and data is either a single byte value or a run of image data
\ bytes. A positive count, N, means "write the data byte N times". A negative
\ count, -N, means "copy the following N bytes". A token pair with a count of 0
\ terminates.

.showLoadingScreen

 LDA #0                 \ MODE 5 screen memory starts at &5800
 STA wLo
 LDA #&58
 STA wHi
 
 LDA #00                \ This program is loaded at &3000, it starts with the
 STA rLo                \ compressed loading screen image data.
 LDA #&30
 STA rHi

.slsreadtoken
 LDY #0
 LDA (read),Y           \ Read the compressed image data count byte
 STA count              \ Store it away
 BNE slscont            \ If the count is not zero we continue
 RTS                    \ Finished
.slscont
 INY                    \ Advance compressed image data cursor
 TAX
 BMI slscopyinit        \ If the count is negative go to slscopyinit
                        \ A positive value, N, means write the next byte value
                        \ to screen memory N times.
 LDA (read),Y           \ Read the byte value
 DEY                    \ Decrement Y so that the screen memory cursor is
                        \ correct.
.slsrunloop
 STA (write),Y          \ Write to screen memory
 INY 
 DEX                    \ Keep looping until N values done
 BNE slsrunloop

 CLC                    \ Advance the write cursor by the run count
 LDA wLo
 ADC count
 STA wLo
 LDA wHi
 ADC #0
 STA wHi

 LDA rLo                \ Advance the read cursor to the next token (2 bytes)
 ADC #2
 STA rLo
 BNE slsreadtoken

 CLC                    \ Advance the high byte of read cursor
 LDA rHi
 ADC #1
 STA rHi
 BPL slsreadtoken       \ If bit 7 remained clear then keep looping
                        \ Top of screen memory is &7FFF and first location
                        \ after is &8000. The high byte is 80 which has bit 7
                        \ set.
 RTS                    \ Finished
.slscopyinit
                        \ A negative count indicates that N following bytes
                        \ is image data that should be copied over to the
                        \ write cursor.
 SEC                    \ Recover N, N = count - 127
 SBC #&7F
 DEY                    \ Decrement Y so that the screen memory cursor is
                        \ correct.
 TAX                    \ X=N
 INC rLo                \ Advance the read cursor by one to account for the DEY
                        \ instruction above.
.slscopyloop
 LDA (read),Y           \ Copy an image byte over
 STA (write),Y

 CLC                    \ Advance write cursor by 1 byte
 LDA wLo
 ADC #1
 STA wLo
 LDA wHi
 ADC #0
 STA wHi

 INC rLo                \ Increment low byte of read cursor.
 BEQ slsfixupreadcursor \ If low byte became zero then it overflowed and the
                        \ high byte needs updating.
.slsreadloop2
 DEX                    \ Decrement N by 1
 BNE slscopyloop        \ If N > 0 then loop back
 BEQ slsreadtoken       \ This token has been decompressed, read another one
 CLC 
.slsfixupreadcursor
 LDA rHi 
 ADC #1
 STA rHi
 LDY #0                 
 BEQ slsreadloop2       \ This is guaranteed to branch because of above
                        \ instruction.

 SKIP 15

\ ******************************************************************************
\
\        Name: sendVDUCodes
\        Type: Subroutine
\     Summary: Submits VDU codes from pre-defined list
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   Y                   Byte offset into vdu_codes (the predefined list)
\
\ ******************************************************************************

.sendVDUCodes
 LDA vducodes,Y
 BMI scodes1            \ If top-bit set then this is the end of list marker,
                        \ finished here.
 JSR OSWRCH
 INY                    \ Next byte
 BNE sendVDUCodes       \ Keep looping until Y=0
.scodes1
 RTS 

 SKIP 4
 
.start                  \ Program start
 LDA #&C8               \ Set ESCAPE/BREAK to mode 3
 LDX #&03
 LDY #&00
 JSR OSBYTE

 LDY #&00               \ Send initialize VDU commands
 JSR sendVDUCodes

 JSR showLoadingScreen

 LDY #&28               \ Send second batch of VDU commands
 JSR sendVDUCodes

 LDA #&15               \ Flush keyboard buffer
 LDX #&00
 JSR OSBYTE

 LDA #&81               \ Wait 800 centiseconds (8s) for a key to be pressed
 LDX #&20 
 LDY #&03
 JSR OSBYTE

 LDA #0
 LDY #&0F
.pagedromloop
 CPY &0DBC              \ XFILEV rom number?
 BEQ pagedromskip
 STA &02A1,Y            \ Zero out corresponding Paged ROM type
.pagedromskip
 DEY 
 BPL pagedromloop

 LDY #&18               \ Restore horizontal displayed chars count
 JSR sendVDUCodes

 LDX #LO(loadGame)      \ Load the main game
 LDY #HI(loadGame)      
 JMP OSCLI              \ JMP because we are not returning here

 SKIP 15
 
.loadGame
 EQUS "/ExileL", 13

 EQUB 0,0,0,0,0         \ Unknown use
 EQUB &11,1,&89

 EQUS "(C) 1989BEEBSOFT"

SAVE "MYEXILE", CODE%, P%, .start