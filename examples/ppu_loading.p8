main{
    sub start(){
        ; as of now, prog8's variable initialisation is not always working properly due to "ROMability issues",
        ; so it's better to initialise these values. PR that fixes this has been already made
        nes.ppurqfi=0
        nes.ppurqfo=0
        nes.ppurqbuf[0]=0
        nes.ppu_memsetnow($2000+(13*32), 96, 3, false)
        nes.ppu_sendrq_memset($2000+128+5, 5, $c2, true)
        nes.ppu_sendrq_data($2000+(2*32)+3, len("greetings from ppu!"), "greetings from ppu!", false)
        nes.ppu_loadnow($2000+(9*32), len("this message was bruteforced"), "this message was bruteforced", false)
        
        repeat{
        }
    }
}