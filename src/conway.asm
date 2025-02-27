; Conway II
; Lee W. Fastenau
; thelbane@gmail.com
; Created 03/14/2017

                processor 6502
                incdir "include"
                include "apple2.asm"
                include "macros.asm"

; ------------------------------------
; Build Options
; ------------------------------------
 
NOISY           equ 0                           ; 0 = Sound off, 1 = Sound on
CHARSET         equ 0                           ; 0 = Olde Skoole, 1 = Pixel, 2 = Inverse, 3 = Small O's, 4 = Enhanced
INIT_PATTERN    equ 1                           ; 0 = Glider gun, 1 = "Random", 2 = Edge test
TEST_PERF       equ 0                           ; 0 = Normal, 1 = Instrument for emulator cycle counting (forces Glider gun layout and sound off)

; ------------------------------------
; Constants
; ------------------------------------

soundEnabled    equ NOISY && !TEST_PERF
initialPattern  equ INIT_PATTERN - [TEST_PERF * INIT_PATTERN]

textRow         equ ZPA0
textRowH        equ ZPA1

mainData        equ ZPC0
mainDataH       equ ZPC1

altData         equ ZPC2
altDataH        equ ZPC3

currentPage     equ ZPA2
temp            equ ZPA3

fieldWidth      equ 40
fieldHeight     equ 24

dataWidth       equ fieldWidth+2
dataHeight      equ fieldHeight+2

;normalText      equ %10000000                   ; 'X | normalText
inverseText     equ %00111111                   ; 'X & inverseText

                if CHARSET == 0
charOn          equ '@ ;| normalText
charOff         equ '  ;| normalText
                endif

                if CHARSET == 1
charOn          equ '  & inverseText
charOff         equ '  | normalText
                endif

                if CHARSET == 2
charOn          equ '  | normalText
charOff         equ ': & inverseText
                endif

                if CHARSET == 3
charOn          equ 'o | normalText
charOff         equ '  | normalText
                endif

                if CHARSET == 4
charOn          equ $ff ; | normalText
charOff         equ '  | normalText
                endif

n_offset        equ dataWidth+1                 ; Alt data topleft offset from current cell

y_topleft       equ 0                           ; Alt data pointer offsets
y_top           equ 1
y_topright      equ 2
y_left          equ dataWidth
y_right         equ dataWidth+2
y_bottomleft    equ dataWidth*2
y_bottom        equ dataWidth*2+1
y_bottomright   equ dataWidth*2+2

; ------------------------------------
; Entry Point
; ------------------------------------
                seg program
                org $C00

start           subroutine
                lda #0
                sta currentPage                 ; Point main data segment to first block
                ;jsr OUTPORT                     ; PR#0 (Set output to 40-column text screen)
                jsr initScreen                  ; Render initial cell layout
                jsr updateData                  ; Initialize backing data based on displayed cells
                if TEST_PERF
                jsr perfTest
                else
                jsr runLoop
                endif
                jmp EXITDOS

runLoop         subroutine
.loop           jsr iterate                     ; Modify and display next generation
                jmp .loop                       ; Until cows come home

perfTest        subroutine
                jsr RDKEY
.startTimer     
                lda #50
                sta .counter
.loop           jsr iterate
                dec .counter
                bne .loop
.endTimer
.break          jsr RDKEY
                echo "Breakpoint:", .break
                rts
.counter        ds.b 1
                echo "START TIMER BREAKPOINT:",.startTimer
                echo "END TIMER BREAKPOINT:",.endTimer

                mac INCREMENT_ADC
                ldy #y_{1}                      ; +2   2
                lda (altData),y                 ; +5/6 8
                adc #1                          ; +5   13 Relies on carry being clear
                sta (altData),y                 ; +6   19
                endm

                mac INCREMENT_INX
                ldy #y_{1}                      ; +2   2
                lda (altData),y                 ; +5/6 8
                tax                             ; +2   10
                inx                             ; +2   12
                txa                             ; +2   14
                sta (altData),y                 ; +6   20
                endm

                mac INCREMENT
                INCREMENT_ADC {1}
                endm

iterate         subroutine
                jsr toggleDataPages
                jsr clearBorders
                lda #fieldHeight-1
                sta .row
.rowLoop        jsr getTextRow
                lda #fieldWidth-1
                sta .column
                lda #0
                ldy #y_top                      ; clean up stale data
                sta (altData),y
                ldy #y_topright
                sta (altData),y
.columnLoop     ldy .column                     ; get neighbor bit flags
                lda (mainData),y                ; at current data address
                tay
                lda rulesTable,y                ; convert bit flags to cell state character (or 0 for do nothing)
                beq .doNothing                  ; rule says do nothing, so update the neighbor data
                ldy #0 ; .column
.column         equ .-1
                sta (textRow),y                 ; set char based on rule
                bne .setBits
.doNothing      ldy .column
                lda (textRow),y
.setBits        cmp #charOn                     ; A = cell character
                bne .clearTopLeft               ; cell is disabled, so clear the topleft neighbor
                if soundEnabled
                ;bit CLICK
                endif
                ldy #y_topleft                  ; set top left value to one (previous value is stale)
                lda #1                          
                sta (altData),y                 
                if soundEnabled
                ;bit CLICK                       ; (Pretend I'm not here... I just click the speaker)
                endif
                clc
                INCREMENT top                     
                INCREMENT topright
                INCREMENT left
                INCREMENT right
                INCREMENT bottomleft
                INCREMENT bottom
                INCREMENT bottomright
                jmp .continue
.clearTopLeft   ldy #y_topleft                  ; cell is off, so clear top left value to remove stale data
                lda #0
                sta (altData),y
.continue       sec
                lda altData
                sbc #1
                sta altData
                lda altDataH
                sbc #0
                sta altDataH
.nextColumn     dec .column
                bmi .nextRow
                jmp .columnLoop
.nextRow        sec
                lda mainData
                sbc #dataWidth
                sta mainData
                lda mainDataH
                sbc #0
                sta mainDataH
                sec
                lda altData
                sbc #2
                sta altData
                lda altDataH
                sbc #0
                sta altDataH
                dec .row
                lda #0 ; .row
.row            equ .-1
                bmi .end
                jmp .rowLoop
.end            rts

updateData      subroutine
                jsr toggleDataPages
                jsr clearBorders
                lda #fieldHeight-1
                sta .row
.rowLoop        jsr getTextRow
                lda #fieldWidth-1
                sta .column
                lda #0
                ldy #y_top                      ; clean up stale data
                sta (altData),y
                ldy #y_topright
                sta (altData),y
.columnLoop     ldy #0 ; .column
.column         equ .-1
                lda (textRow),y
                cmp #charOff
                beq .clearTopLeft
                ldy #y_topleft                  ; set top left value to one (previous value is stale)
                lda #1                          
                sta (altData),y
                clc                 
                INCREMENT top
                INCREMENT topright
                INCREMENT left
                INCREMENT right
                INCREMENT bottomleft
                INCREMENT bottom
                INCREMENT bottomright
                jmp .nextColumn
.clearTopLeft   ldy #y_topleft
                lda #0
                sta (altData),y
.nextColumn     sec
                lda altData
                sbc #1
                sta altData
                lda altDataH
                sbc #0
                sta altDataH
                dec .column
                bpl .columnLoop
.nextRow        sec
                lda altData
                sbc #2
                sta altData
                lda altDataH
                sbc #0
                sta altDataH
                dec .row
                lda #0 ; .row
.row            equ .-1
                bmi .end
                jmp .rowLoop
.end            rts

toggleDataPages subroutine                      ; toggles the current data page and sets up the pointers
                lda #1
                eor currentPage
                sta currentPage
                bne .page1
.page0          lda <#datapg0_lastRow
                sta mainData
                lda >#datapg0_lastRow
                sta mainDataH
                lda <#datapg1_tln
                sta altData
                lda >#datapg1_tln
                sta altDataH
                jmp .continue
.page1          lda <#datapg1_lastRow
                sta mainData
                lda >#datapg1_lastRow
                sta mainDataH
                lda <#datapg0_tln
                sta altData
                lda >#datapg0_tln
                sta altDataH
.continue       rts

clearBorders    subroutine

                mac CLEAR_BORDERS
.bottomRow      set datapg{2}_end - [dataWidth * 2] + 1
                ldx #fieldWidth
.hloop          lda #0
                sta .bottomRow,x
                dex
                bne .hloop
.rightColumn    set ZPB0
.rightAddr      set datapg{1}_end - dataWidth - 2
                lda <#.rightAddr
                sta <.rightColumn
                lda >#.rightAddr
                sta >.rightColumn
                ldy #0
                ldx #fieldHeight
.vloop          lda #0
                sta (.rightColumn),y
                lda #dataWidth
                sec
                sbc <.rightColumn
                sta <.rightColumn
                lda #0
                sbc >.rightColumn
                sta >.rightColumn
                dex
                bne .vloop
                endm

                lda currentPage
                bne .page1
.page0          CLEAR_BORDERS 0,1
                rts
.page1          CLEAR_BORDERS 1,0
                rts

initScreen      subroutine
                lda <#initData
                sta mainData
                lda >#initData
                sta mainDataH
                lda #initDataLen-1              ; get data length
                sta .dataoffset                 ; save it
                lda #fieldHeight-1              ; load the field height
                sta .row                        ; save in row counter
.1              jsr getTextRow                  ; update textRow (A = row)
                lda #fieldWidth-1               ; load the field width (reset every new row)
                sta .column                     ; save in column counter
                ldy .dataoffset
                lda (mainData),y                ; get the current data byte
                sta .byte                       ; save it
                lda #8                          ; init the byte counter
                sta .bit                        ; save in bit counter
.2              ldy .column
                lda #0
.byte           equ .-1
                lsr
                sta .byte
                bcs .turnOn
.turnOff        lda #charOff
                bne .draw
.turnOn         lda #charOn
.draw           sta (textRow),y
                dec .bit
                bne .skipbit
                lda #8                          ; reset bit counter
                sta .bit                        ; decrease data byte reference
                sec
                dec .dataoffset
                ldy #0 ; .dataoffset
.dataoffset     equ .-1
                lda (mainData),y
                sta .byte
.skipbit        lda .column                     ; start to calculate init byte offset
                dec .column
                ldy #0 ; .column
.column         equ .-1
                bpl .2
                dec .row
                lda #0 ; .row
.row            equ .-1
                bpl .1
                rts

.bit            ds.b 1

; inputs:
; A = row
; outputs:
; A = ?, X = A << 1, textRow = address of first character in row A
getTextRow      subroutine
                asl
                tax
                lda textRowsTable,x
                sta textRow
                lda textRowsTable+1,x
                sta textRowH
                rts

rulesTable      dc.b charOff                    ;0 neighbors
                dc.b charOff                    ;1
                dc.b 0                          ;2
                dc.b charOn                     ;3
                dc.b charOff                    ;4
                dc.b charOff                    ;5
                dc.b charOff                    ;6
                dc.b charOff                    ;7
                dc.b charOff                    ;8

; ------------------------------------
; Tables
; ------------------------------------
textRowsTable   subroutine                      ; Lookup table for text page 0 row addresses
.pg             equ 1024
.y              set 0
                repeat 25
                dc.w .pg + .y ; (.y & %11111000) * 5 + ((.y & %00000111) << 7)
.y              set .y + 40
                repend
                LOG_REGION "textRowsTable", textRowsTable, 0

                if initialPattern == 0             ; Glider gun
initData        dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%01000000,%00000000
                dc.b %00000000,%00000000,%00000001,%01000000,%00000000
                dc.b %00000000,%00000110,%00000110,%00000000,%00011000
                dc.b %00000000,%00001000,%10000110,%00000000,%00011000
                dc.b %01100000,%00010000,%01000110,%00000000,%00000000
                dc.b %01100000,%00010001,%01100001,%01000000,%00000000
                dc.b %00000000,%00010000,%01000000,%01000000,%00000000
                dc.b %00000000,%00001000,%10000000,%00000000,%00000000
                dc.b %00000000,%00000110,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                endif
                if initialPattern == 1        ; "Random"
initData        dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%01000000
                dc.b %00000000,%00000000,%00000000,%00000000,%10100000
                dc.b %00000000,%00000000,%00000000,%00000000,%10100000
                dc.b %00000000,%00000000,%00000000,%00000000,%01000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00100000,%00000000,%00000000,%00000000
                dc.b %00000000,%10110000,%00000000,%00000000,%00000000
                dc.b %00000000,%10100000,%00000000,%00000000,%00000000
                dc.b %00000000,%10000000,%00000000,%00000000,%00000000
                dc.b %00000010,%00000000,%00000000,%00000000,%00000000
                dc.b %00001010,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                endif
                if initialPattern == 2        ; Edge test
initData        dc.b %11000000,%00000000,%00011000,%00000000,%00000011
                dc.b %11000000,%00000000,%00100100,%00000000,%00000011
                dc.b %00000000,%00000000,%00011000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %11100000,%00000000,%00000000,%00000000,%00000111
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00011100,%00000000,%00111000,%00000000
                dc.b %00000000,%00010000,%11011011,%00001000,%00000000
                dc.b %00000000,%00001000,%11011011,%00010000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00001000,%11011011,%00010000,%00000000
                dc.b %00000000,%00010000,%11011011,%00001000,%00000000
                dc.b %00000000,%00011100,%00000000,%00111000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %11100000,%00000000,%00000000,%00000000,%00000111
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00000000,%00000000,%00000000
                dc.b %00000000,%00000000,%00011000,%00000000,%00000000
                dc.b %11000000,%00000000,%00100100,%00000000,%00000011
                dc.b %11000000,%00000000,%00011000,%00000000,%00000011
                endif
initDataLen     equ .-initData

dataSeg         equ .
                seg.u conwayData                ; uninitialized data segment
                org dataSeg

datapg0         ds.b dataWidth * dataHeight     ; data page 0
datapg0_lastRow equ . - dataWidth - fieldWidth  ; first visible cell of the last row
datapg0_tln     equ . - [n_offset * 2]          ; topleft neighbor of the bottomright-most visible cell
datapg0_end     equ .

datapg1         ds.b dataWidth * dataHeight     ; data page 1
datapg1_lastRow equ . - dataWidth - fieldWidth  ; first visible cell of the last row
datapg1_tln     equ . - [n_offset * 2]          ; topleft neighbor of the bottomright-most visible cell
datapg1_end     equ .