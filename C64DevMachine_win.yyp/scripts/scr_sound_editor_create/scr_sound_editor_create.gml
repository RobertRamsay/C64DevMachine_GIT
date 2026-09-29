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
        // Song filter: mode bits (1 LP, 2 BP, 4 HP), resonance 0-15, cutoff 0-2047.
        filt_mode     : 0,
        filt_res      : 0,
        filt_cut      : 1024,

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
/// Additive multi-SID format: v1-v3 stay compatible; extra order lanes are v4-v24.
function scr_music_sid_count(_m) {
    return variable_struct_exists(_m, "sid_count") ? clamp(floor(real(_m.sid_count)), 1, 8) : 1;
}
/// Shared by manual save, Save As, autosave and load. Keep hidden lanes' masks.
function scr_music_sid_copy_meta(_source, _target) {
    _target.sid_count = scr_music_sid_count(_source);
    _target.sid_page = variable_struct_exists(_source, "sid_page") ? clamp(real(_source.sid_page), 0, _target.sid_count - 1) : 0;
    for (var _c = 1; _c < 8; _c++) _target[$ "sid_mask_" + string(_c)] = scr_music_sid_mask(_source, _c);
    if (variable_struct_exists(_source, "music_nodes")) _target.music_nodes = _source.music_nodes;
}
function scr_music_sid_mask(_m, _chip) {
    if (_chip == 0) return variable_struct_exists(_m, "voice_mask") ? (_m.voice_mask & 7) : 7;
    var _key = "sid_mask_" + string(_chip);
    return variable_struct_exists(_m, _key) ? (_m[$ _key] & 7) : 7;
}
function scr_music_sid_pattern(_row, _voice) {
    var _key = "v" + string(_voice + 1);
    return variable_struct_exists(_row, _key) ? _row[$ _key] : -1;
}
function scr_music_sid_length(_m, _row) {
    if (variable_struct_exists(_row, "force_len") && _row.force_len > 0) return clamp(_row.force_len, 1, 255);
    var _len = 0;
    for (var _v = 0; _v < scr_music_sid_count(_m) * 3; _v++) {
        if ((scr_music_sid_mask(_m, _v div 3) & (1 << (_v mod 3))) == 0) continue;
        var _p = scr_music_sid_pattern(_row, _v);
        if (_p >= 0 && _p < array_length(_m.patterns)) _len = max(_len, _m.patterns[_p].pattern_len);
    }
    return (_len > 0) ? clamp(_len, 1, 255) : 64;
}
/// Compiler view: shared instruments/patterns, projected lanes, common row lengths.
function scr_music_sid_project(_m, _chip) {
    var _out = { instruments: _m.instruments, patterns: _m.patterns, songs: [],
        play_speed: _m.play_speed, voice_mask: scr_music_sid_mask(_m, _chip),
        filt_mode: _m.filt_mode, filt_res: _m.filt_res, filt_cut: _m.filt_cut };
    for (var _s = 0; _s < array_length(_m.songs); _s++) {
        var _source = _m.songs[_s];
        var _song = { name: _source.name, loop: _source.loop, loop_row: _source.loop_row, order: [] };
        for (var _r = 0; _r < array_length(_source.order); _r++) {
            var _row = _source.order[_r];
            array_push(_song.order, { v1: scr_music_sid_pattern(_row, _chip * 3),
                v2: scr_music_sid_pattern(_row, _chip * 3 + 1), v3: scr_music_sid_pattern(_row, _chip * 3 + 2),
                repeat_short: _row.repeat_short, force_len: scr_music_sid_length(_m, _row) });
        }
        array_push(_out.songs, _song);
    }
    return _out;
}

/// Explicit paging never discards a partly edited note or changes the saved lanes.
function scr_music_sid_page(_m, _page, _col_pat, _undo, _snap) {
    scr_sound_editor_commit_cell(_m, _undo, _snap, _col_pat);
    _m.sid_page = clamp(_page, 0, scr_music_sid_count(_m) - 1);
    _m.cmd_entry_str = "";
    _m.sel_anchor_voice = _m.sel_voice;
    _m.sel_anchor_step = _m.sel_step;
}

function scr_music_sid_find_uid(_uid) {
    var _found = noone;
    var _matches = 0;
    with (obj_c64_node) if (stable_uid == _uid) { _found = id; _matches++; }
    // Never edit an arbitrary first match in a legacy workspace with duplicate IDs.
    return (_matches == 1) ? _found : noone;
}
/// A real instruction node, not source text hidden in a MACRO_CODE node.
function scr_music_sid_op(_op, _operand, _x, _y, _parent) {
    var _n = scr_node_spawn("NORMAL", _x, _y);
    _n.node_title = string_upper((_op == "jmp_abs") ? "JMP" : _op);
    _n.instructions = [[_op, _operand]];
    _n.is_connected = true;
    _n.org_parent = _parent;
    _n.x_indent = (_op == "jsr" && instance_exists(_parent)) ? 40 : 0;
    with (_n) event_user(0);
    _n.height_dirty = true;
    _n.stats_cache_dirty = true;
    scr_macro_sync_height(_n);
    _n.prev_height = _n.height;
    return _n;
}
/// Preflight ONLY tracked legacy music wrappers. Unknown/edited source is not
/// guessed at, and nothing is changed until every candidate has been checked.
function scr_music_sid_native_plan(_existing, _macro) {
    var _targets = ["sng" + string(_macro.stable_uid) + "_play"];
    var _edits = [];
    for (var _i = 0; _i < array_length(_existing.nodes); _i++) {
        var _node = scr_music_sid_find_uid(_existing.nodes[_i]);
        if (!instance_exists(_node)) return { ok: false, edits: [] };
        if (_node.node_type == "LABEL" && array_length(_node.instructions) > 0)
            array_push(_targets, string(_node.instructions[0][1]));
    }
    for (var _i = 0; _i < array_length(_existing.nodes); _i++) {
        var _node = scr_music_sid_find_uid(_existing.nodes[_i]);
        if (_node.node_type != "MACRO_CODE") continue;
        if (array_length(_node.instructions) != 1 || array_length(_node.instructions[0]) != 2
            || _node.instructions[0][0] != "code_block") return { ok: false, edits: [] };
        var _lines = string_split(string_replace_all(string(_node.instructions[0][1]), "\r", ""), "\n");
        var _ops = [];
        for (var _l = 0; _l < array_length(_lines); _l++) {
            var _line = string_trim(_lines[_l]);
            if (_line == "") continue;
            var _upper = string_upper(_line);
            if (_upper == "RTS") {
                array_push(_ops, ["rts", 0]);
            } else {
                var _prefix = string_copy(_upper, 1, 4);
                if (_prefix != "JSR " && _prefix != "JMP ") return { ok: false, edits: [] };
                var _operand = string_trim(string_delete(_line, 1, 4));
                var _known = false;
                for (var _t = 0; _t < array_length(_targets); _t++) {
                    if (_operand == _targets[_t]) { _known = true; break; }
                }
                if (!_known) return { ok: false, edits: [] };
                array_push(_ops, [(_prefix == "JSR ") ? "jsr" : "jmp_abs", _operand]);
            }
        }
        // These are the only shapes emitted by the original generator.
        var _count = array_length(_ops);
        if (_count < 1 || _count > 2) return { ok: false, edits: [] };
        if (_count == 2 && (_ops[0][0] != "jsr"
            || (_ops[1][0] != "rts" && _ops[1][0] != "jmp_abs")))
            return { ok: false, edits: [] };
        array_push(_edits, { node: _node, ops: _ops });
    }
    return { ok: true, edits: _edits };
}
/// Upgrade known wrappers in place: keep the original UID, split the second
/// instruction into its own node, and track it so Generate remains idempotent.
/// User-authored/untracked code blocks and existing routine order stay intact.
function scr_music_sid_apply_native(_existing, _plan) {
    for (var _i = 0; _i < array_length(_plan.edits); _i++) {
        var _edit = _plan.edits[_i];
        var _node = _edit.node;
        var _op = _edit.ops[0][0];
        _node.node_type = "NORMAL";
        _node.node_title = string_upper((_op == "jmp_abs") ? "JMP" : _op);
        _node.instructions = [_edit.ops[0]];
        _node.collapsed = false;
        _node.code_seg_cache = [];
        _node.code_cache_dirty = true;
        _node.height_dirty = true;
        _node.stats_cache_dirty = true;
        with (_node) event_user(0);
        scr_macro_sync_height(_node);
        _node.prev_height = _node.height;
        if (array_length(_edit.ops) > 1) {
            var _after_y = _node.y + 1;
            var _parent = _node.org_parent;
            // Make ordering unambiguous before the normal chain pack closes gaps.
            with (obj_c64_node) {
                if (id != _node && node_type != "ORG" && org_parent == _parent
                    && is_connected && y >= _after_y) y += 80;
            }
            var _new = scr_music_sid_op(_edit.ops[1][0], _edit.ops[1][1],
                _node.x, _after_y, _parent);
            _new.is_connected = _node.is_connected;
            _new.x_indent = _node.x_indent;
            array_push(_existing.nodes, _new.stable_uid);
        }
    }
}
function scr_music_sid_label(_name, _x, _y, _parent) {
    var _n = scr_node_spawn("LABEL", _x, _y);
    _n.instructions = [["label", _name]];
    _n.is_connected = true;
    _n.org_parent = _parent;
    return _n;
}
/// Reserve free RAM for the generated player rather than choosing a fixed ORG.
function scr_music_sid_free_ram(_size, _ignore_org) {
    scr_build_memory_bar_cache();
    for (var _addr = 0x1000; _addr + _size <= 0xD000; _addr += 0x100) {
        var _free = true;
        for (var _i = 0; _i < array_length(global.memory_bar_segments); _i++) {
            var _seg = global.memory_bar_segments[_i];
            if (instance_exists(_ignore_org) && instance_exists(_seg.node_id)
                && (_seg.node_id == _ignore_org || _seg.node_id.org_parent == _ignore_org)) continue;
            if (_seg.type == "CODE" && _seg.no_conflict) continue;
            // Leave room for inserted calls on existing code chains.
            if (_addr < _seg.addr + _seg.size + 32 && _addr + _size > _seg.addr) { _free = false; break; }
        }
        if (_free) return _addr;
    }
    return -1;
}
/// Generate concrete, editable nodes. Stable IDs survive workspace save/load.
function scr_music_sid_generate(_asset) {
    var _m = _asset.meta;
    var _existing = variable_struct_exists(_m, "music_nodes") ? _m.music_nodes : undefined;
    var _org = noone;
    var _macro = noone;
    if (is_struct(_existing)) {
        if (!variable_struct_exists(_existing, "org") || !variable_struct_exists(_existing, "macro")) {
            scr_show_message("MUSIC MAKER: INCOMPLETE GENERATED NODE REFERENCES.\nNO NODES WERE CHANGED.");
            return false;
        }
        _org = scr_music_sid_find_uid(_existing.org);
        _macro = scr_music_sid_find_uid(_existing.macro);
        if (!instance_exists(_org) || !instance_exists(_macro)
            || _org.node_type != "ORG" || _macro.node_type != "MACRO_SID_SONG"
            || !variable_struct_exists(_existing, "nodes") || !is_array(_existing.nodes)) {
            scr_show_message("MUSIC MAKER: GENERATED NODE REFERENCES ARE MISSING OR AMBIGUOUS.\nRESTORE THE ORIGINAL GENERATED NODES BEFORE UPDATING. NO NODES WERE CHANGED.");
            return false;
        }
        for (var _u = 0; _u < array_length(_existing.nodes); _u++) {
            for (var _seen = 0; _seen < _u; _seen++) {
                if (_existing.nodes[_seen] == _existing.nodes[_u]) {
                    scr_show_message("MUSIC MAKER: DUPLICATE GENERATED NODE REFERENCE.\nNO NODES WERE CHANGED.");
                    return false;
                }
            }
            if (!instance_exists(scr_music_sid_find_uid(_existing.nodes[_u]))) {
                scr_show_message("MUSIC MAKER: A GENERATED NODE IS MISSING OR HAS A DUPLICATE ID.\nRESTORE IT BEFORE GENERATING AGAIN; EXISTING CALLS WERE LEFT IN PLACE.");
                return false;
            }
        }
    }
    // Size the complete player with its note table, conservatively even if
    // another macro already emits that table. Restore the compiler's flag.
    var _was_nt = variable_global_exists("sidsong_notetab_emitted") ? global.sidsong_notetab_emitted : false;
    global.sidsong_notetab_emitted = false;
    var _dry = [];
    var _ok = scr_sid_song_build(_dry, { stable_uid: "sizecheck" }, _asset, _asset.name, 1, 3, 2, 0xD400, false);
    global.sidsong_notetab_emitted = _was_nt;
    if (!_ok) return false;
    var _bytes = 64;
    for (var _d = 0; _d < array_length(_dry); _d++) {
        var _mn = _dry[_d][0];
        if (_mn == "byte" || _mn == "byte_lab_lo" || _mn == "byte_lab_hi") _bytes += 1;
        else if (_mn != "label") _bytes += obj_opCodeManager.get_size(_mn);
    }
    var _addr = scr_music_sid_free_ram(_bytes, _org);
    if (_addr < 0) {
        scr_show_message("MUSIC MAKER: NO FREE CONTIGUOUS RAM FOR " + string(_bytes) + " BYTES.\nFREE SOME SPACE OR REDUCE THE CHIP COUNT. NO NODES WERE ADDED.");
        return false;
    }
    if (instance_exists(_org) && instance_exists(_macro)) {
        var _plan = scr_music_sid_native_plan(_existing, _macro);
        if (!_plan.ok) {
            scr_show_message("MUSIC MAKER: A GENERATED CODE BLOCK HAS BEEN CUSTOMISED.\nNO NODES WERE CHANGED. KEEP YOUR EDITS, OR RESTORE THE ORIGINAL WRAPPER BEFORE GENERATING AGAIN.");
            return false;
        }
        if (array_length(_plan.edits) > 0) {
            scr_undo_snapshot();
            scr_music_sid_apply_native(_existing, _plan);
        }
        _org.proxy_address = _addr;
        _org.pc_address = _addr;
        _macro.instructions[0][1] = _asset.name;
        global.addresses_dirty = true;
        global.undo_dirty = true;
        global.autosave_dirty = true;
        obj_workspace_manager.flow_overlay_dirty = true;
        _m.warn_msg = (array_length(_plan.edits) > 0)
            ? "MUSIC WRAPPERS UPDATED TO NATIVE NODES"
            : "UPDATED MUSIC NODES (EXISTING CALLS REUSED)";
        _m.warn_timer = game_get_speed(gamespeed_fps) * 4;
        return true;
    }
    var _init = noone;
    var _main = [];
    var _chains = [];
    var _all_labels = [];
    with (obj_c64_node) {
        if (node_type == "INIT") _init = id;
        if (is_connected && org_parent == noone && node_type != "ORG") array_push(_main, id);
        if (is_connected && node_type != "ORG") array_push(_chains, id);
        if (node_type == "LABEL") array_push(_all_labels, string(instructions[0][1]));
    }
    if (!instance_exists(_init)) return false;
    array_sort(_main, function(_a, _b) { return _a.y - _b.y; });
    array_sort(_chains, function(_a, _b) { return _a.y - _b.y; });
    // A reusable loop must have a visible backward JMP and a VWAIT inside it.
    var _loop_label = noone;
    var _wait = noone;
    for (var _i = 0; _i < array_length(_chains); _i++) {
        var _node = _chains[_i];
        var _target = "";
        for (var _j = 0; _j < array_length(_node.instructions); _j++) {
            var _ins = _node.instructions[_j];
            if (_ins[0] == "jmp_abs" || _ins[0] == "jmp") _target = string(_ins[1]);
        }
        // Also recognise a code block whose last source line is JMP label.
        if (_node.node_type == "MACRO_CODE") {
            var _lines = string_split(string_replace_all(_node.instructions[0][1], "\r", ""), "\n");
            for (var _l = array_length(_lines) - 1; _l >= 0; _l--) {
                var _line = string_trim(_lines[_l]);
                if (_line == "") continue;
                if (string_upper(string_copy(_line, 1, 4)) == "JMP ") _target = string_trim(string_delete(_line, 1, 4));
                break;
            }
        }
        if (_target == "") continue;
        for (var _l = 0; _l < _i; _l++) {
            if (_chains[_l].org_parent != _node.org_parent || _chains[_l].node_type != "LABEL" || string(_chains[_l].instructions[0][1]) != _target) continue;
            for (var _w = _l + 1; _w < _i; _w++) {
                if (_chains[_w].org_parent == _node.org_parent && _chains[_w].node_type == "MACRO_VWAIT") { _loop_label = _chains[_l]; _wait = _chains[_w]; break; }
            }
        }
        if (instance_exists(_wait)) break;
    }
    // Without a recognised loop, do not hide existing terminal jumps inside
    // another loop or silently bypass an existing program.
    if (!instance_exists(_wait)) {
        for (var _i = 0; _i < array_length(_main); _i++) {
            var _node = _main[_i];
            for (var _j = 0; _j < array_length(_node.instructions); _j++) {
                var _terminal = (_node.instructions[_j][0] == "jmp_abs" || _node.instructions[_j][0] == "jmp" || _node.instructions[_j][0] == "rts" || _node.instructions[_j][0] == "rti");
                if (_node.node_type == "MACRO_CODE") {
                    var _code_lines = string_split(string_upper(_node.instructions[0][1]), "\n");
                    for (var _ci = 0; _ci < array_length(_code_lines); _ci++) {
                        var _cl = string_trim(_code_lines[_ci]);
                        if (string_copy(_cl, 1, 4) == "JMP " || _cl == "RTS" || _cl == "RTI") _terminal = true;
                    }
                }
                if (_terminal) {
                    scr_show_message("MUSIC MAKER: EXISTING MAIN FLOW NEEDS A VISIBLE LABEL / VWAIT / JMP LOOP.\nNO NODES ADDED: THIS AVOIDS BYPASSING YOUR EXISTING CODE.");
                    return false;
                }
            }
        }
    }
    var _suffix = "";
    var _number = 1;
    var _clash = true;
    while (_clash) {
        _clash = false;
        for (var _l = 0; _l < array_length(_all_labels); _l++) {
            var _label = string_upper(_all_labels[_l]);
            if (_label == "MUSICMAKER_SETUP" + _suffix || _label == "MUSICMAKER_PLAY" + _suffix || _label == "CORE_LOOP" + _suffix) _clash = true;
        }
        if (_clash) { _number += 1; _suffix = "_" + string(_number); }
    }
    if (global.undo_dirty) { scr_c64_do_update_addresses(); scr_undo_snapshot(); global.undo_dirty = false; }
    var _made = [];
    var _x = _init.x + global.node_display_width + 120;
    with (obj_c64_node) if (node_type == "ORG") _x = max(_x, x + global.node_display_width + 120);
    var _core_x = _x;
    if (!instance_exists(_wait)) _x += global.node_display_width + 120;
    _org = scr_spawn_org_node(_x, _init.y);
    // Keep the existing free-RAM allocator; column order is visual, not a
    // reason to move the player onto occupied RAM via an automatic proxy.
    _org.proxy = false;
    _org.proxy_address = _addr;
    _org.pc_address = _addr;
    _org.node_title = "MUSIC MAKER";
    array_push(_made, _org.stable_uid);
    var _setup_name = "MUSICMAKER_SETUP" + _suffix;
    var _play_name = "MUSICMAKER_PLAY" + _suffix;
    // Allocate the song first to obtain its stable entry-point name. Its
    // visual position follows the PLAY wrapper, exactly like hand-built nodes.
    _macro = scr_node_spawn("MACRO_SID_SONG", _x, _init.y + 420);
    _macro.instructions = [["macro_sid_song", _asset.name, 1, 3, 2, 0]];
    with (_macro) event_user(0);
    _macro.org_parent = _org;
    _macro.is_connected = true;
    _macro.x_indent = 40;
    array_push(_made, _macro.stable_uid);
    var _n = scr_music_sid_label(_play_name, _x, _init.y + 100, _org);
    array_push(_made, _n.stable_uid);
    _n = scr_music_sid_op("jsr", "sng" + string(_macro.stable_uid) + "_play", _x, _init.y + 180, _org);
    array_push(_made, _n.stable_uid);
    _n = scr_music_sid_op("rts", 0, _x, _init.y + 260, _org);
    array_push(_made, _n.stable_uid);
    _n = scr_music_sid_label(_setup_name, _x, _init.y + 340, _org);
    array_push(_made, _n.stable_uid);
    _n = scr_music_sid_op("rts", 0, _x, _init.y + 680, _org);
    array_push(_made, _n.stable_uid);
    if (instance_exists(_wait)) {
        // Insert setup above the backward-jump target; it runs once only.
        // ORG loops are entered via a jump from the main spine. Setup belongs
        // on that spine, not inside the repeatedly entered ORG.
        var _setup_y = (_wait.org_parent == noone) ? _loop_label.y : _init.y + _init.height + 1;
        with (obj_c64_node) if (is_connected && org_parent == noone && node_type != "ORG" && y >= _setup_y) y += 120;
        _n = scr_music_sid_op("jsr", _setup_name, _init.x, _setup_y, noone);
        array_push(_made, _n.stable_uid);
        var _play_y = _wait.y;
        var _loop_parent = _wait.org_parent;
        with (obj_c64_node) if (is_connected && org_parent == _loop_parent && node_type != "ORG" && y >= _play_y) y += 120;
        _n = scr_music_sid_op("jsr", _play_name, _wait.x, _play_y, _loop_parent);
        array_push(_made, _n.stable_uid);
    } else {
        var _core = scr_spawn_org_node(_core_x, _init.y);
        _core.proxy = false;
        _core.proxy_address = _addr + _bytes - 32;
        _core.pc_address = _core.proxy_address;
        _core.node_title = "CORE LOOP";
        array_push(_made, _core.stable_uid);
        _n = scr_music_sid_label("CORE_LOOP" + _suffix, _core.x, _core.y + 100, _core);
        array_push(_made, _n.stable_uid);
        _n = scr_music_sid_op("jsr", _play_name, _core.x, _core.y + 180, _core);
        array_push(_made, _n.stable_uid);
        _n = scr_node_spawn("MACRO_VWAIT", _core.x, _core.y + 280);
        _n.org_parent = _core; _n.is_connected = true; _n.x_indent = 40;
        array_push(_made, _n.stable_uid);
        _n = scr_music_sid_op("jmp_abs", "CORE_LOOP" + _suffix, _core.x, _core.y + 400, _core);
        array_push(_made, _n.stable_uid);
        var _bottom = _init.y + _init.height;
        for (var _i = 0; _i < array_length(_main); _i++) _bottom = max(_bottom, _main[_i].y + _main[_i].height);
        _n = scr_music_sid_op("jsr", _setup_name, _init.x, _bottom + 20, noone);
        array_push(_made, _n.stable_uid);
        _n = scr_music_sid_op("jmp_abs", "CORE_LOOP" + _suffix, _init.x, _bottom + 100, noone);
        array_push(_made, _n.stable_uid);
    }
    _m.music_nodes = { org: _org.stable_uid, macro: _macro.stable_uid, nodes: _made };
    global.addresses_dirty = true;
    global.undo_dirty = true;
    global.autosave_dirty = true;
    obj_workspace_manager.flow_overlay_dirty = true;
    _m.warn_msg = instance_exists(_wait) ? "MUSIC NODES ADDED TO EXISTING VWAIT LOOP" : "MUSIC NODES AND CORE LOOP CREATED";
    _m.warn_timer = game_get_speed(gamespeed_fps) * 5;
    return true;
}
