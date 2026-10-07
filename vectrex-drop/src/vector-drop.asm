; VECTOR DROP -- original falling-block game for the GCE Vectrex.
; Assemble with LWASM,6809,raw format. No BIOS is embedded in this ROM.
; Game RAM is C880..CAxx,below the BIOS stack at CBEA.

Wait_Recal      equ $F192
Read_Btns       equ $F1BA
Joy_Digital     equ $F1F8
Intensity_a     equ $F2AB
Moveto_d        equ $F312
Reset0Ref       equ $F354
Print_Str_d     equ $F37A
Draw_Line_d     equ $F3DF
Joy_X           equ $C81B
Joy_Y           equ $C81C
Joy_Mux         equ $C81F
Text_Size       equ $C82A
Scale           equ $D004
                setdp $D0       ; direct addressing is VIA, never ROM page zero

                org $C880
board           rmb 200
state           rmb 1           ; 0 title,1 playing,2 paused,3 game over
piece           rmb 1
rotation        rmb 1
piece_x         rmb 1
piece_y         rmb 1
next_piece      rmb 1
rng             rmb 1
bag_count       rmb 1
bag             rmb 7
score           rmb 2
lines           rmb 2
level           rmb 1           ; internal 0..9,displayed 1..10
fall_period     rmb 1
fall_timer      rmb 1
move_timer      rmb 1
last_dx         rmb 1
buttons         rmb 1
old_x           rmb 1
old_y           rmb 1
old_rot         rmb 1
cell_count      rmb 1
cell_x          rmb 1
cell_y          rmb 1
clear_row       rmb 1
cleared         rmb 1
award           rmb 2
draw_row        rmb 1
draw_col        rmb 1
run_start       rmb 1
run_length      rmb 1
box_y           rmb 1
box_x           rmb 1
box_width       rmb 1
box_height      rmb 1
digit_count     rmb 1
number_value    rmb 2
number_prefix   rmb 2
number_text     rmb 6
frame_count     rmb 2           ; debugger/test instrumentation
ram_end         equ *

                org 0
                fcc "g GCE 2026"
                fcb $80
                fdb $FD0D       ; built-in BIOS title tune
                fcb $F8,$50,$20,$B0
                fcc "VECTOR DROP"
                fcb $80,0

entry:
                lds #$CBEA
                lda #$D0
                tfr a,dp
                lda #$A7
                sta rng
                clr frame_count
                clr frame_count+1
                jsr NewGame
                clr state
                lda #1
                sta Joy_Mux
                lda #3
                sta Joy_Mux+1
                clr Joy_Mux+2
                clr Joy_Mux+3
                ldd #$FC28
                std Text_Size
MainLoop:
                jsr Wait_Recal
                lda #$D0
                tfr a,dp
                ldd frame_count
                addd #1
                std frame_count
                jsr RandomByte  ; timing of start/movement changes future bags
                jsr Read_Btns
                sta buttons
                jsr Joy_Digital
                jsr Update
                jsr Render
                jmp MainLoop

NewGame:
                ldx #board
                ldb #200
NGClear:        clr ,x+
                decb
                bne NGClear
                clr score
                clr score+1
                clr lines
                clr lines+1
                clr level
                clr bag_count
                clr fall_timer
                clr move_timer
                clr last_dx
                lda #35
                sta fall_period
                lda #1
                sta state
                jsr PickPiece
                sta next_piece
                jmp Spawn

RandomByte:
                lda rng
                lsra
                bcc RandomStore
                eora #$B8
RandomStore:    sta rng
                rts

; Draw without replacement from a seven-piece bag.
PickPiece:
                tst bag_count
                bne PickReady
                ldx #bag
                clra
PickFill:       sta ,x+
                inca
                cmpa #7
                blo PickFill
                sta bag_count
PickReady:      jsr RandomByte
PickModulo:     cmpa bag_count
                blo PickIndex
                suba bag_count
                bra PickModulo
PickIndex:      ldx #bag
                tfr a,b
                lda b,x
                pshs a
                dec bag_count
                lda bag_count
                lda a,x
                sta b,x
                puls a,pc

Spawn:
                lda next_piece
                sta piece
                jsr PickPiece
                sta next_piece
                clr rotation
                lda #3
                sta piece_x
                clr piece_y
                clr fall_timer
                jsr Collides
                tsta
                beq SpawnDone
                lda #3
                sta state
SpawnDone:      rts

Update:
                lda state
                cmpa #1
                beq UpdatePlay
                cmpa #2
                beq UpdatePause
                lda buttons
                bita #8
                beq UpdateDone
                jmp NewGame
UpdatePause:    lda buttons
                bita #1
                beq UpdateDone
                lda #1
                sta state
UpdateDone:     rts
UpdatePlay:     lda buttons
                bita #1
                beq UpdateMove
                lda #2
                sta state
                rts
UpdateMove:     lda Joy_X
                beq MoveReleased
                bmi MoveLeft
                lda #1
                bra MoveDirection
MoveLeft:      lda #$FF
MoveDirection: cmpa last_dx
                bne MoveFirst
                dec move_timer
                bne UpdateRotate
                ldb #4
                stb move_timer
                bra MoveTry
MoveFirst:     sta last_dx
                ldb #12
                stb move_timer
MoveTry:       ldb piece_x
                stb old_x
                adda piece_x
                sta piece_x
                jsr Collides
                tsta
                beq UpdateRotate
                lda old_x
                sta piece_x
                bra UpdateRotate
MoveReleased:  clr last_dx
                clr move_timer
UpdateRotate:  lda buttons
                bita #2
                beq RotateRight
                lda #3
                jsr Rotate
RotateRight:   lda buttons
                bita #4
                beq UpdateDrop
                lda #1
                jsr Rotate
UpdateDrop:    lda buttons
                bita #8
                beq UpdateGravity
HardDrop:      inc piece_y
                jsr Collides
                tsta
                bne HardLock
                ldd #2
                jsr AddScore
                bra HardDrop
HardLock:      dec piece_y
                jmp LockPiece
UpdateGravity: inc fall_timer
                lda fall_period
                tst Joy_Y
                bpl GravityCheck
                lda #3
GravityCheck:  cmpa fall_timer
                lbhi UpdateDone
                clr fall_timer
                inc piece_y
                jsr Collides
                tsta
                bne GravityLock
                tst Joy_Y
                bpl GravityDone
                ldd #1
                jsr AddScore
GravityDone:   rts
GravityLock:   dec piece_y
                jmp LockPiece

; Basic wall/floor kicks,deliberately not the modern SRS ruleset.
Rotate:
                ldb rotation
                stb old_rot
                adda rotation
                anda #3
                sta rotation
                lda piece_x
                sta old_x
                lda piece_y
                sta old_y
                jsr Collides
                tsta
                beq RotateDone
                ldy #Kicks
                ldb #4
RotateKick:    pshs b,y
                lda ,y
                adda old_x
                sta piece_x
                jsr Collides
                puls b,y
                tsta
                beq RotateDone
                leay 1,y
                decb
                bne RotateKick
                lda old_x
                sta piece_x
                dec piece_y
                jsr Collides
                tsta
                beq RotateDone
                dec piece_y
                jsr Collides
                tsta
                beq RotateDone
                lda old_y
                sta piece_y
                lda old_rot
                sta rotation
RotateDone:    rts
Kicks:         fcb -1,1,-2,2

; X -> four (column,row) coordinate pairs for current shape/rotation.
ShapePointer:
                lda piece
                ldb #32
                mul
                ldx #Shapes
                leax d,x
                lda rotation
                lsla
                lsla
                lsla
                leax a,x
                rts

; A=0 valid,A=1 collision; no game state or board writes.
Collides:
                jsr ShapePointer
                lda #4
                sta cell_count
CollisionCell: lda ,x+
                adda piece_x
                cmpa #10
                bhs CollisionYes
                sta cell_x
                lda ,x+
                adda piece_y
                cmpa #20
                bhs CollisionYes
                ldb #10
                mul
                addb cell_x
                ldu #board
                leau d,u
                tst ,u
                bne CollisionYes
                dec cell_count
                bne CollisionCell
                clra
                rts
CollisionYes:  lda #1
                rts

LockPiece:
                jsr ShapePointer
                lda #4
                sta cell_count
LockCell:      lda ,x+
                adda piece_x
                sta cell_x
                lda ,x+
                adda piece_y
                ldb #10
                mul
                addb cell_x
                ldu #board
                leau d,u
                lda #1
                sta ,u
                dec cell_count
                bne LockCell
                jsr ClearLines
                jmp Spawn

ClearLines:
                clr cleared
                lda #19
                sta clear_row
ClearCheck:    lda clear_row
                ldb #10
                mul
                ldx #board
                leax d,x
                ldb #10
ClearScan:     tst ,x+
                beq ClearNext
                decb
                bne ClearScan
                inc cleared
                ; X points after the full row. Copy all earlier rows down.
                leau -10,x
                lda clear_row
                ldb #10
                mul
                tstb
                beq ClearTop
ClearCopy:     lda ,-u
                sta ,-x
                decb
                bne ClearCopy
ClearTop:      ldx #board
                ldb #10
ClearZero:     clr ,x+
                decb
                bne ClearZero
                bra ClearCheck  ; recheck this row after the collapse
ClearNext:     dec clear_row
                bpl ClearCheck
                ldb cleared
                beq ClearDone
                lslb
                ldx #Awards
                ldd b,x
                std award
                ldb level
                incb
ClearScore:    pshs b
                ldd award
                jsr AddScore
                puls b
                decb
                bne ClearScore
                clra
                ldb cleared
                addd lines
                cmpd #999
                bls ClearLineStore
                ldd #999
ClearLineStore: std lines
                clr level
                cmpd #90
                blo LevelLoop
                lda #9
                sta level
                bra LevelDone
LevelLoop:     cmpd #10
                blo LevelDone
                subd #10
                inc level
                bra LevelLoop
LevelDone:     lda level
                ldb #3
                mul
                stb fall_period
                lda #35
                suba fall_period
                sta fall_period
ClearDone:     rts
Awards:        fdb 0,100,300,500,800

; Saturating 16-bit score; never wraps back to zero.
AddScore:      addd score
                bcc AddScoreStore
                ldd #$FFFF
AddScoreStore: std score
                rts

Render:
                lda #$60
                jsr Intensity_a
                lda #$7F
                sta Scale
                ; Board sides: split long vertical vectors into signed bytes.
                jsr Reset0Ref
                ldd #$50B0      ; y=80,x=-80
                jsr Moveto_d
                ldd #$0050
                jsr Draw_Line_d
                ldd #$B000
                jsr Draw_Line_d
                ldd #$B000
                jsr Draw_Line_d
                ldd #$00B0
                jsr Draw_Line_d
                ldd #$5000
                jsr Draw_Line_d
                ldd #$5000
                jsr Draw_Line_d
                ; Occupied horizontal runs share an outline. This keeps
                ; dense boards inexpensive without drawing a full grid.
                lda #$48
                jsr Intensity_a
                clr draw_row
                ldx #board
RenderRow:     clr draw_col
RenderFind:    tst ,x
                beq RenderEmpty
                lda draw_col
                sta run_start
                clr run_length
RenderRun:     inc run_length
                inc draw_col
                leax 1,x
                lda draw_col
                cmpa #10
                beq RenderRunBox
                tst ,x
                beq RenderRunBox
                bra RenderRun
RenderRunBox:  lda draw_row
                lsla
                lsla
                lsla
                nega
                adda #79
                sta box_y
                lda run_start
                lsla
                lsla
                lsla
                adda #-79
                sta box_x
                lda run_length
                lsla
                lsla
                lsla
                suba #2
                sta box_width
                lda #6
                sta box_height
                pshs x
                jsr DrawBox
                puls x
                bra RenderContinue
RenderEmpty:   inc draw_col
                leax 1,x
RenderContinue: lda draw_col
                cmpa #10
                blo RenderFind
                inc draw_row
                lda draw_row
                cmpa #20
                blo RenderRow

                lda state
                cmpa #1
                bne RenderHUD
                lda #$7F
                jsr Intensity_a
                jsr ShapePointer
                lda #4
                sta cell_count
RenderActive:  lda ,x+
                adda piece_x
                lsla
                lsla
                lsla
                adda #-79
                sta box_x
                lda ,x+
                adda piece_y
                lsla
                lsla
                lsla
                nega
                adda #79
                sta box_y
                lda #6
                sta box_width
                sta box_height
                pshs x
                jsr DrawBox
                puls x
                dec cell_count
                bne RenderActive
RenderHUD:
                lda #$60
                jsr Intensity_a
                ldu #TitleText
                ldd #$64B0
                jsr PrintText
                ldd score
                jsr Decimal
                ldd #$5320      ; "S " prefix
                std number_prefix
                ldu #number_prefix
                ldd #$5014
                jsr PrintText
                ldd lines
                jsr Decimal
                ldd #$4C20      ; "L " replaces two leading zeroes
                std number_text
                ldu #number_text
                ldd #$3214
                jsr PrintText
                clra
                ldb level
                incb
                jsr Decimal
                ldd #$4C56      ; "LV " replaces three leading zeroes
                std number_text
                lda #32        ; ASCII space
                sta number_text+2
                ldu #number_text
                ldd #$1414
                jsr PrintText
                ldu #NextText
                ldd #$ED14
                jsr PrintText
                ; Draw the next piece's spawn orientation in the sidebar.
                lda next_piece
                ldb #32
                mul
                ldx #Shapes
                leax d,x
                lda #4
                sta cell_count
RenderNext:    lda ,x+
                lsla
                lsla
                lsla
                adda #24
                sta box_x
                lda ,x+
                lsla
                lsla
                lsla
                nega
                adda #-38
                sta box_y
                lda #6
                sta box_width
                sta box_height
                pshs x
                jsr DrawBox
                puls x
                dec cell_count
                bne RenderNext
                lda state
                cmpa #1
                beq RenderDone
                cmpa #2
                beq RenderPaused
                cmpa #3
                beq RenderOver
                ldu #StartText
                bra RenderMessage
RenderPaused:  ldu #PauseText
                bra RenderMessage
RenderOver:    ldu #OverText
RenderMessage: ldd #$0CBA
                jsr PrintText
                lda state
                cmpa #2
                beq RenderDone
                ldu #ButtonText
                ldd #$F8BA
                jsr PrintText
RenderDone:    rts

; Inputs in box_*; each box starts at zero reference to limit analog drift.
DrawBox:
                jsr Reset0Ref
                lda #$7F
                sta Scale
                lda box_y
                ldb box_x
                jsr Moveto_d
                ; Short vectors use a smaller timer and larger DAC delta.
                ; This preserves size while avoiding 127-cycle tiny lines.
                lda box_width
                cmpa #31
                bhs BoxMedium
                asl box_width
                asl box_height
                asl box_width
                asl box_height
                lda #31
                sta Scale
                bra BoxEdges
BoxMedium:     cmpa #63
                bhs BoxEdges
                asl box_width
                asl box_height
                lda #63
                sta Scale
BoxEdges:
                clra
                ldb box_width
                jsr Draw_Line_d
                lda box_height
                nega
                clrb
                jsr Draw_Line_d
                clra
                ldb box_width
                negb
                jsr Draw_Line_d
                lda box_height
                clrb
                jmp Draw_Line_d

PrintText:
                pshs d,u
                jsr Reset0Ref
                puls d,u
                jmp Print_Str_d

; Unsigned D -> five ASCII digits and the BIOS high-bit string terminator.
Decimal:
                std number_value
                ldx #Divisors
                ldu #number_text
DecimalDigit:  clr digit_count
                ldd number_value
DecimalSub:    cmpd ,x
                blo DecimalPut
                subd ,x
                inc digit_count
                bra DecimalSub
DecimalPut:    std number_value
                lda digit_count
                adda #'0
                sta ,u+
                leax 2,x
                cmpx #Divisors+10
                blo DecimalDigit
                lda #$80
                sta ,u
                rts
Divisors:      fdb 10000,1000,100,10,1
TitleText:     fcc "VECTOR DROP"
                fcb $80
ScoreText:     fcc "SCORE"
                fcb $80
LinesText:     fcc "LINES"
                fcb $80
LevelText:     fcc "LEVEL"
                fcb $80
NextText:      fcc "NEXT"
                fcb $80
ControlText:   fcc "1:PAUSE  2/3:TURN  4:DROP"
                fcb $80
StartText:     fcc "READY?"
                fcb $80
PauseText:     fcc "PAUSED"
                fcb $80
OverText:      fcc "GAME OVER"
                fcb $80
ButtonText:    fcc "PRESS 4"
                fcb $80

; Seven tetrominoes,four clockwise orientations,four (x,y) cells each.
Shapes:
; I
                fcb 0,1,1,1,2,1,3,1
                fcb 2,0,2,1,2,2,2,3
                fcb 0,2,1,2,2,2,3,2
                fcb 1,0,1,1,1,2,1,3
; O
                fcb 1,0,2,0,1,1,2,1
                fcb 1,0,2,0,1,1,2,1
                fcb 1,0,2,0,1,1,2,1
                fcb 1,0,2,0,1,1,2,1
; T
                fcb 1,0,0,1,1,1,2,1
                fcb 1,0,1,1,2,1,1,2
                fcb 0,1,1,1,2,1,1,2
                fcb 1,0,0,1,1,1,1,2
; S
                fcb 1,0,2,0,0,1,1,1
                fcb 1,0,1,1,2,1,2,2
                fcb 1,1,2,1,0,2,1,2
                fcb 0,0,0,1,1,1,1,2
; Z
                fcb 0,0,1,0,1,1,2,1
                fcb 2,0,1,1,2,1,1,2
                fcb 0,1,1,1,1,2,2,2
                fcb 1,0,0,1,1,1,0,2
; J
                fcb 0,0,0,1,1,1,2,1
                fcb 1,0,2,0,1,1,1,2
                fcb 0,1,1,1,2,1,2,2
                fcb 1,0,1,1,0,2,1,2
; L
                fcb 2,0,0,1,1,1,2,1
                fcb 1,0,1,1,1,2,2,2
                fcb 0,1,1,1,2,1,0,2
                fcb 0,0,1,0,1,1,1,2
rom_end:
