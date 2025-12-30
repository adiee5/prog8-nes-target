;%option romable ; as of prog8 v12.0.1, this option doesn't really work and code seems to compile fine without it anyways.

main{
    sub start(){
        ubyte i, j

        nes.ppu_memsetnow($2000, $3C0, $FC, false) ; tile of the background

        for i in 0 to 255 step 16{
            while not nes.ppu_buildrq_start($2020+(i as uword)*2, false) {
                sys.waitvsync()
            }
            for j in 0 to 15{
                while not nes.ppu_buildrq_push(i+j) {
                    sys.waitvsync()
                }
            }
            nes.ppu_buildrq_send()
        }
        
        ; press 'select' to change the tileset
        repeat{
            j, void = nes.joyfetch()
            if j&nes.JOY_SELECT!=0{
                while j&nes.JOY_SELECT!=0 {
                    j, void = nes.joyfetch()
                }
                nes.temp_PPUCTRL^=$10
            }
        }
    }
}