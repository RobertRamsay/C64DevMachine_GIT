"""POLARITY music (MUSIC_MAKER) and sound effects (SFX_MAKER) metas.

An original tune: no melodies or chord sequences are taken from anywhere.
It is arranged with production techniques of three C64 greats, studied at
register level (style only) from HVSC tunes by Reyn Ouwehand, Jeroen Tel
and Charles Deenen:
  - Ouwehand: a slow build over a filtered pedal bass (the cutoff jumps on
    each note and sweeps down), delayed-arp chord stabs (root first, then
    the chord tones), chords changing every half bar in the major section,
    octave-pluck lead attacks.
  - Tel: a long minor i-bVII-bVI-bVII progression, two bars per chord,
    carried by fast 1-frame arpeggio chords re-triggered every other row
    over a busy 16th-note click bass with the kick and snare folded in;
    then a vibrato lead over the same changes.
  - Deenen: a Phrygian i-bVII-i-bII breakdown with a minor-third trill
    lead and an octave-pluck answer.
6 frames per row, 16 rows per bar, 2-bar patterns. Voice 1 carries bass and
drums, voice 2 lead / arps; voice 3 stays free for the game's sound effects.
Form: intro (build), Sunny (C major) x2, Hex (A minor), breakdown, Sunny
again, then back to Sunny (about 100 s per loop).
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
    # bass voice: pulse with a 1-frame noise click; cutoff jumps on the note, sweeps down
    ins("CLICK BASS", ["$41", "C$600", "D1", "$81", "N=95", "D1", "$41", "N", "D1"], 8, (96, 24), (-14, 40),
        a=0, d=8, s=8, r=9, pw=1280, filt=1),
    ins("KICK BASS", ["$11", "N=60", "D1", "N=44", "D1", "N=36", "D1", "$41", "N", "D1"], 9, (96, 24),
        a=0, d=9, s=8, r=9, pw=1280, filt=1),
    ins("SNARE BASS", ["$81", "N=72", "D1", "$41", "N=48", "D1", "$81", "N=70", "D1", "$41", "N", "D1"], 11, (96, 24),
        a=0, d=9, s=8, r=9, pw=1280, filt=1),
    ins("HAT", ["$81", "N=95", "D1", "$80"], end=True, a=0, d=2, s=0, r=0),
    # lead voice
    ins("LEAD", ["$21", "D1", "$41", "D14", "V$24", "D1"], 5, (16, 48), a=0, d=0, s=11, r=8, pw=1600),
    ins("ARP MAJOR", ["$41", "N", "D1", "N+7", "D1", "N+4", "D1"], 1, (32, 32), a=0, d=8, s=6, r=3, pw=1024),
    ins("ARP MINOR", ["$41", "N", "D1", "N+7", "D1", "N+3", "D1"], 1, (32, 32), a=0, d=8, s=6, r=3, pw=1024),
    ins("ECHO LEAD", ["$21", "D1", "$41", "D14", "V$24", "D1"], 5, (16, 48), a=0, d=0, s=6, r=6, pw=1600),
    ins("PAD", ["$41", "D60", "V$23", "D1"], 3, (120, 28), a=10, d=10, s=12, r=8),
    ins("SNARE LEAD", ["$81", "N=72", "D1", "$41", "N=50", "D1", "$80", "D3"], end=True, a=0, d=8, s=0, r=4),
    ins("DELAY ARP MIN", ["$41", "N", "D3", "N+3", "D2", "N+7", "D1", "N+12", "D2"], 1, (24, 40), a=0, d=9, s=5, r=4, pw=1200),
    ins("DELAY ARP MAJ", ["$41", "N", "D3", "N+4", "D2", "N+9", "D1", "N+12", "D2"], 1, (24, 40), a=0, d=9, s=5, r=4, pw=1200),
    ins("OCT PLUCK", ["$21", "N+12", "D2", "$41", "N", "D10", "V$24", "D1"], 7, (12, 56), a=0, d=0, s=10, r=7, pw=1800),
    ins("TRILL", ["$41", "N", "D2", "N+3", "D4", "N", "D4"], 1, (16, 40), a=0, d=0, s=10, r=6, pw=1500),
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

def groove(name, roots, style="normal"):
    """Bass + drums in one voice. roots: 1, 2 or 4 per pattern.
    styles: pedal (eighth clicks, no drums), build (pedal + kick + hats),
    normal (kick, snare, hats, octave clicks), busy (16th clicks)."""
    span = 32 // len(roots)
    notes = []
    for i, r in enumerate(roots):
        b = i * span
        hi = transpose(r, 12)
        if style == "pedal":
            cell = [(o, r, "CLICK BASS") for o in range(0, 8, 2)]
        elif style == "build":
            cell = [(0, r, "KICK BASS"), (2, r, "CLICK BASS"), (3, "C-7", "HAT"),
                    (4, r, "CLICK BASS"), (6, r, "CLICK BASS"), (7, "C-7", "HAT")]
        elif style == "busy":
            cell = [(0, r, "KICK BASS"), (1, r, "CLICK BASS"), (2, hi, "CLICK BASS"), (3, r, "CLICK BASS"),
                    (4, r, "SNARE BASS"), (5, r, "CLICK BASS"), (6, hi, "CLICK BASS"), (7, r, "CLICK BASS")]
        else:
            cell = [(0, r, "KICK BASS"), (2, r, "CLICK BASS"), (3, "C-7", "HAT"),
                    (4, r, "SNARE BASS"), (6, hi, "CLICK BASS"), (7, "C-7", "HAT")]
        for off in range(0, span, 8):
            notes += [(b + off + o, n, I[k]) for o, n, k in cell]
    return pattern(name, notes)

def stabs(name, root, quality, rows):
    return pattern(name, [(o, root, I["DELAY ARP " + quality]) for o in rows])

def fast_arps(name, root, quality):
    """A 1-frame arp chord re-triggered every other row."""
    return pattern(name, [(o, root, I["ARP " + quality]) for o in range(0, 32, 2)])

def lead(name, seq, instr="LEAD"):
    out = []
    for tok in seq.split():
        pos, note = tok.split(":")
        out.append((int(pos), note, I[instr]))
    return pattern(name, out)

PATTERNS = [
    pattern("REST", []),                                                              # 0
    # intro: a slow build over an A pedal
    groove("PEDAL A", ["A-2"], "pedal"),                                              # 1
    groove("PEDAL A + KICK", ["A-2"], "build"),                                       # 2
    stabs("STABS Am", "A-3", "MIN", [0, 16]),                                         # 3
    stabs("STABS Am 2", "A-3", "MIN", [0, 6, 16, 22, 28]),                            # 4
    # Sunny's theme, C major, chords every half bar
    groove("GROOVE C F G C", ["C-3", "F-2", "G-2", "C-3"]),                           # 5
    groove("GROOVE Am F G G", ["A-2", "F-2", "G-2", "G-2"]),                          # 6
    groove("GROOVE F G Em Am", ["F-2", "G-2", "E-2", "A-2"]),                         # 7
    groove("GROOVE F G C C", ["F-2", "G-2", "C-3", "C-3"]),                           # 8
    lead("SUNNY 1", "0:G-5 2:E-5 4:C-5 6:E-5 8:A-5 10:F-5 12:C-6 14:A-5 16:B-5 18:D-6 20:G-5 22:B-5 24:C-6 28:E-5", "OCT PLUCK"),   # 9
    lead("SUNNY 2", "0:C-6 2:A-5 4:E-5 6:A-5 8:F-5 10:A-5 12:C-6 14:D-6 16:B-5 18:G-5 20:D-5 22:G-5 24:B-5 26:D-6 28:B-5 30:A-5", "OCT PLUCK"),  # 10
    lead("SUNNY 3", "0:A-5 4:C-6 6:A-5 8:B-5 12:D-6 14:B-5 16:G-5 18:B-5 20:E-6 24:C-6 26:A-5 28:E-5", "OCT PLUCK"),             # 11
    lead("SUNNY 4", "0:F-5 2:A-5 4:C-6 6:A-5 8:G-5 10:B-5 12:D-6 14:B-5 16:C-6 20:G-5 24:E-5 26:G-5 28:C-6", "OCT PLUCK"),       # 12
    # Hex's theme, A minor: i - bVII - bVI - bVII, two bars each
    groove("BUSY Am", ["A-2"], "busy"),                                               # 13
    groove("BUSY G", ["G-2"], "busy"),                                                # 14
    groove("BUSY F", ["F-2"], "busy"),                                                # 15
    fast_arps("FAST ARPS Am", "A-4", "MINOR"),                                        # 16
    fast_arps("FAST ARPS G", "G-4", "MAJOR"),                                         # 17
    fast_arps("FAST ARPS F", "F-4", "MAJOR"),                                         # 18
    lead("HEX 1", "0:A-5 6:C-6 8:B-5 10:A-5 12:E-5 16:A-5 18:B-5 20:C-6 22:D-6 24:E-6 28:D-6"),                                  # 19
    lead("HEX 2", "0:D-6 4:B-5 6:G-5 8:D-5 12:G-5 14:A-5 16:B-5 20:D-6 22:B-5 24:G-5 28:D-5"),                                   # 20
    lead("HEX 3", "0:C-6 4:A-5 6:F-5 8:C-5 12:F-5 14:G-5 16:A-5 20:C-6 24:E-6 26:D-6 28:C-6"),                                   # 21
    lead("HEX 4", "0:B-5 2:C-6 4:D-6 8:G-5 12:B-5 16:D-6 20:C-6 22:B-5 24:A-5 28:E-5"),                                          # 22
    # breakdown: Phrygian i - bVII - i - bII
    groove("GROOVE Am G", ["A-2", "G-2"]),                                            # 23
    groove("GROOVE Am Bb", ["A-2", "A#2"]),                                           # 24
    lead("TRILL 1", "0:E-5 4:D-5 8:D-5 12:B-4 16:E-5 20:C-5 24:F-5 28:D-5", "TRILL"),                                            # 25
    lead("TRILL 2", "0:A-4 8:G-4 16:A-4 24:A#4", "TRILL"),                                                                       # 26
    lead("PLUCK ANSWER 1", "0:A-5 2:A-5 4:G-5 6:A-5 8:B-5 10:A-5 12:G-5 14:D-5 16:E-5 18:E-5 20:F-5 22:E-5 24:D-5 26:A#4 28:A-4", "OCT PLUCK"),  # 27
    lead("PLUCK ANSWER 2", "0:E-5 4:A-5 8:G-5 12:D-5 16:F-5 20:A#5 24:A-5 28:A#5", "OCT PLUCK"),                                  # 28
]

def row(v1, v2):
    return {"v1": float(v1), "v2": float(v2), "v3": 0.0, "dg": -1.0, "force_len": 32.0, "repeat_short": False}

SUNNY = [row(5, 9), row(6, 10), row(7, 11), row(8, 12)]
ORDER = (
    [row(1, 3), row(2, 4)]                                    # intro: pedal build
    + SUNNY + SUNNY                                           # Sunny's theme x2 (loop point: row 2)
    + [row(13, 16), row(14, 17), row(15, 18), row(14, 17)]    # Hex: fast arps over the changes
    + [row(13, 19), row(14, 20), row(15, 21), row(14, 22)]    # Hex: the lead takes over
    + [row(23, 25), row(24, 26), row(23, 27), row(24, 28)]    # breakdown
    + SUNNY                                                   # home again
)
SONGS = [{"loop_row": 2.0, "name": "POLARITY THEME", "loop": True, "order": ORDER}]

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
    m["song_loop_row"] = 2.0
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
