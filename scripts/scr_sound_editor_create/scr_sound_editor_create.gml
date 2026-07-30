/// @function scr_sound_editor_create(_asset)
/// @desc Seeds the meta for a fresh SOUND_EDITOR asset. Every field the
///       editor touches is initialised here, so the editor never has to test
///       variable_struct_exists at runtime.
///
/// A SOUND_EDITOR is an AUTHORING asset, same family as BITMAP_BUILDER — no
/// C64 payload of its own. It holds a shared instrument pool plus one or more
/// SONGS, each song being three voice lanes of (note, instrument) steps.
///
///   instruments[] — shared across every song in this asset. Each:
///                     { name, text (mini-language source), compiled (cached
///                       scr_instrument_parse() result), ins_name (owned
///                       SE_INS_<n> BYTE_DATA asset), dirty }
///                   Exportable/importable between SOUND_EDITOR assets via
///                   clipboard — EXPORT copies .text, IMPORT pastes it as a
///                   new instrument. No cross-asset reference is stored; once
///                   imported it's a fully independent copy, same as a bitmap
///                   builder's records belong to exactly one builder.
///
///   patterns[]    — shared pool, ONE LANE each. Also asset-level, so any
///                   song can plug any pattern into any of its three voices.
///
///   songs[]       — each song owns ONLY its order table and loop settings;
///                   the instrument and pattern pools above are shared.
///                   Each song:
///                     { name,
///                       order: [ {v1,v2,v3,repeat_short,force_len}, ... ],
///                       loop,        // wrap at the end?
///                       loop_row }   // which order row to wrap back to
///                   MACRO_SID_SONG emits every song's order table into one
///                   concatenated block; <key>_init / <key>_seek take a song
///                   index in A and resolve the right slice at runtime.
///
///   A step struct: { instr_idx, note, empty }
///     instr_idx — index into instruments[], -1 = none (rest continues)
///     note      — note-name string ("C-4"), or "" for a rest/hold row
///     empty     — true = this row does nothing (holds whatever's ringing),
///                 distinct from a rest, which the note-name parser already
///                 understands as "---"
function scr_sound_editor_create(_asset) {
    _asset.meta = {
        // ── SHARED INSTRUMENT POOL ──
        instruments   : [],
        sel_instr     : -1,
        instr_list_scroll         : 0,
        instr_edit_active         : false,
        instr_edit_buf            : "",
        instr_edit_cursor         : 0,
        instr_name_edit_active    : false,
        instr_name_edit_buf       : "",
        instr_name_edit_cursor    : 0,

        // ── PATTERNS ──
        // A pattern is now ONE LANE of notes — not tied to any voice. The
        // song order table's v1/v2/v3 cells each pick a pattern INDEX to play
        // in that column, so the same pattern object can be plugged into
        // multiple voices at once (a row of 1,1,1 shows and edits the exact
        // same data in all three grid columns, since they're the same object).
        patterns      : [
            { name: "PATTERN 00", steps: [], pattern_len: 64 },
            { name: "PATTERN 01", steps: [], pattern_len: 64 },
            { name: "PATTERN 02", steps: [], pattern_len: 64 }
        ],
        bank_sel_pattern : 0,   // which pattern the BANK row (add/del) points at

        // ── SONGS ── each song owns its own order table, loop flag and loop
        // row. instruments[] and patterns[] stay ASSET-level shared pools, so
        // a title tune and an in-game tune can reuse the same bass pattern.
        //
        // There is deliberately NO song_order alias field: json_stringify would
        // write it as a second independent copy, and json_parse would rebuild
        // it detached from songs[], so edits would silently stop reaching the
        // real data. songs[sel_song].order is the only reference.
        songs         : [
            {
                name     : "SONG 00",
                order    : [ { v1: 0, v2: 1, v3: 2, repeat_short: false, force_len: 0 } ],
                loop     : true,
                loop_row : 0
            }
        ],
        sel_song      : 0,
        song_name_edit_active : false,
        song_name_edit_buf    : "",
        song_name_edit_cursor : 0,

        sel_order_row : 0,
        order_scroll  : 0,

        // ── EDITOR CURSOR ──
        sel_voice     : 0,
        sel_step      : 0,
        cur_octave    : 4,   // piano-key entry: Z-row=oct-1, Q-row=oct, I/O/P=oct+1

        // ── PLAYBACK ──
        playing       : false,
        play_row      : 0,
        play_tick     : 0,      // frames elapsed in the current row
        song_playing    : false,   // Ctrl+Space full-song playback
        song_order_row  : 0,
        song_master_row : 0,
        song_tick       : 0,
        // Frames per row. The runtime reloads _S_TICK with this on every row
        // advance, so it's the whole of the tempo. 6 at 50Hz PAL is roughly
        // 125bpm at 4 rows/beat. Editable via the TEMPO stepper in the header.
        play_speed    : 6,

        // ── VIEW ──
        view_mode     : "VERTICAL",   // vertical first; horizontal is a later
                                      // draw mode over the same data, per your
                                      // earlier decision
        step_zoom     : 1,
        list_scroll   : 0,

        // ── UNDO / REDO ──
        // Same shape as the builder's — snapshot the mutable state before each
        // edit, session-only, pruned on save/load.
        undo_stack    : [],
        redo_stack    : [],

        // ── KEY-REPEAT TIMERS ──
        nav_up_timer  : 0,
        nav_down_timer: 0,
        bksp_timer    : 0,
        ins_timer     : 0,

        // ── WARNING LINE ──
        warn_msg      : "",
        warn_timer    : 0
    };
}