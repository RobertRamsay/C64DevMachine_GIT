# ALIEN BREED 64 generator

Builds the **PORTS > GAMES > ALIEN BREED 64** project
(`C64DMResources/TEMPLATES/ALIEN_BREED.json`). It is an unofficial C64
conversion pitch of Team17's Alien Breed (Amiga, 1991). One project serves
two machines:

| Machine | Audio |
|---|---|
| Stock C64 | Title theme from the Music Maker (`AB_MUSIC`), effects from the SFX Maker (`AB_SFX`, voice 3) |
| C64 Ultimate (or any 17xx REU) | `AB_REU` (LOAD_REU) carries the theme and every effect as 4-bit samples. An NMI DMAs them byte by byte into `$D418`. RUN ON ULTIMATE uploads the image and F5 attaches it in VICE. UP on the title switches to it. |

Requires Node 22+ (no packages).

```
node build.mjs                 # writes TEMPLATES/ALIEN_BREED.json + out/alienbreed.prg/.reu
node build.mjs OUT.json        # somewhere else
node editor.mjs                # round trip through a running, paired Dev Machine (MCP):
                               # load, native build, compare its PRG with ours
```

## The game

- 8-way, double-buffered char scroll over a 128 x 96 char deck (two decks, RLE metatiles).
- HUD in rows 21-23. An FLD split from line `$D7` keeps it still whatever the vertical scroll.
- 8-way marine at 1.5 px a frame. Two bullets at a time; ammo, keys, credits, energy and lives.
- Aliens climb out of vents near you, chase along walls and bite.
- Keys open doors. Intex terminals sell ammo, first aid, key passes and lives.
- **Deck 1:** find the lift.
- **Deck 2:** shoot out the 4 reactor cores, then reach the lift before the 1:30 self-destruct.

## Memory

| Range | Use |
|---|---|
| `$0801-$1FFF` | Boot + low code |
| `$2000-$2BFF` | SFX column (editor macros) |
| `$2C00-$3FFF` | Music column (editor macros) |
| `$4000/$4400` | Screens A/B |
| `$4800` | Station charset |
| `$5000` | Sprites |
| `$6000-$77FF` | High code |
| `$7800` | Title charset |
| `$8000-$9FFF` | Data |
| `$A000-$CFFF` | The expanded deck |
| `$E000-$FFEF` | Top code (runs with the KERNAL banked out) |

The full map is in `defs.mjs`.

## Files

| File | Contents |
|---|---|
| `defs.mjs` | Memory map, variables, constants |
| `art.mjs` | Charsets (autotiled walls, floors, pickups, lift, cores), logo, sprites |
| `levels.mjs` | Decks as rooms + corridors. Carving, a key/door reachability check, metatile RLE |
| `texts.mjs` | HUD, messages, Intex / end pages, title screen |
| `audio.mjs` | Music Maker song, SFX Maker effects, REU converter (WAV in `audio_src/`, else a rendered version) |
| `code_core.mjs` | Boot, IRQs, REU stream, sound dispatch, helpers |
| `code_game.mjs` | Title, deck load, game states, marine, weapons, aliens |
| `code_view.mjs` | Camera + redraw, sprites, HUD, pages, Intex |

The code blocks use the CODE BLOCK dialect via `../golazo_gen/asm.mjs`:
constants only in `.byte`, no label arithmetic, and zero-page names `Z_*`.

## Tests

| Command | What it does |
|---|---|
| `node shots.mjs tests/walk.json 6,12 name` | Scripted joystick build + VICE screenshots |
| `node machine.mjs PRG seconds [--reu img]` | Headless C64 (6502 + raster IRQ + CIA2 NMI + REU): SID / `$D418` activity |
| `node soak.mjs PRG 120` | Random walker with fire held. State every 5 s, frame-loop check |
| `node deck2.mjs PRG` | Deck 2: shoot the cores, self-destruct, lift, back to the title |
| `node hybrid.mjs script out.prg` | The editor's build with a test joystick spliced in |
| `node compare.mjs a.prg b.prg` | Byte compare of two PRGs |

## Audio sources

The Amiga data in the GamesNostalgia package is packed in Team17's own
formats. Only the menu module's sample names (DEEPVOICEBASS, RESOBASS, SNARE,
HIHAT, MINCHOIR, ...) were readable, so the theme is a new composition in
that style. Put real WAVs in `audio_src/` (see its README) and rebuild to
replace any REU clip.
