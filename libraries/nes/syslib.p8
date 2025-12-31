%option no_symbol_prefixing, ignore_unused

nes{

    ; Various IO regs. Names taken from nesdev wiki

    ; PPU regs
    &ubyte PPUCTRL = $2000
    &ubyte PPUMASK = $2001
    &ubyte PPUSTATUS = $2002
    &ubyte OAMADDR = $2003
    &ubyte OAMDATA = $2004
    &ubyte PPUSCROLL = $2005 ; takes a word value by writing to it 2 times
    &ubyte PPUADDR = $2006 ; takes a word value by writing to it 2 times
    &ubyte PPUDATA = $2007

    ; sound channels
    &ubyte SQ1_VOL = $4000
    &ubyte SQ1_SWEEP = $4001
    &ubyte SQ1_LO = $4002
    &ubyte SQ1_HI = $4003

    &ubyte SQ2_VOL = $4004
    &ubyte SQ2_SWEEP = $4005
    &ubyte SQ2_LO = $4006
    &ubyte SQ2_HI = $4007

    &ubyte TRI_LINEAR = $4008
    ;ubyte -
    &ubyte TRI_LO = $400a
    &ubyte TRI_HI = $400b

    &ubyte NOISE_VOL = $400c
    ;ubyte -
    &ubyte NOISE_LO = $400e
    &ubyte NOISE_HI = $400f

    &ubyte DMC_FREQ = $4010
    &ubyte DMC_RAW = $4011
    &ubyte DMC_START = $4012
    &ubyte DMC_LEN = $4013

    ; other IO
    &ubyte OAMDMA = $4014
    &ubyte SND_CHN = $4015
    &ubyte JOYPAD1 = $4016
    &ubyte JOYPAD2 = $4017

    ; temporary values of important write-only IO regs. Should try to reflect the last write state
    ubyte @dirty temp_PPUCTRL
    ubyte @dirty temp_PPUMASK
    uword temp_PPUSCROLL
    ubyte temp_SNDCHN

    ; PPUMASK should be only written to in VBlank, so instead
    ; we write to temp_PPUMASK and the default NMI handler takes care of that.
    inline asmsub set_ppumask(ubyte mask @A){
        %asm{{
            sta nes.temp_PPUMASK
        }}
    }    
    inline asmsub get_ppumask() -> ubyte @A{
        %asm{{
            lda nes.temp_PPUMASK
        }}
    }
    inline asmsub ppustatus_read() -> bool @Pn, bool @Pv{
        %asm{{
            bit nes.PPUSTATUS
        }}
    }


    uword nmi_vec = &nmi_handler
    uword irq_vec = &irq_handler
    bool nmicheck ; a reliable way to check whether nmi has occured. works only if default nmi
    uword postnmi_vec ; a pointer to a function to execute after the nmi

    ; internal functions for jumping to handlers defined by vector variables
    asmsub nmijmp(){
        %asm{{
            jmp (nmi_vec)
        }}
    }
    asmsub irqjmp(){
        %asm{{
            jmp (irq_vec)
        }}
    }

    ; the default NMI handler of Prog8 programs. needed for all of the helper routines to work
    asmsub nmi_handler(){
        %asm{{
        inx7 .macro
            inx
            bpl +
            ldx #0
        +
            .endmacro
            pha
            txa
            pha
            tya
            pha
            lda P8ZP_SCRATCH_REG
            pha

            lda temp_PPUMASK
            sta PPUMASK

            bit PPUSTATUS

            ldx ppurqfo
        _ppurqloop
            lda temp_PPUCTRL
            sta PPUCTRL
            lda ppurqbuf, x
            sta P8ZP_SCRATCH_REG
            lda #%00111111
            bit P8ZP_SCRATCH_REG
            bne +
            jmp _endppurq
        +   bpl +

            pha
            ; this somewhat assumes, that user did not set 32 inc themself.
            lda temp_PPUCTRL 
            ora #4
            sta PPUCTRL
            pla

        +   bvc _ppurqnormal

            and P8ZP_SCRATCH_REG
            tay
            #inx7
            lda ppurqbuf, x
            sta PPUADDR
            #inx7
            lda ppurqbuf, x
            sta PPUADDR
            #inx7

            lda ppurqbuf, x
        -   sta PPUDATA
            dey
            bne -
            #inx7
            jmp _ppurqloop

        _ppurqnormal
            and P8ZP_SCRATCH_REG
            tay
            #inx7
            lda ppurqbuf, x
            sta PPUADDR
            #inx7
            lda ppurqbuf, x
            sta PPUADDR
            #inx7

        -   lda ppurqbuf, x
            sta PPUDATA
            #inx7
            dey
            bne -
            jmp _ppurqloop

        _endppurq
            stx ppurqfo

            lda temp_PPUSCROLL
            sta PPUSCROLL
            lda temp_PPUSCROLL+1
            sta PPUSCROLL

            inc nes.nmicheck

            ; run postnmi function, if exists
            lda postnmi_vec+1
            beq +
            jsr sys.save_prog8_internals
            jsr _post_nmi
            jsr sys.restore_prog8_internals

        +   pla
            sta P8ZP_SCRATCH_REG
            pla
            tay
            pla
            tax
            pla
            rti
        _post_nmi
            jmp (postnmi_vec)
        }}
    }

    asmsub irq_handler(){
        %asm{{
            rti
        }}
    }

    const uword PALETTES_PPUADDR = $3f00

    ubyte[128] @shared ppurqbuf ; TODO - this has to be smaller ToT
    ubyte ppurqfi
    ubyte @shared ppurqfo
    ;bool ppurqfull = false ; yeah, it's actually useless, fi and fo can't overlap in any scenario (unless the request buffer is empty)
    bool ppurqwip = false

    ; PPU send request functions. They tell the NMI handler to load data to PPU.
    ; they return false if the Request Buffer doesn't have enough space for the request

    ; sends a singular byte to the PPU
    sub ppu_sendrq_byte(uword ppuaddr, ubyte value) -> bool{
        if ppurqwip or ppurqbuffree() < 4{
            return false
        }
        ppurqbuf[(ppurqfi+1)&127]=msb(ppuaddr)
        ppurqbuf[(ppurqfi+2)&127]=lsb(ppuaddr)
        ppurqbuf[(ppurqfi+3)&127]=value
        ppurqbuf[(ppurqfi+4)&127]=0
        ppurqbuf[ppurqfi]=1
        ppurqfi=(ppurqfi+4)&127
        return true
    }

    ; sets specified amount of bytes in PPU to a specific value
    sub ppu_sendrq_memset(uword ppuaddr, ubyte length, ubyte value, bool vertical) -> bool{
        if ppurqwip or length >63 or ppurqbuffree() < 4{
            return false
        }
        ppurqbuf[(ppurqfi+1)&127]=msb(ppuaddr)
        ppurqbuf[(ppurqfi+2)&127]=lsb(ppuaddr)
        ppurqbuf[(ppurqfi+3)&127]=value
        ppurqbuf[(ppurqfi+4)&127]=0
        ppurqbuf[ppurqfi]=length|$40|((vertical as ubyte)<<7)
        ppurqfi=(ppurqfi+4)&127
        return true
    }

    ; sends specified data. `data` argument is expected to be an array of values
    sub ppu_sendrq_data(uword ppuaddr, ubyte length, uword data, bool vertical) -> bool{
        if ppurqwip or length >63 or ppurqbuffree() < length+3{
            return false
        }
        ppurqbuf[(ppurqfi+1)&127]=msb(ppuaddr)
        ppurqbuf[(ppurqfi+2)&127]=lsb(ppuaddr)
        ppurqfi=(ppurqfi+3)&127
        cx16.r0L=0
        while cx16.r0L < length{
            ppurqbuf[(ppurqfi+cx16.r0L)&127]=data[cx16.r0L]
            cx16.r0L+=1
        }
        ppurqbuf[(ppurqfi+length)&127]=0
        ppurqbuf[(ppurqfi-3)&127]=length|((vertical as ubyte)<<7)
        ppurqfi=(ppurqfi+length)&127
        return true
    }

    ; tells us how many free bytes are there in PPU request buffer
    ; returned value is smaller by 1 from actual free space
    sub ppurqbuffree() -> ubyte{
        if ppurqfi<ppurqfo{
            return ppurqfo-ppurqfi-1
        }
        return len(ppurqbuf)-1-(ppurqfi-ppurqfo)
    }

    ubyte ppurqfi_b

    ; The functions bellow allow you to iteratively build a ppu request byte by byte.
    ; Useful, if data length is unknown or calculating it requires iterating through elements
    sub ppu_buildrq_start(uword ppuaddr, bool vertical) -> bool{
        if ppurqwip or ppurqbuffree() < 5{
            return false
        }
        ppurqwip=true
        ppurqfi_b=(ppurqfi+3)&127
        ppurqbuf[(ppurqfi+1)&127]=msb(ppuaddr)
        ppurqbuf[(ppurqfi+2)&127]=lsb(ppuaddr)
        ppurqbuf[ppurqfi]= if vertical 128 else 0
        return true
    }

    sub ppu_buildrq_push(ubyte value) -> bool{
        if not ppurqwip or (ppurqfi_b+1)&127==ppurqfo{
            return false
        }
        if ppu_buildrq_len()+1>63{
            return false
        }
        ppurqbuf[ppurqfi_b]=value
        ppurqfi_b=(ppurqfi_b+1)&127
        return true
    }

    sub ppu_buildrq_send(){
        if (not ppurqwip) return
        ppurqbuf[ppurqfi_b]=0
        ppurqbuf[ppurqfi]|=ppu_buildrq_len()
        ppurqfi=ppurqfi_b
        ppurqwip=false
    }

    sub ppu_buildrq_cancel(){
        ppurqwip=false
    }

    sub ppu_buildrq_len() -> ubyte{
        if ppurqfi<ppurqfi_b {
            return ppurqfi_b-ppurqfi-3
        }
        return len(ppurqbuf)-1-(ppurqfi-ppurqfi_b)-2
    }

    ; similar to ppu_sendrq functions, but loads data immediately, outside of VBlank.
    ; Good, when you want to load enormous amounts of data, PPU is turned OFF during this function
    sub ppu_loadnow(uword ppuaddress, uword length, uword data, bool vertical){;, bool surpress_nmi){
        cx16.r0L = temp_PPUMASK
        temp_PPUMASK &=~$18
        sys.waitvsync()
        PPUCTRL= (temp_PPUCTRL & %01111011)|(if vertical 4 else 0);|(if surpress_nmi 0 else 128)
        %asm{{
            lda ppuaddress+1
            sta PPUADDR
            lda ppuaddress
            sta PPUADDR
        }}
        cx16.r1=0
        while cx16.r1 < length{
            PPUDATA=data[cx16.r1]
            cx16.r1+=1
        }
        temp_PPUMASK=cx16.r0L
        void ppustatus_read()
        PPUCTRL=temp_PPUCTRL
    }

    sub ppu_memsetnow(uword ppuaddress, uword length, ubyte value, bool vertical){;, bool surpress_nmi){
        cx16.r0L = temp_PPUMASK
        temp_PPUMASK &=~$18
        sys.waitvsync()
        PPUCTRL= (temp_PPUCTRL & %01111011)|(if vertical 4 else 0);|(if surpress_nmi 0 else 128)
        %asm{{
            lda ppuaddress+1
            sta PPUADDR
            lda ppuaddress
            sta PPUADDR
        }}
        repeat length{
            PPUDATA=value
        }
        temp_PPUMASK=cx16.r0L
        void ppustatus_read()
        PPUCTRL=temp_PPUCTRL
    }




    ; fetches the data from controllers. assumes normal NES controllers.
    ; there are apparently some additional stuff to care about when playing samples,
    ; this routine doesn't take that into consideration.
    asmsub joyfetch() -> ubyte @A, ubyte @Y{
        %asm{{
            lda #$01
            sta JOYPAD1
            sta P8ZP_SCRATCH_W1+1 ; player 2's buttons double as a ring counter
            lsr a
            sta JOYPAD1
        -   lda JOYPAD1
            lsr a
            rol P8ZP_SCRATCH_W1
            lda JOYPAD2
            lsr a
            rol P8ZP_SCRATCH_W1+1
            bcc -
            lda P8ZP_SCRATCH_W1
            ldy P8ZP_SCRATCH_W1+1
            rts
        }}
    }
    const ubyte JOY_A       = %10000000
    const ubyte JOY_B       = %01000000
    const ubyte JOY_SELECT  = %00100000
    const ubyte JOY_START   = %00010000
    const ubyte JOY_UP      = %00001000
    const ubyte JOY_DOWN    = %00000100
    const ubyte JOY_LEFT    = %00000010
    const ubyte JOY_RIGHT   = %00000001

    ; convenience routines for setting the palette colors.
    sub palette_set(ubyte palettenum @R3, ubyte c1 @R1, ubyte c2 @R0, ubyte c3 @R2){
        cx16.r1H=cx16.r0L
        if not ppu_sendrq_data(PALETTES_PPUADDR+(palettenum & 7)*4+1, 3, &cx16.r1, false){
            sys.waitvsync()
            void ppu_sendrq_data(PALETTES_PPUADDR+(palettenum & 7)*4+1, 3, &cx16.r1, false)
        }
    }
    sub bgcolor_set(ubyte value){
        if not ppu_sendrq_byte(PALETTES_PPUADDR, value){
            sys.waitvsync()
            void ppu_sendrq_byte(PALETTES_PPUADDR, value)
        }
    }
    sub palette_setall_from(uword colorarray){
        if not ppu_sendrq_data(PALETTES_PPUADDR, 32, colorarray, false){
            sys.waitvsync()
            void ppu_sendrq_data(PALETTES_PPUADDR, 32, colorarray, false)
        }
    }

}

sys{
    const ubyte target = 85

    const ubyte SIZEOF_BOOL  = 1
    const ubyte SIZEOF_BYTE  = 1
    const ubyte SIZEOF_UBYTE = 1
    const ubyte SIZEOF_WORD  = 2
    const ubyte SIZEOF_UWORD = 2
    const ubyte SIZEOF_LONG  = sizeof(long)
    const ubyte SIZEOF_POINTER = sizeof(&p8_sys_startup.init_system)
    const byte  MIN_BYTE     = -128
    const byte  MAX_BYTE     = 127
    const ubyte MIN_UBYTE    = 0
    const ubyte MAX_UBYTE    = 255
    const word  MIN_WORD     = -32768
    const word  MAX_WORD     = 32767
    const uword MIN_UWORD    = 0
    const uword MAX_UWORD    = 65535

    ; TODO: set_irq(), restore_irq(), set_rasterirq(), set_raster().
    ; Note that on NES, vblank is actually handled by NMI.

    asmsub reset_system() {
        ; There probably isn't any other way
        %asm{{
            jmp ($fffc)
        }}
    }

    sub wait(uword jiffies){
        ; TODO
    }

    %asm{{
    waitvsync .macro
        dec nes.nmicheck
        pha
    -   lda nes.nmicheck
        beq -
        pla
        .endmacro
    waitvsync2 .macro
    -   bit nes.PPUSTATUS
        bpl -
        .endmacro
    }}
    inline asmsub waitvsync(){
        %asm{{
            #sys.waitvsync
        }}
    }

    asmsub internal_stringcopy(uword source @R0, uword target @AY) clobbers (A,Y) {
        ; Called when the compiler wants to assign a string value to another string.
        %asm {{
		sta  P8ZP_SCRATCH_W1
		sty  P8ZP_SCRATCH_W1+1
		lda  cx16.r0
		ldy  cx16.r0+1
		jmp  prog8_lib.strcpy
        }}
    }

    asmsub memcopy(uword source @R0, uword target @R1, uword count @AY) clobbers(A,X,Y) {
        ; note: only works for NON-OVERLAPPING memory regions!
        ;       If you have to copy overlapping memory regions, consider using
        ;       the cx16 specific kernal routine `memory_copy` (make sure kernal rom is banked in).
        ; note: can't be inlined because is called from asm as well.
        ;       also: doesn't use cx16 ROM routine so this always works even when ROM is not banked in.
        %asm {{
            cpy  #0
            bne  _longcopy

            ; copy <= 255 bytes
            tay
            bne  _copyshort
            rts     ; nothing to copy

        _copyshort
            dey
            beq  +
        -   lda  (cx16.r0),y
            sta  (cx16.r1),y
            dey
            bne  -
        +   lda  (cx16.r0),y
            sta  (cx16.r1),y
            rts

        _longcopy
            sta P8ZP_SCRATCH_B1         ; lsb(count) = remainder in last page
            tya
            tax                         ; x = num pages (1+)
            ldy  #0
        -   lda  (cx16.r0),y
            sta  (cx16.r1),y
            iny
            bne  -
            inc  cx16.r0+1
            inc  cx16.r1+1
            dex
            bne  -
            ldy  P8ZP_SCRATCH_B1
            bne  _copyshort
            rts
        }}
    }
    asmsub memset(uword mem @R0, uword numbytes @R1, ubyte value @A) clobbers(A,X,Y) {
        %asm {{
            ldy  cx16.r0
            sty  P8ZP_SCRATCH_W1
            ldy  cx16.r0+1
            sty  P8ZP_SCRATCH_W1+1
            ldx  cx16.r1
            ldy  cx16.r1+1
            jmp  prog8_lib.memset
        }}
    }

    asmsub memsetw(uword mem @R0, uword numwords @R1, uword value @AY) clobbers (A,X,Y) {
        %asm {{
            ldx  cx16.r0
            stx  P8ZP_SCRATCH_W1
            ldx  cx16.r0+1
            stx  P8ZP_SCRATCH_W1+1
            ldx  cx16.r1
            stx  P8ZP_SCRATCH_W2
            ldx  cx16.r1+1
            stx  P8ZP_SCRATCH_W2+1
            jmp  prog8_lib.memsetw
        }}
    }

    asmsub memcmp(uword address1 @R0, uword address2 @R1, uword size @AY) -> byte @A {
        ; Compares two blocks of memory
        ; Returns -1 (255), 0 or 1, meaning: block 1 sorts before, equal or after block 2.
        %asm {{
            sta  P8ZP_SCRATCH_W1
            sty  P8ZP_SCRATCH_W1+1
            ldx  P8ZP_SCRATCH_W1+1
            beq  _no_msb_size

        _loop_msb_size
            ldy  #0
        -   lda  (cx16.r0),y
            cmp  (cx16.r1),y
            bcs  +
            lda  #-1
            rts
        +   beq  +
            lda  #1
            rts
        +   iny
            bne  -
            inc  cx16.r0+1
            inc  cx16.r1+1
            dec  P8ZP_SCRATCH_W1+1
            dex
            bne  _loop_msb_size

        _no_msb_size
            lda  P8ZP_SCRATCH_W1
            bne  +
            rts

        +   ldy  #0
        -   lda  (cx16.r0),y
            cmp  (cx16.r1),y
            bcs  +
            lda  #-1
            rts
        +   beq  +
            lda  #1
            rts
        +   iny
            cpy  P8ZP_SCRATCH_W1
            bne  -

            lda #0
            rts
        }}
    }

    inline asmsub read_flags() -> ubyte @A {
        %asm {{
            php
            pla
        }}
    }

    inline asmsub clear_carry() {
        %asm {{
        clc
        }}
    }

    inline asmsub set_carry() {
        %asm {{
        sec
        }}
    }

    inline asmsub clear_irqd() {
        %asm {{
        cli
        }}
    }

    inline asmsub set_irqd() {
        %asm {{
        sei
        }}
    }

    inline asmsub irqsafe_set_irqd() {
        %asm {{
        php
        sei
        }}
    }

    inline asmsub irqsafe_clear_irqd() {
        %asm {{
        plp
        }}
    }

    asmsub save_prog8_internals() {
        %asm {{
            lda  P8ZP_SCRATCH_B1
            sta  save_SCRATCH_ZPB1
            lda  P8ZP_SCRATCH_REG
            sta  save_SCRATCH_ZPREG
            lda  P8ZP_SCRATCH_W1
            sta  save_SCRATCH_ZPWORD1
            lda  P8ZP_SCRATCH_W1+1
            sta  save_SCRATCH_ZPWORD1+1
            lda  P8ZP_SCRATCH_W2
            sta  save_SCRATCH_ZPWORD2
            lda  P8ZP_SCRATCH_W2+1
            sta  save_SCRATCH_ZPWORD2+1
            rts
            .section BSS
        save_SCRATCH_ZPB1	.byte  ?
        save_SCRATCH_ZPREG	.byte  ?
        save_SCRATCH_ZPWORD1	.word  ?
        save_SCRATCH_ZPWORD2	.word  ?
            .send BSS
            ; !notreached!
        }}
    }

    asmsub restore_prog8_internals() {
        %asm {{
            lda  save_prog8_internals.save_SCRATCH_ZPB1
            sta  P8ZP_SCRATCH_B1
            lda  save_prog8_internals.save_SCRATCH_ZPREG
            sta  P8ZP_SCRATCH_REG
            lda  save_prog8_internals.save_SCRATCH_ZPWORD1
            sta  P8ZP_SCRATCH_W1
            lda  save_prog8_internals.save_SCRATCH_ZPWORD1+1
            sta  P8ZP_SCRATCH_W1+1
            lda  save_prog8_internals.save_SCRATCH_ZPWORD2
            sta  P8ZP_SCRATCH_W2
            lda  save_prog8_internals.save_SCRATCH_ZPWORD2+1
            sta  P8ZP_SCRATCH_W2+1
            rts
        }}
    }

    ; nothing is going to actually read these values, nor does the stack pointer matter at this point
    inline asmsub exit(ubyte returnvalue @A) {
        %asm {{
            jmp  p8_sys_startup.cleanup_at_exit
        }}
    }
    inline asmsub exit2(ubyte resulta @A, ubyte resultx @X, ubyte resulty @Y) {
        %asm {{
            jmp  p8_sys_startup.cleanup_at_exit
        }}
    }
    inline asmsub exit3(ubyte resulta @A, ubyte resultx @X, ubyte resulty @Y, bool carry @Pc) {
        %asm {{
            jmp  p8_sys_startup.cleanup_at_exit
        }}
    }

    inline asmsub progend() -> uword @AY {
        %asm {{
            lda  #<prog8_program_end
            ldy  #>prog8_program_end
        }}
    }

    inline asmsub progstart() -> uword @AY {
        %asm {{
            lda  #<prog8_program_start
            ldy  #>prog8_program_start
        }}
    }

    inline asmsub push(ubyte value @A) {
        %asm {{
            pha
        }}
    }

    inline asmsub pushw(uword value @AY) {
        %asm {{
            pha
            tya
            pha
        }}
    }

    inline asmsub push_returnaddress(uword address @XY) {
        %asm {{
            ; push like JSR would:  address-1,  MSB first then LSB
            cpx  #0
            bne  +
            dey
        +   dex
            tya
            pha
            txa
            pha
        }}
    }

    asmsub get_as_returnaddress(uword address @XY) -> uword @AX {
        %asm {{
            ; return the address like JSR would push onto the stack:  address-1,  MSB first then LSB
            cpx  #0
            bne  +
            dey
+           dex
            tya
            rts
        }}
    }

    inline asmsub pop() -> ubyte @A {
        %asm {{
            pla
        }}
    }

    inline asmsub popw() -> uword @AY {
        %asm {{
            pla
            tay
            pla
        }}
    }

    inline asmsub pushl(long value @R0R1_32) {
        %asm {{
            lda  cx16.r0
            pha
            lda  cx16.r0+1
            pha
            lda  cx16.r0+2
            pha
            lda  cx16.r0+3
            pha
        }}
    }

    inline asmsub popl() -> long @R0R1_32 {
        %asm {{
            pla
            sta  cx16.r0+3
            pla
            sta  cx16.r0+2
            pla
            sta  cx16.r0+1
            pla
            sta  cx16.r0
        }}
    }

    sub cpu_is_65816() -> bool {
        ; Returns true when you have a 65816 cpu, false when it's a 6502.
        return false
    }
}

cx16 {
    ; the sixteen virtual 16-bit registers that the CX16 has defined in the zeropage
    &uword r0  = $0002
    &uword r1  = $0004
    &uword r2  = $0006
    &uword r3  = $0008
    &uword r4  = $000a
    &uword r5  = $000c
    &uword r6  = $000e
    &uword r7  = $0010
    &uword r8  = $0012
    &uword r9  = $0014
    &uword r10 = $0016
    &uword r11 = $0018
    &uword r12 = $001a
    &uword r13 = $001c
    &uword r14 = $001e
    &uword r15 = $0020

    &word r0s  = $0002
    &word r1s  = $0004
    &word r2s  = $0006
    &word r3s  = $0008
    &word r4s  = $000a
    &word r5s  = $000c
    &word r6s  = $000e
    &word r7s  = $0010
    &word r8s  = $0012
    &word r9s  = $0014
    &word r10s = $0016
    &word r11s = $0018
    &word r12s = $001a
    &word r13s = $001c
    &word r14s = $001e
    &word r15s = $0020

    &ubyte r0L  = $0002
    &ubyte r1L  = $0004
    &ubyte r2L  = $0006
    &ubyte r3L  = $0008
    &ubyte r4L  = $000a
    &ubyte r5L  = $000c
    &ubyte r6L  = $000e
    &ubyte r7L  = $0010
    &ubyte r8L  = $0012
    &ubyte r9L  = $0014
    &ubyte r10L = $0016
    &ubyte r11L = $0018
    &ubyte r12L = $001a
    &ubyte r13L = $001c
    &ubyte r14L = $001e
    &ubyte r15L = $0020

    &ubyte r0H  = $0003
    &ubyte r1H  = $0005
    &ubyte r2H  = $0007
    &ubyte r3H  = $0009
    &ubyte r4H  = $000b
    &ubyte r5H  = $000d
    &ubyte r6H  = $000f
    &ubyte r7H  = $0011
    &ubyte r8H  = $0013
    &ubyte r9H  = $0015
    &ubyte r10H = $0017
    &ubyte r11H = $0019
    &ubyte r12H = $001b
    &ubyte r13H = $001d
    &ubyte r14H = $001f
    &ubyte r15H = $0021

    &byte r0sL  = $0002
    &byte r1sL  = $0004
    &byte r2sL  = $0006
    &byte r3sL  = $0008
    &byte r4sL  = $000a
    &byte r5sL  = $000c
    &byte r6sL  = $000e
    &byte r7sL  = $0010
    &byte r8sL  = $0012
    &byte r9sL  = $0014
    &byte r10sL = $0016
    &byte r11sL = $0018
    &byte r12sL = $001a
    &byte r13sL = $001c
    &byte r14sL = $001e
    &byte r15sL = $0020

    &byte r0sH  = $0003
    &byte r1sH  = $0005
    &byte r2sH  = $0007
    &byte r3sH  = $0009
    &byte r4sH  = $000b
    &byte r5sH  = $000d
    &byte r6sH  = $000f
    &byte r7sH  = $0011
    &byte r8sH  = $0013
    &byte r9sH  = $0015
    &byte r10sH = $0017
    &byte r11sH = $0019
    &byte r12sH = $001b
    &byte r13sH = $001d
    &byte r14sH = $001f
    &byte r15sH = $0021

     ; signed long versions
    &long r0r1sl  = $0002
    &long r2r3sl  = $0006
    &long r4r5sl  = $000a
    &long r6r7sl  = $000e
    &long r8r9sl  = $0012
    &long r10r11sl = $0016
    &long r12r13sl = $001a
    &long r14r15sl = $001e

    ; boolean versions
    &bool r0bL  = $0002
    &bool r1bL  = $0004
    &bool r2bL  = $0006
    &bool r3bL  = $0008
    &bool r4bL  = $000a
    &bool r5bL  = $000c
    &bool r6bL  = $000e
    &bool r7bL  = $0010
    &bool r8bL  = $0012
    &bool r9bL  = $0014
    &bool r10bL = $0016
    &bool r11bL = $0018
    &bool r12bL = $001a
    &bool r13bL = $001c
    &bool r14bL = $001e
    &bool r15bL = $0020

    &bool r0bH  = $0003
    &bool r1bH  = $0005
    &bool r2bH  = $0007
    &bool r3bH  = $0009
    &bool r4bH  = $000b
    &bool r5bH  = $000d
    &bool r6bH  = $000f
    &bool r7bH  = $0011
    &bool r8bH  = $0013
    &bool r9bH  = $0015
    &bool r10bH = $0017
    &bool r11bH = $0019
    &bool r12bH = $001b
    &bool r13bH = $001d
    &bool r14bH = $001f
    &bool r15bH = $0021



    asmsub save_virtual_registers() clobbers(A,Y) {
        %asm {{
            ldy  #31
    -       lda  cx16.r0,y
            sta  _cx16_vreg_storage,y
            dey
            bpl  -
            rts
            .section BSS
    _cx16_vreg_storage
            .word 0,0,0,0,0,0,0,0
            .word 0,0,0,0,0,0,0,0
            .send BSS
            ; !notreached!
        }}
    }

    asmsub restore_virtual_registers() clobbers(A,Y) {
        %asm {{
            ldy  #31
    -       lda  save_virtual_registers._cx16_vreg_storage,y
            sta  cx16.r0,y
            dey
            bpl  -
            rts
        }}
    }
}

p8_sys_startup{
    ; since %option no_sysinit doesn't make sense on NES target and thus the distinction between phases
    ; that other platforms have doesn't matter here, this target repurposes them in a different way: 
    ; init_system() initializes non-graphical stuff before PPU is ready to be written to. 
    ; init_system_phase2() handles all the graphical stuff, since it runs after PPU is warmed up.
    ; It would be very beneficial if prog8's codegen did some kind of var init between the two
    asmsub init_system(){
        %asm{{
            sei          ; disable IRQs
            ldx #$40
            stx nes.JOYPAD2    ; disable APU frame IRQ
            ldx #0          ; now X = 0
            stx nes.PPUCTRL    ; disable NMI
            stx nes.PPUMASK    ; disable rendering
            stx nes.DMC_FREQ    ; disable DMC IRQs

            bit nes.PPUSTATUS   ; reset vblank flag
            #sys.waitvsync2      ; First wait for vblank to make sure PPU is ready

            lda #<nes.nmi_handler
            sta nes.nmi_vec
            lda #>nes.nmi_handler
            sta nes.nmi_vec+1
            lda #<nes.irq_handler
            sta nes.irq_vec
            lda #>nes.irq_handler
            sta nes.irq_vec+1

            
            rts
        }}
    }
    asmsub init_system_phase2(){
        %asm{{
            #sys.waitvsync2
            lda nes.PPUSTATUS

            lda #>nes.PALETTES_PPUADDR
            sta nes.PPUADDR
            lda #<nes.PALETTES_PPUADDR
            sta nes.PPUADDR
            lda #$0F
            sta nes.PPUDATA
            lda #$38
            sta nes.PPUDATA
            lda #$05
            sta nes.PPUDATA
            lda #$22
            sta nes.PPUDATA

            lda #>nes.PALETTES_PPUADDR
            sta nes.PPUADDR
            lda #<nes.PALETTES_PPUADDR+16
            sta nes.PPUADDR
            ldx #0
        -
            lda _sprite_pallettes, x
            sta nes.PPUDATA
            inx
            cpx #12
            bne -

            lda #%10001000
            sta nes.temp_PPUCTRL
            sta nes.PPUCTRL

            lda #%00001010
            sta nes.temp_PPUMASK

            cli

            rts
        _sprite_pallettes
            .byte $0f,$27,$14,$30,  $00,$28,$17,$0f,  $0f,$29,$09,$2d
            ; !notreached!
        }}
    }

    ; since we can't leave NES, we instead halt the entire CPU by trapping it in an infinite loop 
    ; and by silencing interrupt sources. This will probably cause sprites to glitch, but we don't 
    ; care about that at this point. We do mute the sound though.
    asmsub cleanup_at_exit() {
        %asm{{
            sei
            lda nes.temp_PPUCTRL
            and #%01111111
            sta nes.PPUCTRL
            lda #0
            sta nes.SND_CHN
        _loop
            jmp _loop
        }}
    }
}