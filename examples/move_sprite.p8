%import sprites

main{
    sub start(){
        sprites.init()
        sprites.set_graphic(1, 16)
        sprites.set_attributes(1, 0)
        sprites.set_palette(1, 0)
        repeat{
            ubyte j1
            const ubyte speed =5
            j1, void = nes.joyfetch()
            if j1&nes.JOY_UP!=0{
                sprites.movey(1, -5)
            }
            if j1&nes.JOY_DOWN!=0{
                sprites.movey(1, 5)
            }
            if j1&nes.JOY_LEFT!=0{
                sprites.movex(1, -5)
            }
            if j1&nes.JOY_RIGHT!=0{
                sprites.movex(1, 5)
            }
            sys.waitvsync()
        }
    }
}