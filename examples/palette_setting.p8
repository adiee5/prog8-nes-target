%import sprites

main{
    sub start(){
        ; as of now, prog8's variable initialisation is not always working properly due to "ROMability issues",
        ; so it's better to initialise these values. PR that fixes this has been already made
        nes.ppurqfi=0
        nes.ppurqfo=0
        nes.ppurqbuf[0]=0
        sprites.init()
        nes.bgcolor_set($21)
        nes.palette_set(4, $10, $0f, $30)
        sprites.pos(1, 20, 20)
        sprites.pos(2, 28, 20)
        sprites.pos(3, 20, 28)
        sprites.pos(4, 28, 28)
        sprites.set_graphic(1, $0b)
        sprites.set_graphic(2, $0c)
        sprites.set_graphic(3, $1b)
        sprites.set_graphic(4, $1c)
        repeat{
        }
    }
}