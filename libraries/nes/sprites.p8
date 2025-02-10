%option no_symbol_prefixing, ignore_unused

; api isn't 1:1 with cx16 equivalent due to hardware differences

sprites{
    ubyte[256] @shared @alignpage OAM_buffer

    %asm{{
    update  .macro
        lda #0
        sta nes.OAMADDR
        lda #>sprites.OAM_buffer
        sta nes.OAMDMA
        .endmacro
    }}
    inline asmsub update(){
        %asm{{
            #sprites.update
        }}
    }

    ; run once at the start of the program.
    ; inits stuff for us, so that it all just works.
    asmsub init() clobbers(A){
        %asm{{
            lda nes.temp_PPUCTRL
            and #%01111111
            sta nes.PPUCTRL

            lda nes.nmi_vec
            sta _orig_nmivec
            lda nes.nmi_vec+1
            sta _orig_nmivec+1

            lda #<_nmi_oam
            sta nes.nmi_vec
            lda #>_nmi_oam
            sta nes.nmi_vec+1

            lda nes.temp_PPUMASK
            ora #$10
            sta nes.temp_PPUMASK

            lda nes.PPUSTATUS ; avoid accidental NMI runs
            lda nes.temp_PPUCTRL
            sta nes.PPUCTRL

            rts
        _nmi_oam
            pha
            #sprites.update
            pla
            jmp (_orig_nmivec)
            .section BSS
        _orig_nmivec .word ?
            .send BSS
            ; !notreached!
        }}
    }

    sub pos(ubyte spritenum, ubyte xpos, ubyte ypos){
        OAM_buffer[spritenum*4+3] = xpos
        OAM_buffer[spritenum*4] = ypos
    }
    sub setx(ubyte spritenum, ubyte xpos){
        OAM_buffer[spritenum*4+3] = xpos
    }
    sub sety(ubyte spritenum, ubyte ypos){
        OAM_buffer[spritenum*4] = ypos
    }
    sub move(ubyte spritenum, byte dx, byte dy){
        spritenum*=4
        OAM_buffer[spritenum+3]=OAM_buffer[spritenum+3]+(dx as ubyte)
        OAM_buffer[spritenum]=OAM_buffer[spritenum]+(dy as ubyte)
    }
    sub movex(ubyte spritenum, byte dx){
        spritenum*=4
        OAM_buffer[spritenum+3]=OAM_buffer[spritenum+3]+(dx as ubyte)
    }
    sub movey(ubyte spritenum, byte dy){
        spritenum*=4
        OAM_buffer[spritenum]=OAM_buffer[spritenum]+(dy as ubyte)
    }
    sub set_palette(ubyte spritenum, ubyte palettenum){
        spritenum*=4
        OAM_buffer[spritenum+2] = (palettenum & %011)|(OAM_buffer[spritenum+2] & %11111100)
    }
    const ubyte ATTRIB_HFLIP = $40
    const ubyte ATTRIB_VFLIP = $80
    const ubyte ATTRIB_BEHINDBG = $20
    sub set_attributes(ubyte spritenum, ubyte attribs){
        spritenum*=4
        OAM_buffer[spritenum+2] = (OAM_buffer[spritenum+2] & %011)|(attribs & %11111100)
    }
    sub set_graphic(ubyte spritenum, ubyte tileid){
        OAM_buffer[spritenum*4+1] = tileid
    }


    sub getx(ubyte spritenum) -> ubyte{
        return OAM_buffer[spritenum*4+3]
    }
    sub gety(ubyte spritenum) -> ubyte{
        return OAM_buffer[spritenum*4+3]
    }
    sub getxy(ubyte spritenum) -> ubyte, ubyte{
        spritenum*=4
        return OAM_buffer[spritenum+3], OAM_buffer[spritenum]
    }
    sub get_palette(ubyte spritenum) -> ubyte{
        return (OAM_buffer[spritenum*4+2] & %011)+4
    }
    sub get_attributes(ubyte spritenum) -> ubyte{
        return OAM_buffer[spritenum*4+2] & %11111100
    }
    sub get_graphic(ubyte spritenum) -> ubyte{
        return OAM_buffer[spritenum*4+1]
    }
    
}