This is a repo where the NES target is being developed and tested.

## Compiling roms
Currently, in order to build a program for NES, run this on the sourcecode of choice:
```sh
$ prog8c -target nes-nrom.properties program.p8 -slabsgolden -varsgolden
$ ./truncateoutput.sh program.prg program.nes
```

You may replace `prog8c` with any kind of regular way you usually run the prog8 compiler.

`truncateoutput.sh` requires you to have `dd` installed on your system. If you're using windows, you can install MSYS2, WSL or Cygwin environments or you can use some kind of windows ports of `dd`, that can work with regular binary files. Manually removing `$0000-$7ff0` bytes from the outputed binary with a hex editor is also an option.

In case you have some kind of directory errors, such as in `.binary "../default-nrom.chr"` or regarding the `./libraries/nes` path, feel free to modify the .properties file and play with compiler options to fit your needs.

## TODO
- Implement `textio` library
- `sprites` library: implement helpers for sprite combinations (16x16 sprites, 16x24, 16x16 using tall sprites, etc.)
- MMC3 mapper config (or other mappers)
- Some kind of set of subroutines, that allow for "building" a *PPU request*, so that one doesn't have to iterate over data multiple times
- Regarding sound (low priority):
  - helpers functions for sound?
  - .nsf playback? if possible? (I think it isn't)
  - try to make use of FamiTracker's (and its forks') export options
- Some stuff to make it easier to make VBlank handlers in Prog8 (like in cx16 target)
- Other helpers like in other targets
- Add more images to the default.chr