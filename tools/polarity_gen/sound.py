"""POLARITY music (MUSIC_MAKER) and sound effects (SFX_MAKER) metas.

An original tune, written to be sung: clear four-bar phrases (a question,
then its answer) over real chord changes, rather than riffs over a drone.
Two voices carry it, as voice 3 belongs to the game's sound effects:
  - voice 1 is the harmony: the bass plays each chord broken up (root,
    fifth, octave, tenth...) with the kick and snare folded into its notes,
    so the full chord is heard even with one voice;
  - voice 2 is the tune: a soft triangle flute for the verses, a brighter
    pulse lead with delayed vibrato for the chorus, and a music-box bell
    playing the chords for the intro and the interlude.
6 frames per row, 16 rows per bar, 2-bar patterns (one chord a bar).
Form: intro (music box) -> Sunny's verse (C major) -> chorus -> Hex's
verse (A minor, with E major pulling home) -> music-box interlude ->
verse -> chorus, then back to the verse (about 100 s per loop).
"""
import copy

NOTES = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]

def transpose(note, semis):
    i = NOTES.index(note[:2]) + int(note[2]) * 12 + semis
    return NOTES[i % 12] + str(i // 12)


# ------------------------------------------------------------------ instruments
def ins(name, main, loop_to=None, pulse=None, cutoff=None, a=0, d=9, s=8, r=4, pw=2048, filt=0, end=False):
    """main: program tokens. loop_to: token index the program loops back to
    (holds the note). pulse: (speed, frames) sweep up/down, keeps running.
    cutoff: (speed, frames) filter sweep run on each note, then held."""
    toks = list(main)
    if end:
        toks.append("---")
    elif loop_to is not None:
        toks.append("L%d" % loop_to)
    if pulse:
        q, dd = pulse
        start = len(toks) + 1
        toks += ["~PULSE+", "Q+%d" % q, "D%d" % dd, "Q-%d" % q, "D%d" % dd, "L%d" % start]
    if cutoff:
        c, dd = cutoff
        hold = len(toks) + 3
        toks += ["~FILTER", "C%+d" % c, "D%d" % dd, "C+0", "D1", "L%d" % hold]
    return {"name": name, "text": "\n".join(toks), "attack": float(a), "decay": float(d),
            "sustain": float(s), "release": float(r), "pulse_width": float(pw), "filt": float(filt),
            "vib_delay": 0.0, "vib_speed": 0.0, "vib_depth": 0.0, "dirty": True}

INSTRUMENTS = [
    # voice 1: a round filtered pulse bass (the cutoff opens on each note and
    # closes again), plus the same bass with a kick or a snare on its front
    ins("BASS", ["$41", "C$500", "N", "D1"], 3, (64, 32), (-10, 40),
        a=0, d=8, s=9, r=6, pw=1200, filt=1),
    ins("KICK BASS", ["$11", "N=60", "D1", "N=44", "D1", "N=36", "D1", "$41", "N", "D1"], 9, (64, 32),
        a=0, d=8, s=9, r=6, pw=1200, filt=1),
    ins("SNARE BASS", ["$81", "N=72", "D1", "$41", "N=48", "D1", "$81", "N=70", "D1", "$41", "N", "D1"], 11, (64, 32),
        a=0, d=8, s=9, r=6, pw=1200, filt=1),
    # voice 2: the tune
    ins("FLUTE", ["$11", "N", "D10", "V$23", "D1"], 4, a=1, d=6, s=11, r=7),
    ins("SWEET LEAD", ["$41", "N+12", "D1", "N", "D12", "V$24", "D1"], 6, (12, 64),
        a=0, d=4, s=11, r=8, pw=1700),
    ins("BELL", ["$11", "N+12", "D1", "N", "D1"], end=True, a=0, d=9, s=0, r=9),
]
I = {n["name"]: i for i, n in enumerate(INSTRUMENTS)}
for _ins in INSTRUMENTS:                      # absolute notes are N=0 .. N=95
    for _t in _ins["text"].splitlines():
        if _t.startswith("N="):
            assert 0 <= int(_t[2:]) <= 95, (_ins["name"], _t)


# ------------------------------------------------------------------ patterns
def empty_step():
    return {"empty": True, "cmd_val": 0.0, "instr_idx": -1.0, "note": "", "cmd": -1.0}

def step(note, instr):
    return {"empty": False, "cmd_val": 0.0, "instr_idx": float(instr), "note": note, "cmd": -1.0}

def pattern(name, notes):
    steps = [empty_step() for _ in range(32)]
    for pos, note, instr in notes:
        assert 0 <= pos < 32 and steps[pos]["empty"], (name, pos)
        steps[pos] = step(note, instr)
    return {"pattern_len": 32.0, "steps": steps, "name": name}

# chord name -> (bass root, third in semitones)
CHORDS = {"C": ("C-3", 4), "Am": ("A-2", 3), "F": ("F-2", 4), "G": ("G-2", 4), "Em": ("E-2", 3),
          "Dm": ("D-3", 3), "E": ("E-2", 4)}

def bass(chords, drums=True):
    """Two bars, one chord each, broken up in eighths: root, fifth, octave,
    tenth, root, fifth, octave, fifth. Kick on beat 1 (and 3 with drums),
    snare on beats 2 and 4 (with drums)."""
    notes = []
    for b, ch in enumerate(chords):
        root, third = CHORDS[ch]
        tones = [root, transpose(root, 7), transpose(root, 12), transpose(root, 12 + third),
                 root, transpose(root, 7), transpose(root, 12), transpose(root, 7)]
        for k, n in enumerate(tones):
            if k == 0 or (drums and k == 4):
                instr = "KICK BASS"
            elif drums and k in (2, 6):
                instr = "SNARE BASS"
            else:
                instr = "BASS"
            notes.append((b * 16 + k * 2, n, I[instr]))
    return pattern("BASS " + " ".join(chords) + ("" if drums else " SOFT"), notes)

def music_box(chords):
    """The chords as a bell arpeggio up high: 1 5 3' 5 | 1' 5 3' 5 per bar."""
    notes = []
    for b, ch in enumerate(chords):
        root, third = CHORDS[ch]
        r = transpose(root, 24 if root[2] == "2" else 12)          # octave 4
        seq = [r, transpose(r, 7), transpose(r, 12 + third), transpose(r, 7),
               transpose(r, 12), transpose(r, 7), transpose(r, 12 + third), transpose(r, 19)]
        notes += [(b * 16 + k * 2, n, I["BELL"]) for k, n in enumerate(seq)]
    return pattern("BOX " + " ".join(chords), notes)

def tune(name, seq, instr):
    out = []
    for tok in seq.split():
        pos, note = tok.split(":")
        out.append((int(pos), note, I[instr]))
    return pattern(name, out)

VERSE_CHORDS = [("C", "Am"), ("F", "G"), ("Em", "Am"), ("Dm", "G")]
CHORUS_CHORDS = [("F", "G"), ("Em", "Am"), ("Dm", "G"), ("C", "C")]
HEX_CHORDS = [("Am", "F"), ("C", "G"), ("Am", "F"), ("E", "E")]

PATTERNS = [pattern("REST", [])]
def add(p):
    PATTERNS.append(p)
    return len(PATTERNS) - 1

BASS = {c: add(bass(c)) for c in VERSE_CHORDS + CHORUS_CHORDS + HEX_CHORDS if c != ("C", "C")}
BASS[("C", "C")] = add(bass(("C", "C")))
SOFT = {c: add(bass(c, drums=False)) for c in VERSE_CHORDS}
BOX = {c: add(music_box(c)) for c in VERSE_CHORDS}

# Sunny's verse, C major: a question (bars 1-4), then its answer (5-8)
VERSE = [add(tune(n, s, "FLUTE")) for n, s in (
    ("VERSE 1", "0:E-5 6:D-5 8:C-5 12:E-5 14:G-5 16:A-5 24:G-5 26:E-5 28:C-5"),
    ("VERSE 2", "0:F-5 4:A-5 8:C-6 14:A-5 16:G-5 22:F-5 24:E-5 28:D-5"),
    ("VERSE 3", "0:E-5 6:G-5 8:B-5 14:A-5 16:A-5 22:C-6 24:E-6 30:D-6"),
    ("VERSE 4", "0:D-6 4:C-6 8:A-5 12:F-5 16:G-5 24:A-5 26:B-5 28:D-6"),
)]
# chorus: it climbs to the top F, then comes home to C
CHORUS = [add(tune(n, s, "SWEET LEAD")) for n, s in (
    ("CHORUS 1", "0:C-6 6:A-5 8:C-6 12:D-6 16:D-6 22:B-5 24:G-5 28:B-5"),
    ("CHORUS 2", "0:B-5 6:G-5 8:E-5 12:G-5 16:A-5 22:C-6 24:E-6"),
    ("CHORUS 3", "0:F-6 6:E-6 8:D-6 12:A-5 16:B-5 22:A-5 24:G-5 28:F-5"),
    ("CHORUS 4", "0:E-5 8:G-5 12:C-6 16:C-6"),
)]
# Hex's verse, A minor: lower and darker, the E major chord's G# leading home
HEX = [add(tune(n, s, "FLUTE")) for n, s in (
    ("HEX 1", "0:A-5 6:B-5 8:C-6 14:B-5 16:A-5 22:G-5 24:F-5 28:A-5"),
    ("HEX 2", "0:G-5 6:E-5 8:C-5 12:E-5 16:D-5 22:G-5 24:B-5"),
    ("HEX 3", "0:C-6 6:B-5 8:A-5 12:E-5 16:F-5 20:A-5 24:C-6 28:A-5"),
    ("HEX 4", "0:G#5 8:B-5 12:E-6 16:D-6 22:B-5 24:G#5 28:E-5"),
)]

def row(v1, v2):
    return {"v1": float(v1), "v2": float(v2), "v3": 0.0, "dg": -1.0, "force_len": 32.0, "repeat_short": False}

INTRO = [row(SOFT[c], BOX[c]) for c in VERSE_CHORDS[:2]]
SECTION_VERSE = [row(BASS[c], p) for c, p in zip(VERSE_CHORDS, VERSE)]
SECTION_CHORUS = [row(BASS[c], p) for c, p in zip(CHORUS_CHORDS, CHORUS)]
SECTION_HEX = [row(BASS[c], p) for c, p in zip(HEX_CHORDS, HEX)]
INTERLUDE = [row(SOFT[c], BOX[c]) for c in VERSE_CHORDS]
ORDER = (INTRO + SECTION_VERSE + SECTION_CHORUS + SECTION_HEX + INTERLUDE
         + SECTION_VERSE + SECTION_CHORUS)
LOOP_ROW = len(INTRO)                          # the intro plays once
SONGS = [{"loop_row": float(LOOP_ROW), "name": "POLARITY THEME", "loop": True, "order": ORDER}]

SFX = [
    # name, text, note, attack, decay, sustain, release, priority
    ("COIN",    "$11,N+12,D2,N+19,D2,N+24,D4,---", "C-5", 0, 6, 0, 2, 2),
    ("USE",     "$41,D1,N+7,D2,---",               "C-5", 0, 3, 0, 1, 1),
    ("MAGIC",   "$21,D1,N+12,D1,N+7,D1,N+19,D2,---", "C-5", 0, 4, 2, 2, 1),
    ("SWAP",    "$11,D2,N+4,D2,N+7,D2,N+12,D2,N+16,D4,---", "C-5", 0, 6, 4, 3, 3),
    ("OUCH",    "$81,D2,$41,N-5,D3,N-10,D4,---",    "C-4", 0, 6, 2, 2, 3),
    ("PROMOTE", "$21,D4,N+4,D4,N+7,D4,N+12,D10,---", "C-5", 0, 6, 8, 3, 3),
    ("ERROR",   "$41,D6,N-1,D6,---",                "C-3", 0, 8, 6, 2, 2),
    ("SLEEP",   "$11,D8,N-3,D8,N-7,D12,---",        "C-4", 2, 8, 6, 6, 2),
    ("JUMP",    "$41,D1,N+5,D1,N+10,D1,N+15,D2,---", "C-4", 0, 4, 0, 1, 1),
    ("CLUE",    "$11,D2,N+7,D2,N+12,D2,N+19,D2,N+24,D2,N+31,D8,---", "C-5", 0, 8, 6, 4, 3),
]
SFX_ID = {s[0]: i for i, s in enumerate(SFX)}


def music_meta(gate_music_meta):
    m = copy.deepcopy(gate_music_meta)
    m["instruments"] = copy.deepcopy(INSTRUMENTS)
    m["patterns"] = copy.deepcopy(PATTERNS)
    m["songs"] = copy.deepcopy(SONGS)
    m["play_speed"] = 6.0
    m["voice_mask"] = 3.0
    m["song_loop"] = True
    m["song_loop_row"] = float(LOOP_ROW)
    m["filt_mode"] = 1.0          # low-pass, for the bass voice
    m["filt_res"] = 15.0
    m["filt_cut"] = 1280.0
    for k in ("sel_song", "sel_order_row", "sel_voice", "sel_step", "bank_sel_pattern", "list_scroll", "sel_instr"):
        m[k] = 0.0
    m["song_order"] = []
    return m


def sfx_meta(gate_sfx_meta):
    m = copy.deepcopy(gate_sfx_meta)
    m["instruments"] = [{
        "release": float(r), "pulse_width": 2048.0, "sfx_note": note, "sfx_priority": float(pri),
        "name": name, "text": text, "attack": float(a), "decay": float(d), "sustain": float(s),
    } for name, text, note, a, d, s, r, pri in SFX]
    m["sel_instr"] = 0.0
    return m
