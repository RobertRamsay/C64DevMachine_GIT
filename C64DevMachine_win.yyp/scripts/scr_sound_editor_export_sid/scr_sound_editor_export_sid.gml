/// EXPORT SID — writes a Music Maker asset as a standalone PSID file.
///
/// The player is the same one MACRO_SID_SONG builds (scr_sid_song_build),
/// assembled straight to the chosen load address, so no relocation step is
/// needed: pick the address and it is compiled there. Layout, GoatTracker-style:
///   load + 0   JMP init   (A = song number, 0-based — as PSID players call it)
///   load + 3   JMP play   (once per frame, 50 Hz PAL)
///   load + 6   JMP sfx    (with SFX support: A/Y = effect data, X = 0/7/14;
///                          without it this is just RTS, so an SFX macro
///                          pointed at the SID does nothing rather than crash)
/// The player needs 44 zero-page bytes from the chosen base; nothing else
/// outside its own block is touched except the SID registers.

/// Start the export: ask for address, zero page and SFX support.
function scr_sound_editor_export_sid(_asset) {
    if (scr_music_sid_count(_asset.meta) > 1) {
        scr_show_message("MULTI-SID: USE GENERATE NODES AND EXPORT THE PROGRAM.\nTHE STANDALONE SID EXPORT CURRENTLY SUPPORTS ONE CHIP.");
        return;
    }
    // Defaults: a MACRO_SID_SONG node playing this asset lends its ZP and hard
    // restart, so the exported SID behaves like the in-project one.
    var _zp = 0x03;
    var _hr = 2;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID_SONG" && array_length(instructions) > 0) {
            var _in = instructions[0];
            if (array_length(_in) > 1 && string(_in[1]) == _asset.name) {
                if (array_length(_in) > 3 && is_real(_in[3])) {
                    _zp = real(_in[3]) & 0xFF;
                }
                if (array_length(_in) > 4 && is_real(_in[4])) {
                    _hr = clamp(real(_in[4]), 0, 8);
                }
            }
        }
    }
    var _zp_hex = string_upper(decimal_to_hex(_zp));
    while (string_length(_zp_hex) < 2) { _zp_hex = "0" + _zp_hex; }
    scr_prompt_text("EXPORT SID\nLoad address, zero-page base (uses 44 bytes), SFX support Y/N\n"
                  + "e.g. 1000," + _zp_hex + ",Y",
                    "1000," + _zp_hex + ",Y",
                    scr_sound_editor_export_sid_go, { asset: _asset, hr: _hr });
}

/// Hex text ("$1000", "1000", "0x1000") → number, or -1.
function scr_sound_editor_export_hex(_t) {
    var _s = string_upper(string_trim(_t));
    _s = string_replace(_s, "$", "");
    _s = string_replace(_s, "0X", "");
    if (_s == "") {
        return -1;
    }
    var _v = 0;
    for (var _i = 1; _i <= string_length(_s); _i++) {
        var _d = string_pos(string_char_at(_s, _i), "0123456789ABCDEF");
        if (_d == 0) {
            return -1;
        }
        _v = (_v << 4) | (_d - 1);
    }
    return _v;
}

/// Prompt callback: validate, assemble, write the .sid.
function scr_sound_editor_export_sid_go(_input, _ctx) {
    if (!is_string(_input) || _input == "") {
        return;
    }
    var _asset = _ctx.asset;
    var _parts = string_split(_input, ",");
    var _addr = -1;
    var _zp = -1;
    var _sfx = true;
    if (array_length(_parts) > 0) {
        _addr = scr_sound_editor_export_hex(_parts[0]);
    }
    if (array_length(_parts) > 1) {
        _zp = scr_sound_editor_export_hex(_parts[1]);
    }
    if (array_length(_parts) > 2) {
        var _yn = string_upper(string_trim(_parts[2]));
        _sfx = (_yn == "Y" || _yn == "YES" || _yn == "1");
    }
    if (_addr < 0x0200 || _addr > 0xF000) {
        scr_show_message("EXPORT SID: the load address must be hex between $0200 and $F000.");
        return;
    }
    if (_zp < 0x02 || _zp + 43 > 0xFF) {
        scr_show_message("EXPORT SID: the zero-page base must be hex between $02 and $D4 (the player uses 44 bytes).");
        return;
    }

    // ── build the player at the chosen address ──
    var _list = [];
    var _fid = { stable_uid: "x" };                 // label prefix "sngx_"
    var _key = "sngx_";
    array_push(_list, ["jmp_abs", _key + "init", _fid]);
    array_push(_list, ["jmp_abs", _key + "play", _fid]);
    if (_sfx) {
        array_push(_list, ["jmp_abs", _key + "sfxt", _fid]);
    } else {
        array_push(_list, ["rts", 0, _fid]);
        array_push(_list, ["byte", 0, _fid]);
        array_push(_list, ["byte", 0, _fid]);
    }
    // This is its own program, so it needs its own copy of the note table.
    var _nt_was = false;
    if (variable_global_exists("sidsong_notetab_emitted")) {
        _nt_was = global.sidsong_notetab_emitted;
    }
    global.sidsong_notetab_emitted = false;
    // Always all three voices: the VOICES buttons are for listening while
    // editing, not part of the tune.
    var _vm_was = 7;
    if (variable_struct_exists(_asset.meta, "voice_mask")) {
        _vm_was = _asset.meta.voice_mask;
    }
    _asset.meta.voice_mask = 7;
    var _ok = scr_sid_song_build(_list, _fid, _asset, _asset.name, 0, _zp, _ctx.hr, 0xD400, _sfx);
    _asset.meta.voice_mask = _vm_was;
    global.sidsong_notetab_emitted = _nt_was;
    if (!_ok) {
        scr_show_message("EXPORT SID: '" + _asset.name + "' has no patterns, no song order or no songs to export.");
        return;
    }

    // ── assemble: pass 1 places labels, pass 2 emits, then fixups ──
    var _p = c64_new_program();
    _p.base_address = _addr;
    _p.header_size  = 0;
    for (var _i = 0; _i < array_length(_list); _i++) {
        var _mn = string_lower(_list[_i][0]);
        if (_mn == "label" || _mn == "org") {
            _p.assemble_instruction(_mn, _list[_i][1]);
        } else {
            var _sz = obj_opCodeManager.get_size(_mn);
            if (_mn == "byte") {
                _sz = 1;
            }
            if (_sz > 0) {
                _p.add(array_create(_sz, 0));
            }
        }
    }
    _p.bytes = [];
    _p.fixups = [];
    _p.pc_override = -1;
    _p.label_seen = {};
    for (var _i = 0; _i < array_length(_list); _i++) {
        _p.assemble_instruction(string_lower(_list[_i][0]), _list[_i][1]);
    }
    global.asm_branch_error = false;
    _p.assemble();
    var _missing = "";
    for (var _fi = 0; _fi < array_length(_p.fixups); _fi++) {
        if (!ds_map_exists(_p.labels, _p.fixups[_fi].label)) {
            _missing = string(_p.fixups[_fi].label);
        }
    }
    // The player's state sits at the very end of the block (from <key>st to
    // <key>rtskip) and init clears it, so the file can stop where it starts.
    var _vars_at = _p.labels[? _key + "st"];
    var _skip_at = _p.labels[? _key + "rtskip"];
    ds_map_destroy(_p.labels);
    if (_missing != "" || global.asm_branch_error || array_length(_p.errors) > 0) {
        scr_show_message("EXPORT SID: the player didn't assemble. Nothing was written.\n\n" + _p.error_text());
        return;
    }
    var _n = array_length(_p.bytes);
    if (_addr + _n > 0x10000) {
        scr_show_message("EXPORT SID: the tune is $" + string_upper(decimal_to_hex(_n))
                       + " bytes and doesn't fit above $" + string_upper(decimal_to_hex(_addr)) + ".");
        return;
    }

    var _file_n = _n;
    if (!is_undefined(_vars_at) && !is_undefined(_skip_at) && _skip_at == _addr + _n && _vars_at > _addr && _vars_at < _addr + _n) {
        _file_n = _vars_at - _addr;
    }

    // ── songs, for the header (same rule as the build: empty songs are skipped) ──
    var _m = _asset.meta;
    var _n_songs = 0;
    if (variable_struct_exists(_m, "songs") && is_array(_m.songs)) {
        for (var _si = 0; _si < array_length(_m.songs); _si++) {
            if (variable_struct_exists(_m.songs[_si], "order") && array_length(_m.songs[_si].order) > 0) {
                _n_songs += 1;
            }
        }
    }
    _n_songs = clamp(_n_songs, 1, 255);

    var _path = get_save_filename("SID Music|*.sid", _asset.name + ".sid");
    if (_path == "") {
        return;
    }

    // ── PSID v2 header (big-endian fields), then load address + code ──
    var _b = buffer_create(0x7C + 2 + _file_n, buffer_fixed, 1);
    buffer_fill(_b, 0, buffer_u8, 0, 0x7C);
    buffer_poke(_b, 0x00, buffer_u8, ord("P"));
    buffer_poke(_b, 0x01, buffer_u8, ord("S"));
    buffer_poke(_b, 0x02, buffer_u8, ord("I"));
    buffer_poke(_b, 0x03, buffer_u8, ord("D"));
    var _be = function(_buf, _off, _v) {
        buffer_poke(_buf, _off,     buffer_u8, (_v >> 8) & 0xFF);
        buffer_poke(_buf, _off + 1, buffer_u8, _v & 0xFF);
    };
    _be(_b, 0x04, 2);                 // version
    _be(_b, 0x06, 0x7C);              // data offset
    _be(_b, 0x08, 0);                 // load address: taken from the data's first two bytes
    _be(_b, 0x0A, _addr);             // init
    _be(_b, 0x0C, _addr + 3);         // play
    _be(_b, 0x0E, _n_songs);
    _be(_b, 0x10, 1);                 // start song
    // 0x12-0x15 speed: 0 = every song on the 50 Hz vertical blank
    var _strs = [string_upper(_asset.name), "C64 DEV MACHINE", string(current_year)];
    for (var _si2 = 0; _si2 < 3; _si2++) {
        var _t = _strs[_si2];
        for (var _ci = 1; _ci <= min(31, string_length(_t)); _ci++) {
            buffer_poke(_b, 0x16 + _si2 * 32 + _ci - 1, buffer_u8, ord(string_char_at(_t, _ci)) & 0x7F);
        }
    }
    // flags: PAL, and the song's chip (6581 / 8580)
    var _flags = 0x0004 | 0x0010;
    var _exp_chip = _asset.meta[$ "chip_model"];
    if (is_undefined(_exp_chip)) _exp_chip = global.sid64_model;
    if (_exp_chip == 1) {
        _flags = 0x0004 | 0x0020;
    }
    _be(_b, 0x76, _flags);
    // Where a SID player may put its own driver: never over the player's state
    // (it's in RAM past the end of the file). The bigger free run of whole
    // pages, after the player up to $9FFF or from $0400 up to the load address.
    var _ram_end = _addr + _n;
    var _rel_start = 0;
    var _rel_pages = 0;
    var _pg_after = (_ram_end + 255) >> 8;
    if (_pg_after < 0xA0) {
        _rel_start = _pg_after;
        _rel_pages = 0xA0 - _pg_after;
    }
    var _pg_below = _addr >> 8;
    if (_pg_below - 4 > _rel_pages) {
        _rel_start = 4;
        _rel_pages = _pg_below - 4;
    }
    if (_rel_pages <= 0) {
        _rel_start = 0xFF;      // no room: the player must not relocate
        _rel_pages = 0;
    }
    buffer_poke(_b, 0x78, buffer_u8, _rel_start);
    buffer_poke(_b, 0x79, buffer_u8, _rel_pages);
    buffer_poke(_b, 0x7C, buffer_u8, _addr & 0xFF);
    buffer_poke(_b, 0x7D, buffer_u8, (_addr >> 8) & 0xFF);
    for (var _bi = 0; _bi < _file_n; _bi++) {
        buffer_poke(_b, 0x7E + _bi, buffer_u8, _p.bytes[_bi]);
    }
    buffer_save(_b, _path);
    buffer_delete(_b);

    var _end = _addr + _n - 1;
    var _msg = "EXPORTED " + filename_name(_path)
             + "\n$" + string_upper(decimal_to_hex(_addr)) + "-$" + string_upper(decimal_to_hex(_end))
             + " (" + string(_n) + " bytes in RAM, " + string(_file_n) + " in the file), " + string(_n_songs) + " song(s)"
             + "\nINIT $" + string_upper(decimal_to_hex(_addr)) + " (A = song)   PLAY $" + string_upper(decimal_to_hex(_addr + 3))
             + "\nZERO PAGE $" + string_upper(decimal_to_hex(_zp)) + "-$" + string_upper(decimal_to_hex(_zp + 43));
    if (_sfx) {
        _msg += "\nSFX $" + string_upper(decimal_to_hex(_addr + 6)) + " (A/Y = effect, X = 0/7/14)";
    } else {
        _msg += "\nNO SFX SUPPORT";
    }
    scr_show_message(_msg);
}

// =====================================================================
// MUSIC MAKER FILE (.c64mm) — one MUSIC_MAKER / SFX_MAKER asset in its own
// file, so a song can move to another project. JSON:
//   { format:"C64DM_MUSIC_MAKER", version:1, type, name, meta, samples:[...] }
// meta is the same field set a project save writes, so import goes through
// the project loader's own rebuild (scr_music_maker_apply_meta). SAMPLE
// assets named by the digi track travel with it as {name, address, blob, meta}.
// =====================================================================

/// The saved meta field set — mirrors scr_save_workspace_as_path.
function scr_music_maker_meta_out(_a) {
    var _m = _a.meta;
    var _o = {};
    scr_music_sid_copy_meta(_m, _o);
    // GENERATE NODES links point at node uids in THIS project only
    if (variable_struct_exists(_o, "music_nodes")) variable_struct_remove(_o, "music_nodes");
    if (_a.type == "MUSIC_MAKER") {
        _o.digi_rate     = _m.digi_rate;
        _o.digi_samples  = _m.digi_samples;
        _o.digi_patterns = _m.digi_patterns;
        _o.digi_boost    = _m.digi_boost;
        _o.digi_speed    = _m.digi_speed;
        _o.instr_div     = _m.instr_div;
        _o.digi_on       = _m.digi_on;
    }
    var _keys = ["voice_mask", "sfx_chip", "instruments", "sel_instr", "patterns", "bank_sel_pattern",
                 "play_speed", "filt_mode", "filt_res", "filt_cut", "chip_model", "free_voices",
                 "note_table", "songs", "sel_song", "song_order", "sel_order_row", "song_loop",
                 "song_loop_row", "sel_voice", "sel_step", "cur_octave", "view_mode", "step_zoom",
                 "list_scroll"];
    for (var _i = 0; _i < array_length(_keys); _i++) {
        if (variable_struct_exists(_m, _keys[_i])) _o[$ _keys[_i]] = _m[$ _keys[_i]];
    }
    return _o;
}

/// A free asset name built from _base (max 15 chars, _2/_3... on a clash).
function scr_music_maker_unique_name(_base) {
    var _am = obj_asset_manager;
    var _name = scr_clamp_asset_name(_base, 15);
    var _k = 1;
    var _clash = true;
    while (_clash) {
        _clash = false;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            if (string_upper(ds_list_find_value(_am.asset_list, _i).name) == string_upper(_name)) { _clash = true; break; }
        }
        if (_clash) {
            _k++;
            _name = scr_clamp_asset_name(_base, 15 - (string_length(string(_k)) + 1)) + "_" + string(_k);
        }
    }
    return _name;
}

function scr_music_maker_export(_asset) {
    var _fn = get_save_filename("C64DM Music Maker|*.c64mm", _asset.name + ".c64mm");
    io_clear();
    if (_fn == "") return;
    if (string_lower(filename_ext(_fn)) != ".c64mm") _fn += ".c64mm";

    var _samples = [];
    if (_asset.type == "MUSIC_MAKER" && is_array(_asset.meta.digi_samples)) {
        for (var _i = 0; _i < array_length(_asset.meta.digi_samples); _i++) {
            var _sa = scr_digi_find_sample(string(_asset.meta.digi_samples[_i]));
            if (is_undefined(_sa)) continue;
            var _dupe = false;
            for (var _j = 0; _j < array_length(_samples); _j++) if (_samples[_j].name == _sa.name) _dupe = true;
            if (_dupe) continue;
            array_push(_samples, { name: _sa.name, address: _sa.address,
                blob: scr_blob_encode(_sa.buffer), meta: scr_sample_save_meta(_sa) });
        }
    }
    var _out = { format: "C64DM_MUSIC_MAKER", version: 1, type: _asset.type, name: _asset.name,
                 meta: scr_music_maker_meta_out(_asset), samples: _samples };
    var _txt = json_stringify(_out);
    var _buf = buffer_create(string_byte_length(_txt) + 1, buffer_fixed, 1);
    buffer_write(_buf, buffer_text, _txt);
    buffer_save_ext(_buf, _fn, 0, string_byte_length(_txt));
    buffer_delete(_buf);
    scr_show_message("EXPORT MUSIC MAKER\n\n'" + _asset.name + "' written to\n" + filename_name(_fn)
        + ((array_length(_samples) > 0) ? "\n(with " + string(array_length(_samples)) + " digi sample(s))" : ""));
}

/// IMPORT menu: a .c64mm file comes in as a new MUSIC_MAKER (or SFX_MAKER) asset.
function scr_import_music_maker() {
    if (!instance_exists(obj_asset_manager)) return;
    var _fn = get_open_filename("C64DM Music Maker|*.c64mm|All Files|*.*", "");
    io_clear();
    if (_fn == "") return;
    if (!file_exists(_fn)) {
        scr_show_message("IMPORT MUSIC MAKER\n\nFile not found:\n" + _fn);
        return;
    }
    var _fb = buffer_load(_fn);
    var _txt = buffer_read(_fb, buffer_text);
    buffer_delete(_fb);
    var _d = undefined;
    try { _d = json_parse(_txt); } catch (_e) { _d = undefined; }
    if (!is_struct(_d) || _d[$ "format"] != "C64DM_MUSIC_MAKER" || !is_struct(_d[$ "meta"])) {
        scr_show_message("IMPORT MUSIC MAKER\n\n" + filename_name(_fn) + " isn't a music maker file.");
        return;
    }
    var _am   = obj_asset_manager;
    var _type = (_d[$ "type"] == "SFX_MAKER") ? "SFX_MAKER" : "MUSIC_MAKER";
    var _sem  = _d.meta;

    // Digi samples first. One already here with identical data is reused;
    // otherwise the sample is added (renamed on a clash) and the song's slot
    // list is pointed at the new name.
    var _renames = {};
    var _added = 0;
    var _samples = is_array(_d[$ "samples"]) ? _d.samples : [];
    for (var _i = 0; _i < array_length(_samples); _i++) {
        var _sd = _samples[_i];
        if (!is_struct(_sd) || !is_string(_sd[$ "name"])) continue;
        var _have = scr_digi_find_sample(_sd.name);
        if (!is_undefined(_have) && scr_blob_encode(_have.buffer) == _sd[$ "blob"]) continue;
        var _sbuf = scr_blob_decode(_sd[$ "blob"]);
        if (_sbuf == noone) _sbuf = buffer_create(1, buffer_fixed, 1);
        var _sname = scr_music_maker_unique_name(_sd.name);
        var _sa = { name: _sname, type: "SAMPLE", address: real(_sd[$ "address"] ?? 0), file: "",
                    buffer: _sbuf, meta: {}, load_later: false, d64_filename: "", reu_filename: "",
                    reu_size: 0, reu_used: 0, linked_assets: [], group: "" };
        scr_sample_restore(_sa, is_struct(_sd[$ "meta"]) ? _sd.meta : {});
        ds_list_add(_am.asset_list, _sa);
        _renames[$ _sd.name] = _sname;
        _added++;
    }
    if (is_array(_sem[$ "digi_samples"])) {
        for (var _i = 0; _i < array_length(_sem.digi_samples); _i++) {
            var _sn = string(_sem.digi_samples[_i]);
            if (variable_struct_exists(_renames, _sn)) _sem.digi_samples[_i] = _renames[$ _sn];
        }
    }

    var _base = is_string(_d[$ "name"]) && _d.name != "" ? _d.name : filename_change_ext(filename_name(_fn), "");
    var _a = { name: scr_music_maker_unique_name(string_upper(_base)), type: _type,
               address: scr_asset_default_address(_type), file: "",
               buffer: buffer_create(1, buffer_fixed, 1), meta: {}, load_later: false,
               d64_filename: "", reu_filename: "", reu_size: 0, reu_used: 0,
               linked_assets: [], group: "" };
    scr_music_maker_apply_meta(_a, _sem);
    ds_list_add(_am.asset_list, _a);

    global.undo_dirty      = true;
    global.addresses_dirty = true;
    with (obj_workspace_manager) { alarm[3] = 6; }
    scr_show_message("IMPORT MUSIC MAKER\n\nAdded '" + _a.name + "'"
        + ((_added > 0) ? "\nplus " + string(_added) + " digi sample(s)" : ""));
}
