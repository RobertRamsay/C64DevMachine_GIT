# ALIEN BREED 64 generator

Builds the **PORTS > GAMES > ALIEN BREED 64** project
(`C64DMResources/TEMPLATES/ALIEN_BREED.json`). It is an unofficial C64
conversion pitch of Team17's Alien Breed (Amiga, 1991). One project serves
two machines:

| Machine | Audio |
|---|---|
| Stock C64 | The original title tune (ALIENMENU) converted note for note into the Music Maker (`AB_MUSIC`); effects from the SFX Maker (`AB_SFX`, voice 3) |
| C64 Ultimate (or any 17xx REU) | `AB_REU` (LOAD_REU) carries the original tune, rendered from its own Amiga samples, plus every effect, as 4-bit samples. An NMI DMAs them byte by byte into `$D418`. RUN ON ULTIMATE uploads the image and F5 attaches it in VICE. |

## Samples

Two digitised sounds play on both machines: "Welcome to Intex Systems" when a terminal opens, and the ammo-clip reload when you pick up or buy ammo.

- **Stock C64:** 4-bit, two samples per byte, at about 4.6 kHz. The voice lives in the 4 KB of RAM under the I/O at `$D000` (BOOT copies it there from `$A000`) and the clip in the data area. An NMI player banks the I/O out for each read. The SID effects pause while a sample plays.
- **C64 Ultimate / REU:** the same sounds are REU clips 11 and 12, at 5.5 kHz.
- **Sources:** `audio_src/intex_voice.wav` is a stand-in made with the Windows voice "Microsoft Hazel". Replace it with the original line and rebuild. `audio_src/clip.wav`, if present, replaces the synthesised reload.

## Building for real hardware

The project uses the **PRG EXO** build target. The plain PRG runs from `$0801` to `$FF3F`, so a disk load would write its `$D000-$DFFF` bytes into the I/O chips and fail. The Exomizer PRG unpacks safely, is about 11 KB, and loads from disk on a stock C64.

## Title

The title is `AB_TITLE_BMP`, a Koala BITMAP (`art/title.kla`) in VIC bank 3 at `$E000`. It carries sprite text in the logo's tall font and shading (`AB_TITLE_SPR`, drawn by `titlespr.mjs`):

- **Top band:** C64 | C64U. LEFT picks the stock C64 (SID); RIGHT picks the C64 Ultimate (REU stream), and only works with an REU. With an REU present, C64U is selected from the start.
- **Bottom band:** PRESS FIRE | TO PLAY.

A raster IRQ at line `$A0` moves the sprites from the top band to the bottom one. The editor emits the bitmap's screen and colour at `$C400` / `$C7E8`, which is inside the level area, so BOOT saves them to `$7800` and the title puts them back.

Requires Node 22+ (no packages).

```
node build.mjs                 # writes TEMPLATES/ALIEN_BREED.json + out/alienbreed.prg/.reu
node build.mjs OUT.json        # somewhere else
node editor.mjs                # round trip through a running, paired Dev Machine (MCP):
                               # load, native build, compare its PRG with ours
```

## The game

- 8-way, double-buffered char scroll over a 128 x 96 char deck (two decks, stamp-id maps in the AB_DECKS META_TILESET, editable in the map editor).
- HUD in rows 21-23. An FLD split from line `$D7` keeps it still whatever the vertical scroll.
- 8-way marine at 1.5 px a frame. Two bullets at a time; ammo, keys, credits, energy and lives.
- Aliens climb out of vents near you, chase along walls and bite.
- Keys open doors. Intex terminals sell ammo, first aid, key passes and lives.
- **Deck 1:** find the lift.
- **Deck 2:** shoot out the 4 reactor cores, then reach the lift before the 1:30 self-destruct.

## Memory

| Range | Use |
|---|---|
| `$0801-$118F` | Boot + low code |
| `$1190-$19FF` | SFX column (editor macros) |
| `$1A00-$3FFF` | Music column (editor macros) |
| `$4000/$4400` | Screens A/B |
| `$4800` | Station charset |
| `$5000` | Sprites |
| `$5C40-$5FFF` | Deck tables, HUD template, ammo-clip sample |
| `$6000-$77FF` | High code |
| `$7800-$7FCF` | Title screen + colour, saved at boot |
| `$8000-$9FFF` | Data: char types, title sprite text, texts, AB_DECKS (stamp table + both deck maps) |
| `$A000-$CFFF` | The expanded deck (at load: the Intex voice at `$A000`, title screen/colour at `$C400`) |
| `$D000-$DFFF` | RAM under the I/O: the Intex voice (stock C64) |
| `$E000-$FF3F` | Title bitmap (bank 3, under the KERNAL) |

The full map is in `defs.mjs`.

## Asset groups

TITLE, GRAPHICS, DECKS, TEXT + HUD, SID AUDIO, SAMPLES, REU AUDIO.
The decks are the AB_DECKS META_TILESET (2 x 2 char stamps on AB_CHARS),
exported as STAMP IDS: the stamp table, then one map per deck, each cropped
to the part of the 64 x 48 grid that is not void. Its crop (x, y, w, h in
tiles) sits in DECK_TAB0/1 bytes 11-14, so a deck edited in the map editor
loads as long as its size stays the same. A resized map needs the crop
updated in the deck table. All 64 stamp slots are exported (32 used): a new
stamp goes into a blank slot, so the maps never move.

## Files

| File | Contents |
|---|---|
| `defs.mjs` | Memory map, variables, constants |
| `art.mjs` | Charset (autotiled walls, floors, pickups, lift, cores), sprites |
| `titlespr.mjs` | Title sprite text: font, shading, layout |
| `koala.mjs` | Koala reader / PNG preview (`node koala.mjs art/title.kla out.png`) |
| `levels.mjs` | Decks as rooms + corridors. Carving, a key/door reachability check, the crop to stamp ids for AB_DECKS |
| `texts.mjs` | HUD, messages, Intex / end pages |
| `audio.mjs` | Music Maker song, SFX Maker effects, REU converter (WAV in `audio_src/`, else the module render / synthesised effects) |
| `bpsm.mjs` | Reader for Brian Postma SoundMon v2 modules (the format of the title tune) |
| `bp2mm.mjs` | SoundMon to Music Maker: patterns, order + transposes, tempo, 4 voices onto 3, SID instruments |
| `bprender.mjs` | Renders the module to PCM with its own samples (the REU title clip; `node bprender.mjs FILE 0 out.wav`) |
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
| `node deckcheck.mjs PRG` | Loads both decks in the game: the `$A000` map, vents and cores found, the marine start |
| `node marinesheet.mjs out.png` | The marine frames (walk A, walk B, recoil per direction) as a PNG |
| `node deck2.mjs PRG` | Deck 2: shoot the cores, self-destruct, lift, back to the title |
| `node hybrid.mjs script out.prg` | The editor's build with a test joystick spliced in |
| `node compare.mjs a.prg b.prg` | Byte compare of two PRGs |

## Audio sources

`audio_src/alienmenu.bp` is the title tune exactly as stored on the Amiga disk (Disk.2, offset `$2C00`): a Brian Postma SoundMon v2 module by Allister Brimble. It is Team17's music and is included for this pitch only.

The SID version keeps every note, transpose and tempo change. The SoundMon synth instruments become Music Maker instrument programs. Instrument 1, the DEEPVOICEBASS "gargle" that opens the tune, is a sawtooth with a fast warble stepping down in pitch. Each sequence step drops the least important of the four Amiga voices, so empty and doubled voices go first.

Put WAVs in `audio_src/` (see its README) and rebuild to replace any REU clip.
