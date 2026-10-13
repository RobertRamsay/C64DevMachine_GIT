/// WORKFLOW tour steps for: MUSIC_MAKER, SFX_MAKER, SID_MUSIC, SFX_DATA, SAMPLE, BYTE_DATA, TEXT_DATA, LOAD_ORG, LOAD_REU
/// (see scr_panel_help_workflow for the format)
function scr_panel_help_wf_sound() {
    return {
        MUSIC_MAKER : [
            { title: "COMPOSING FOR THE SID", text: "The Music Maker is a tracker for the C64's SID chip: three voices, each playing its own pattern of notes.\n\nThe usual path is: make instruments, write patterns, arrange them in the song order list, listen, then GENERATE NODES so your program plays it. Everything autosaves as you go.", targets: [] },
            { title: "START WITH INSTRUMENTS", text: "An instrument is the sound a note plays with. + PRESETS gives you ready-made ones to start from; + ADD makes a plain sawtooth you can shape yourself.\n\nClick an instrument to select it - new notes use the selected one. Click NAME: to rename it.", targets: ["INSTRUMENTS", "+ PRESETS", "+ ADD", "NAME:"] },
            { title: "SHAPE THE SOUND", text: "ADSR sets the volume envelope (attack, decay, sustain, release, each 0-15). PULSE sets the width for pulse waves.\n\nThe command box on the right is the instrument's per-frame program: $21 picks a waveform, N+12 changes pitch, D2 holds two frames, --- ends. The WAVE, NOTE and HOLD menus insert these for you.", targets: ["ADSR:", "PULSE:", "WAVE", "NOTE", "HOLD"] },
            { title: "WRITE NOTES", text: "Pick a voice column in the pattern grid and click a note cell. Your computer keyboard is the piano: the Z row plays OCTAVE minus one, the Q row the current octave.\n\nThe 1 or - key writes --- (note release), Backspace clears a cell, Ctrl+Z / Ctrl+Y undo and redo.", targets: ["PAT *", "OCTAVE:"] },
            { title: "PATTERN COMMANDS", text: "The cell right of each note takes an effect: a letter then two hex digits, such as 1XX slide up, 4XY vibrato or J00 tie.\n\nGUIDE opens the full list with every command explained.", targets: ["GUIDE"] },
            { title: "PATTERNS AND THE BANK", text: "Patterns live in a shared bank. + NEW adds an empty 64-row pattern; the < and > beside each column's LEN change that pattern's length (4-128).\n\nA pattern used in several places is the same data, so editing it changes every use.", targets: ["BANK:", "+ NEW", "PAT *"] },
            { title: "ARRANGE THE SONG", text: "The order list on the right is the song: each row picks a pattern for every voice. Click a cell for the next pattern, right-click for the previous, or type a number.\n\n+ ADD ROW extends the song, and LOOP decides whether it jumps back to its loop row at the end. + SONG adds another song to the same asset.", targets: ["+ ADD ROW", "LOOP", "NO LOOP", "+ SONG"] },
            { title: "LISTEN", text: "PLAY SONG (F1) plays from the start, PLAY HERE (F2) from the selected order row, PLAY PAT (F3) loops the current row's patterns, STOP (F4) stops.\n\nTEMPO is frames per row - lower is faster.", targets: ["PLAY SONG (F1)", "PLAY HERE (F2)", "PLAY PAT (F3)", "STOP (F4)", "TEMPO:"] },
            { title: "VOICES AND SOUND EFFECTS", text: "The VOICES buttons mute a voice in the preview and in the compiled tune.\n\nTurn one off to keep it free for sound effects from an SFX MAKER asset - for example music on voices 1 and 2, effects on 3.", targets: ["VOICES:", "1 O*", "2 O*", "3 O*"] },
            { title: "PUT IT IN YOUR PROGRAM", text: "GENERATE NODES adds the workspace nodes that play this song: the player code at free RAM, an init call at start-up and a play call once per frame in your main loop.\n\nClick it again after big changes to update them; the size follows your edits automatically.", targets: ["GENERATE NODES"] },
            { title: "SHARE AND EXPORT", text: "EXPORT SID saves a standalone .sid you can play in any SID player (it asks for a load address). EXPORT MM saves a .c64mm file to bring this asset into another project via IMPORT > MUSIC MAKER.", targets: ["EXPORT SID", "EXPORT MM"] }
        ],
        SFX_MAKER : [
            { title: "SOUND EFFECTS", text: "The SFX Maker holds a bank of sound effects (up to 64). Each one is a short SID program that plays on a single voice, so it can run alongside your music.\n\nIt starts with LASER, EXPLOSION and PICKUP to learn from. Everything autosaves.", targets: [] },
            { title: "PICK OR ADD AN EFFECT", text: "Click an effect in the list to select it, double-click to rename it. + ADD makes a new one, - REMOVE deletes the selected one.\n\nCOPY and PASTE also work between here and the Music Maker's instruments.", targets: ["INSTRUMENTS", "+ ADD", "- REMOVE", "COPY", "PASTE"] },
            { title: "ENVELOPE AND PULSE", text: "ADSR sets the volume envelope (each value 0-15). The release value also sets how long the sound fades after the program ends.\n\nPULSE sets the pulse width, used when the effect plays the $41 pulse waveform.", targets: ["ADSR:", "PULSE:"] },
            { title: "WRITE THE PROGRAM", text: "The command box is the effect itself, one step per line: $21 or $81 picks a waveform (saw, noise), N-12 shifts pitch from the base note, D3 holds three frames, L0 loops back, --- ends.\n\nClick in it to type; Ctrl+Enter keeps your edit. The legend underneath lists the commands.", targets: ["@LARGEST"] },
            { title: "PREVIEW IT", text: "PREVIEW plays the selected effect as it will sound; STOP silences it. Edits are kept before it plays.\n\nNOTE - and NOTE + move the base note that the N commands are relative to. LENGTH shows how many frames the effect lasts.", targets: ["PREVIEW", "STOP", "NOTE -", "NOTE +"] },
            { title: "PRIORITY", text: "When an effect is triggered while another is still playing, the higher PRIORITY wins, an equal one restarts, and a lower one is ignored.\n\nGive big sounds like explosions a higher number than footsteps or pickups.", targets: ["PRIORITY: *"] },
            { title: "PLAY IT FROM YOUR PROGRAM", text: "Add an SFX macro node and choose this asset, the effect and the voice. Its ACTION does the work: INIT once at start-up, PLAY to trigger the effect, UPDATE once per frame to advance it, STOP to silence it.\n\nThe effect code is built into your program where that node sits.", targets: [] },
            { title: "SHARING A VOICE WITH MUSIC", text: "Keep the effect voice free in the Music Maker with its VOICES buttons, for example music on 1 and 2, effects on 3.\n\nSID CHIP picks which chip the effects write to when a project uses more than one SID.", targets: ["SID CHIP: *"] }
        ],
        SAMPLE : [
            { title: "DIGITISED SOUND", text: "A SAMPLE is a short recorded sound (speech, a drum hit) played through the SID volume register as a 4-bit 'fourth voice'.\n\nThe original audio is kept, and the C64 version is rebuilt from it whenever you change a setting, so you can experiment freely.", targets: [] },
            { title: "IMPORT A WAV", text: "IMPORT WAV loads any WAV file - any rate, mono or stereo. It becomes the source shown in the top waveform.", targets: ["IMPORT WAV"] },
            { title: "TRIM IT", text: "Left-drag in the source waveform to move the nearer trim handle; only the lit part is used. Right-click resets the trim.\n\nTrim tightly: every extra fraction of a second costs memory.", targets: ["@LARGEST"] },
            { title: "COMPARE BY EAR", text: "PLAY SOURCE plays the trimmed original; PLAY C64 plays the encoded 4-bit version exactly as the C64 will output it. STOP ends the preview.\n\nThe lower waveform shows the 16 levels the C64 will actually use.", targets: ["PLAY SOURCE", "PLAY C64", "STOP"] },
            { title: "QUALITY AGAINST SIZE", text: "RATE sets the playback rate: higher is clearer but bigger and uses more CPU. GAIN, NORMALISE and COMPRESS set the loudness - watch for the clipping warning.\n\nThe OUTPUT line shows the samples, seconds and bytes it will take.", targets: [] },
            { title: "PACKING", text: "4-BIT packs two samples per byte for the best quality. 2-BIT DELTA packs four per byte: half the size, rougher sound.", targets: ["4-BIT", "2-BIT DELTA"] },
            { title: "THE TARGET SID", text: "Volume-register digis are loud on the 6581 SID but nearly silent on the 8580 without help. Pick 8580 and the player adds the boost they need.", targets: ["6581", "8580"] },
            { title: "USING THE SAMPLE", text: "A SAMPLE has no address of its own: whatever plays it emits the bytes. In the Music Maker, open SAMPLES, put this sample in a slot, then place notes on the DIGI lane - C-4 plays it at its own pitch.\n\nThe Music Maker encodes it at its own digi rate from the kept source.", targets: [] }
        ],
        SID_MUSIC : [
            { title: "A READY-MADE TUNE", text: "SID_MUSIC holds a .sid file made in another tracker, complete with its own player code. Your program just calls its init once and its play routine every frame.", targets: [] },
            { title: "IMPORT THE .SID", text: "IMPORT picks a .sid file. Its header supplies the load address, the init and play addresses and how many subtunes it has; they are shown below.\n\nUse the PLAY and STOP buttons under the title to listen, and < > to step through subtunes.", targets: ["IMPORT"] },
            { title: "WHERE IT LIVES", text: "ADDRESS is where the tune loads, taken from the file. SID player code only works at the address it was built for, so make sure nothing else in your project overlaps it - the SIZE and END values show how much it takes.", targets: ["ADDRESS:"] },
            { title: "MOVE IT IF IT CLASHES", text: "If the tune sits where your code or graphics need to go, set RELOCATE TO: with - and +, then press RELOCATE.\n\nThe player is patched and then checked by emulating the tune for the TEST time, and only applied if it still plays the same.", targets: ["RELOCATE TO:", "TEST * MIN", "RELOCATE"] },
            { title: "PLAY IT IN YOUR PROGRAM", text: "Add a SID macro node, pick this asset, the subtune and the volume. It calls init at start-up and play once per frame. The nodes that use the tune are listed under REFERENCED BY.", targets: [] }
        ],
        SFX_DATA : [
            { title: "GOATTRACKER EFFECTS", text: "SFX_DATA brings in sound effects made in GoatTracker 2. Each instrument in the song becomes one effect you can trigger from your program.\n\nTo build effects inside this app instead, use an SFX MAKER asset.", targets: [] },
            { title: "IMPORT A .SNG", text: "IMPORT picks a GoatTracker 2 .sng file. Edit the effects in GoatTracker and import again to update them - this panel is a read-only view.", targets: ["IMPORT"] },
            { title: "READ THE EFFECTS", text: "Each column is one instrument, numbered from 0, with its wavetable rows below: waveform on the left, pitch on the right, in hex. Scroll to see longer tables.", targets: ["0: *"] },
            { title: "MEMORY", text: "ADDRESS is where the effect data loads in C64 memory. Click it to type a new hex address if it overlaps something else.", targets: ["ADDRESS:"] },
            { title: "TRIGGER AN EFFECT", text: "Add an SFX macro node, pick this asset, the instrument number and the voice (1-3) to play it on. Keep that voice free of music while effects play. Nodes using this asset are listed under REFERENCED BY.", targets: [] }
        ],
        BYTE_DATA : [
            { title: "RAW BYTES", text: "BYTE_DATA is a block of bytes placed at its ADDRESS when the program is built - lookup tables, level layouts, anything your code reads.", targets: [] },
            { title: "ENTER THE BYTES", text: "EDIT (or clicking the content) opens a text editor. Write values as decimal, $hex or %binary, separated by commas, semicolons or new lines. Each value becomes one byte (0-255); anything unreadable is skipped.\n\nIMPORT loads the same kind of text from a file.", targets: ["EDIT", "IMPORT"] },
            { title: "SET THE ADDRESS", text: "Click ADDRESS: to type a new hex load address. The line under EDIT shows the byte count and the exact range it occupies, so you can point your code at it.", targets: ["ADDRESS:"] },
            { title: "SAVE GAME AREA", text: "USE AS SAVE FILE turns the asset into a zero-filled block of a chosen size, for save-game nodes to write and read at runtime.", targets: ["USE AS SAVE FILE: *"] }
        ],
        TEXT_DATA : [
            { title: "TEXT FOR YOUR PROGRAM", text: "TEXT_DATA stores text in C64 memory - messages, dialogue, scroller text. Nodes such as PRINT, text scrollers and strings read it from its address.", targets: [] },
            { title: "WRITE THE TEXT", text: "EDIT opens the text editor (clicking the preview does the same). IMPORT loads text from a file instead.\n\nThe counter shows the characters and bytes, including the closing zero byte.", targets: ["EDIT", "IMPORT"] },
            { title: "FIND OFFSETS", text: "While editing, CHAR POS shows where the cursor is. Select some text to see its START and END - type those into a PRINT node to show just that part. One PRINT handles up to 255 characters.", targets: [] },
            { title: "SET THE ADDRESS", text: "Click ADDRESS: to type a new hex load address if the text overlaps other data.", targets: ["ADDRESS:"] }
        ],
        LOAD_ORG : [
            { title: "A DISK FILE LIST", text: "LOAD_ORG lists assets that go on the D64 disk as their own files instead of inside the main BOOT program. That keeps the program small, and a LOADER node pulls each file into memory when you need it.", targets: [] },
            { title: "ADD ASSETS", text: "[+ ADD] picks a project asset to put on the disk. Each row shows its disk file name, size in bytes and blocks, and the memory range it loads into.\n\nAn asset can belong to only one LOAD_ORG or LOAD_REU.", targets: ["[+ ADD]"] },
            { title: "REMOVE AN ENTRY", text: "The X at the end of a row takes that file off the disk; the asset itself stays in the project.", targets: ["X"] },
            { title: "CHECK THE DISK", text: "The D64 SUMMARY at the bottom totals the files and blocks, plus the BOOT program size from the last build, so you can see how full the disk is.", targets: [] },
            { title: "LOAD AT RUNTIME", text: "Add a LOADER macro node, pick this LOAD_ORG and the file to load. Files that load into the same memory at different times (like levels) do not count as clashing.", targets: [] }
        ],
        LOAD_REU : [
            { title: "RAM EXPANSION", text: "LOAD_REU packs assets into a REU image - the C64's RAM Expansion Unit, up to 16 MB. At runtime a REU node copies an asset into C64 memory in a flash, which suits big things like bitmap animations.\n\nA project can have one LOAD_REU.", targets: [] },
            { title: "ADD ASSETS", text: "[+ ADD] picks a project asset to store in the REU. Each row shows its C64 address, its REU address and its size; double-click a name to open that asset.", targets: ["[+ ADD]"] },
            { title: "PACKING", text: "Entries on AUTO are placed by the packer. [AUTO PACK] sets every entry back to AUTO and packs the image again; a red REU address means two entries overlap.", targets: ["[AUTO PACK]", "AUTO"] },
            { title: "ORDER AND INDEX", text: "Drag the ::: handle to reorder entries of the same type. Bitmaps get an IDX number in this order, which a REU node in INDEXED mode uses to pick one by number.", targets: [":::"] },
            { title: "USE IT AT RUNTIME", text: "Add a REU macro node and pick an entry (or an index) to copy it to its C64 address. The REU image is written when you build; run it with a REU enabled in the emulator or on your hardware.", targets: [] }
        ]
    };
}
