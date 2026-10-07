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
