\ Forth core

VARIABLE STATE  ( compilation state variable )
0 STATE !       ( interpreting by default )

VARIABLE BLK
: FH
    BLK @ + ;  \ relative block
: LOAD
    BLK @ SWAP DUP BLK ! (LOAD) BLK ! ;

\ Stack primitives
: ROT
    >R SWAP R> SWAP ;
: ?DUP
    DUP IF DUP THEN ;

( Not part of CORE, disabled at the moment )
\ : -ROT  SWAP >R SWAP R> ;  \ or ROT ROT
\ : NIP  ( n1 n2 -- n2 )       SWAP DROP ;
\ : TUCK ( n1 n2 -- n2 n1 n2 ) SWAP OVER ;

: 2DROP   DROP DROP ;
: 2DUP  OVER OVER ;
: 2SWAP  ROT >R ROT R> ;
: 2OVER  >R >R 2DUP R> R> 2SWAP ;

\ Comparisons
-1 CONSTANT TRUE   0 CONSTANT FALSE

:  =  ( n n -- f)
    XOR  0= ;
:  < ( n n -- f )
    - 0< ;
:  > ( n n -- f )
    SWAP < ;

: MAX ( n n -- n )
    2DUP < IF SWAP THEN DROP ;
: MIN ( n n -- n )
    2DUP > IF SWAP THEN DROP ;

: WITHIN  ( u ul uh -- f )
    OVER - >R - R> U< ;

\ Arithmetic and logical
: 1+  1 + ;
: 1-  1 - ;
: INVERT  TRUE XOR ;
: NEGATE  INVERT 1+ ;
: DNEGATE  INVERT SWAP NEGATE SWAP OVER 0= - ;
: S>D  ( n -- d ) DUP 0< ;   \ sign extend
: ABS  S>D IF NEGATE THEN ;
: DABS  DUP 0< IF DNEGATE THEN ;

: +-
    0< IF NEGATE THEN ;
: D+-
    0< IF DNEGATE THEN ;

\ Variables
VARIABLE BASE
: DECIMAL 10 BASE ! ;   : HEX 16 BASE ! ;

VARIABLE DP

\ Math
: SM/REM ( d n -- r q )  \ symmetric
    OVER >R >R DABS R@ ABS UM/MOD
    R> R@ XOR 0< IF NEGATE THEN
    R> 0< IF >R NEGATE R> THEN ;

: FM/MOD ( d n -- r q )  \ floored
    DUP 0< DUP >R IF NEGATE >R DNEGATE R> THEN
    >R DUP 0< IF R@ + THEN
    R> UM/MOD R> IF >R NEGATE R> THEN ;

: /MOD  OVER 0< SWAP FM/MOD ;
: MOD   /MOD DROP ;
: /     /MOD SWAP DROP ;

: *  UM* DROP ;
: M*  2DUP XOR R> ABS SWAP ABS UM* R> D+- ;
: */MOD  >R M* R> FM/MOD ;
: */     */MOD SWAP DROP ;

: 2* DUP + ;
\ 2/ which is right shift is native

: LSHIFT ( x1 u -- x2 )
    BEGIN DUP WHILE SWAP 2* SWAP 1- REPEAT DROP ;

: RSHIFT ( x1 u -- x2 )
    BEGIN DUP WHILE SWAP 2/ SWAP 1- REPEAT DROP ;

\ Numeric output primitives
VARIABLE HLD
: HERE ( -- addr )  DP @ ;
: PAD ( -- c-addr )  HERE 64 CHARS + ;

: <# ( -- )  PAD HLD ! ;
: #> ( xd -- c-addr u )  2DROP HLD @ PAD OVER - ;
: HOLD ( c -- )  HLD @ -1 CHARS - DUP HLD ! C! ;
: DIGIT ( u -- c )  9 OVER < 7 AND + 30 +  ;
: # ( ud1 -- ud2 )
    0 BASE @ UM/MOD >R BASE @ UM/MOD SWAP DIGIT HOLD R> ;
: #S ( ud1 -- ud2 )  BEGIN # 2DUP OR 0= UNTIL ;
: SIGN ( n -- )  0< IF 45 ( - ) HOLD THEN ;

\ Memory access
: +! ( n a-addr -- )  DUP >R @ + R> ! ;
: 2! ( x1 x2 a-addr -- )  SWAP OVER ! CELL+ ! ;
: 2@ ( a-addr -- x1 x2 )  DUP CELL+ @ SWAP @ ;
: COUNT ( c-addr1 -- c-addr2 u )  DUP CHAR+ SWAP C@ ;

\ Compiler
: [  FALSE STATE ! ; IMMEDIATE
: ]  TRUE STATE ! ;

: ALLOT ( n -- )  DP +! ;
: HERE ( -- a ) DP @ ;
: , ( n -- )  HERE [ 1 CELLS ] LITERAL ALLOT ! ;
: COMPILE, ( xt -- )  HERE [ 1 INSTRS ] LITERAL ALLOT ! ;
: LITERAL ( x -- )  ['] _LIT COMPILE, , ; IMMEDIATE

: VARIABLE CREATE 1 CELLS ALLOT ;
: CONSTANT CREATE , DOES> @ ;

( Colon definitions )
: :  CREATE ] ;
: ;  POSTPONE EXIT SMUDGE [ ; IMMEDIATE

\ Interpreter
CREATE _INPUT-BUFFER 80 CHARS ALLOT ( may do this internally? )

: EVALUATE
    >IN @ >R 0 >IN ! SOURCE >R >R #IN 2! _INTERPRET
    R> R> #IN 2! R> >IN ! ;

: QUIT  _RESET-RSTACK
    BEGIN
	BEGIN
	    _READ-LINE 0 >IN ! _INPUT-BUFFER 0 EVALUATE CR
	    STATE @
	UNTIL ." ok "  ( exhausted input in interpretation mode )
    AGAIN ;
