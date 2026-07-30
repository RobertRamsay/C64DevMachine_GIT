/// @desc scr_build_d64(prg_buf, base_pc)
/// @param {Id.Buffer} prg_buf  - the full PRG output buffer
/// @param {real}      base_pc  - base load address ($0801)
///
/// Builds a valid 1541 .d64 image (174848 bytes, 35 tracks, 683 sectors).
/// Returns the path written.
///
/// 1541 directory sector layout (track 18, sectors 1+):
///   $00      next dir track  (0 = last sector)
///   $01      next dir sector ($FF = last sector)
///   $02-$FF  8 x 32-byte directory entries
///
/// Each 32-byte entry:
///   +$00     file type ($82 = PRG closed; $00 = empty slot)
///   +$01     first data track
///   +$02     first data sector
///   +$03-$12 filename, 16 bytes padded with $A0
///   +$13-$1D unused ($00)
///   +$1E-$1F block count, little-endian

function scr_build_d64(_prg_buf, _base_pc, _boot_actual_size, _out_path = "") {

    var _override_path = _out_path;

    // ================================================================
    // GEOMETRY
    // ================================================================
    var _spt = [
        0,
        21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21, // 1-17
        19,                                                   // 18
        19,19,19,19,19,19,                                   // 19-24
        18,18,18,18,18,18,                                   // 25-30
        17,17,17,17,17                                       // 31-35
    ];

    var _toff = array_create(37, 0);
    var _running = 0;
    for (var _t = 1; _t <= 35; _t++) {
        _toff[_t] = _running;
        _running += _spt[_t];
    }
    var _total_sec = _running; // 683

    // Flat image buffer
    var _img = buffer_create(_total_sec * 256, buffer_fixed, 1);
    buffer_fill(_img, 0, buffer_u8, 0, _total_sec * 256);

    // Used-sector map — reserve all of track 18 upfront
    var _used = array_create(_total_sec, false);
    for (var _s = 0; _s < _spt[18]; _s++) {
        _used[_toff[18] + _s] = true;
    }

    // Allocator pointer (linear, skip track 18)
    var _at = 1;
    var _as = 0;

    // ================================================================
    // COLLECT FILES
    // ================================================================
    var _files    = [];
    var _tmp_bufs = [];

    // BOOT — Use exact compiled size from the assembler
    var _boot_end = max(_boot_actual_size, 15);
    show_debug_message("D64 BUILD: BOOT bytes=" + string(_boot_end));
    array_push(_files, { name: "BOOT", buf: _prg_buf, size: _boot_end, ftype: 0x82 });

    // LOAD_ORG linked assets
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type != "LOAD_ORG") continue;
            if (!variable_struct_exists(_a, "linked_assets")) continue;

            var _links = _a.linked_assets;
            for (var _li = 0; _li < array_length(_links); _li++) {
                var _link = _links[_li];
                if (variable_struct_exists(_link, "load_later") && _link.load_later) {
                    show_debug_message("D64 BUILD: SKIPPING " + string(_link.asset_name) + " — load_later=true");
                    continue;
                }
                show_debug_message("D64 BUILD: PROCESSING " + string(_link.asset_name) + " type check next");

                var _aname = _link.asset_name;
                var _d64n  = (variable_struct_exists(_link, "d64_filename") && _link.d64_filename != "")
                           ? string_upper(_link.d64_filename) : string_upper(_aname);
                if (string_length(_d64n) > 16) _d64n = string_copy(_d64n, 1, 16);

                for (var _bii = 0; _bii < ds_list_size(_am.asset_list); _bii++) {
                    var _b = ds_list_find_value(_am.asset_list, _bii);
                    if (_b.name != _aname) continue;
                    if (_b.type != "SFX_DATA" && (!buffer_exists(_b.buffer) || buffer_get_size(_b.buffer) < 2)) break;
                    if (_b.type == "SFX_DATA" && !variable_struct_exists(_b.meta, "instruments")) break;

                    var _raw_sz = buffer_get_size(_b.buffer);
                    var _lbuf   = noone;
                    var _lsz    = 0;

                    if (_b.type == "BITMAP") {
                        // Bank-aware bitmap layout — MUST match MACRO_BMP's
                        // _scr_addr / _src_col formulas exactly so a KERNAL LOAD
                        // lands screen + colour where the display routine reads:
                        //   bank 0/1: screen = bmp + $2000, colour = screen + $3E8
                        //   bank 2:   screen = bankbase + $3C00 ($BC00)
                        //   bank 3:   screen = bankbase + $0400
                        // The file loads contiguously from _addr, so the screen
                        // offset within the file equals (screen_addr - _addr) and
                        // the colour offset equals (colour_addr - _addr).
                        var _addr      = _b.address;
                        var _bmp_bank  = floor(_addr / 0x4000);
                        var _bank_base = _bmp_bank * 0x4000;

                        var _scr_addr = _addr + 0x2000;
                        if (_bmp_bank == 2) {
                            _scr_addr = _bank_base + 0x3C00;
                        }
                        if (_bmp_bank == 3) {
                            _scr_addr = _bank_base + 0x0400;
                        }
                        var _col_addr = _scr_addr + 0x03E8;

                        // File offsets relative to load address (_addr)
                        var _scr_foff = _scr_addr - _addr;
                        var _col_foff = _col_addr - _addr;

                        // Payload must span from $0000 up to end of colour block.
                        // Total file size = 2 (PRG header) + (col_foff + 1000).
                        var _payload_end = _col_foff + 1000;
                        _lsz = _payload_end + 2;
                        _lbuf = buffer_create(_lsz, buffer_fixed, 1);
                        buffer_fill(_lbuf, 0, buffer_u8, 0, _lsz);

                        // PRG header — overrides Koala's stored load addr
                        buffer_poke(_lbuf, 0, buffer_u8, _addr & 0xFF);
                        buffer_poke(_lbuf, 1, buffer_u8, (_addr >> 8) & 0xFF);

                        // Bitmap (8000) at file offset 2 -> _addr
                        buffer_copy(_b.buffer, 2,    8000, _lbuf, 2);
                        // Screen RAM (1000) -> _scr_addr
                        buffer_copy(_b.buffer, 8002, 1000, _lbuf, 2 + _scr_foff);
                        // Colour RAM (1000) -> _col_addr
                        buffer_copy(_b.buffer, 9002, 1000, _lbuf, 2 + _col_foff);
                        // (BG colour byte at source offset 10002 consumed at build
                        //  time by MACRO_BMP, not transmitted via LOAD)

                        show_debug_message("D64 BITMAP: addr=$" + string_upper(decimal_to_hex(_addr))
                            + " bank=" + string(_bmp_bank)
                            + " scr=$" + string_upper(decimal_to_hex(_scr_addr))
                            + " col=$" + string_upper(decimal_to_hex(_col_addr))
                            + " lsz=" + string(_lsz));

                    } else if (_b.type == "SFX_DATA" && variable_struct_exists(_b.meta, "instruments")) {
                        var _addr = _b.address;
                        var _instrs = _b.meta.instruments;
                        var _blob_all = [];
                        for (var _ii = 0; _ii < array_length(_instrs); _ii++) {
                            var _blob = scr_sfx_data_instrument_blob(_instrs[_ii]);
                            for (var _bi = 0; _bi < array_length(_blob); _bi++) {
                                array_push(_blob_all, _blob[_bi]);
                            }
                        }
                        var _sfx_payload = max(array_length(_blob_all), 1);
                        _lsz  = _sfx_payload + 2;
                        _lbuf = buffer_create(_lsz, buffer_fixed, 1);
                        buffer_fill(_lbuf, 0, buffer_u8, 0, _lsz);
                        buffer_poke(_lbuf, 0, buffer_u8, _addr & 0xFF);
                        buffer_poke(_lbuf, 1, buffer_u8, (_addr >> 8) & 0xFF);
                        for (var _bi = 0; _bi < array_length(_blob_all); _bi++) {
                            buffer_poke(_lbuf, 2 + _bi, buffer_u8, _blob_all[_bi]);
                        }
                    } else {
                        var _addr = _b.address;
                        _lsz  = _raw_sz + 2;
                        _lbuf = buffer_create(_lsz, buffer_fixed, 1);
                        buffer_poke(_lbuf, 0, buffer_u8, _addr & 0xFF);
                        buffer_poke(_lbuf, 1, buffer_u8, (_addr >> 8) & 0xFF);
                        buffer_copy(_b.buffer, 0, _raw_sz, _lbuf, 2);
                    }

                    array_push(_tmp_bufs, _lbuf);
                    array_push(_files, { name: _d64n, buf: _lbuf, size: _lsz, ftype: 0x82 });
                    break;
                }
            }
        }
    }

    // ================================================================
    // WRITE FILES INTO SECTORS
    // ================================================================
    var _dir_entries = [];

    for (var _fi = 0; _fi < array_length(_files); _fi++) {
        var _f    = _files[_fi];
        var _fbuf = _f.buf;
        var _fsz  = _f.size;
        if (_fsz <= 0) continue;

        var _fpos     = 0;
        var _first_t  = -1;
        var _first_s  = -1;
        var _prev_abs = -1;
        var _blocks   = 0;

        while (_fpos < _fsz) {
            // Find next free sector (skip track 18)
            if (_at == 18) { _at = 19; _as = 0; }
            var _found   = false;
            var _scan    = 0;
            while (_scan < _total_sec) {
                if (_at > 35) break;
                if (_at == 18) { _at = 19; _as = 0; }
                if (!_used[_toff[_at] + _as]) {
                    _found = true;
                    break;
                }
                _as++;
                if (_as >= _spt[_at]) { _as = 0; _at++; }
                _scan++;
            }
            if (!_found) {
                show_debug_message("D64 BUILD: disk full writing " + _f.name);
                break;
            }

            var _cur_t   = _at;
            var _cur_s   = _as;
            var _cur_abs = _toff[_cur_t] + _cur_s;
            _used[_cur_abs] = true;

            // Advance allocator pointer for next call
            _as++;
            if (_as >= _spt[_at]) { _as = 0; _at++; }

            var _off = _cur_abs * 256;

            if (_first_t == -1) { _first_t = _cur_t; _first_s = _cur_s; }

            // Patch previous sector's chain link to point here
            if (_prev_abs >= 0) {
                buffer_poke(_img, _prev_abs * 256 + 0, buffer_u8, _cur_t);
                buffer_poke(_img, _prev_abs * 256 + 1, buffer_u8, _cur_s);
            }

            // Write up to 254 data bytes into sector bytes 2-255
            var _chunk = min(254, _fsz - _fpos);
            for (var _wb = 0; _wb < _chunk; _wb++) {
                buffer_poke(_img, _off + 2 + _wb, buffer_u8,
                    buffer_peek(_fbuf, _fpos + _wb, buffer_u8));
            }
            _fpos    += _chunk;
            _blocks++;
            _prev_abs = _cur_abs;

            // Last sector: track=0, sector=bytes_used+1
            if (_fpos >= _fsz) {
                buffer_poke(_img, _off + 0, buffer_u8, 0);
                buffer_poke(_img, _off + 1, buffer_u8, _chunk + 1);
            }
        }

        if (_first_t != -1) {
            array_push(_dir_entries, {
                name         : _f.name,
                ftype        : _f.ftype,
                first_track  : _first_t,
                first_sector : _first_s,
                block_count  : _blocks
            });
            show_debug_message("D64 BUILD: " + _f.name
                + " -> T" + string(_first_t) + "/S" + string(_first_s)
                + "  blocks=" + string(_blocks));
        }
    }

    // ================================================================
    // BAM — track 18, sector 0
    // ================================================================
    var _bam_off = _toff[18] * 256;

    buffer_poke(_img, _bam_off + 0, buffer_u8, 18);
    buffer_poke(_img, _bam_off + 1, buffer_u8, 1);
    buffer_poke(_img, _bam_off + 2, buffer_u8, 0x41);
    buffer_poke(_img, _bam_off + 3, buffer_u8, 0x00);

    for (var _t = 1; _t <= 35; _t++) {
        var _boff = _bam_off + 4 + (_t - 1) * 4;
        var _maxs = _spt[_t];
        var _free = 0;
        var _bm0  = 0; var _bm1 = 0; var _bm2 = 0;
        for (var _s = 0; _s < _maxs; _s++) {
            if (!_used[_toff[_t] + _s]) {
                _free++;
                if      (_s < 8)  _bm0 |= (1 << _s);
                else if (_s < 16) _bm1 |= (1 << (_s - 8));
                else              _bm2 |= (1 << (_s - 16));
            }
        }
        buffer_poke(_img, _boff + 0, buffer_u8, _free);
        buffer_poke(_img, _boff + 1, buffer_u8, _bm0);
        buffer_poke(_img, _boff + 2, buffer_u8, _bm1);
        buffer_poke(_img, _boff + 3, buffer_u8, _bm2);
    }

    var _disk_name = "C64 DEV MACHINE";
    for (var _c = 0; _c < 16; _c++) {
        var _ch = (_c < string_length(_disk_name))
                ? ord(string_char_at(_disk_name, _c + 1)) : 0xA0;
        buffer_poke(_img, _bam_off + 0x90 + _c, buffer_u8, _ch);
    }
    buffer_poke(_img, _bam_off + 0xA0, buffer_u8, 0xA0);
    buffer_poke(_img, _bam_off + 0xA1, buffer_u8, 0xA0);
    buffer_poke(_img, _bam_off + 0xA2, buffer_u8, ord("6"));
    buffer_poke(_img, _bam_off + 0xA3, buffer_u8, ord("4"));
    buffer_poke(_img, _bam_off + 0xA4, buffer_u8, 0xA0);
    buffer_poke(_img, _bam_off + 0xA5, buffer_u8, ord("2"));
    buffer_poke(_img, _bam_off + 0xA6, buffer_u8, ord("A"));

    // ================================================================
    // DIRECTORY — track 18, sectors 1+ (8 entries per sector)
    //
    // Sector bytes $00-$01 = chain link
    // Entries at $02, $22, $42, $62, $82, $A2, $C2, $E2 (every 32 bytes)
    //
    // Entry layout (32 bytes, NO leading padding):
    //   +$00     file type ($82=PRG, $00=empty)
    //   +$01     first track
    //   +$02     first sector
    //   +$03-$12 filename (16 bytes, $A0-padded)
    //   +$13-$1D unused
    //   +$1E-$1F block count (lo/hi)
    // ================================================================
    var _total_entries  = array_length(_dir_entries);
    var _dir_sec_needed = max(1, ceil(_total_entries / 8));

    for (var _dsi = 0; _dsi < min(_dir_sec_needed, 18); _dsi++) {
        var _sec     = _dsi + 1; // track 18 sectors 1-18
        var _sec_off = (_toff[18] + _sec) * 256;
        var _is_last = (_dsi == _dir_sec_needed - 1);

        // Sector chain link
        if (_is_last) {
            buffer_poke(_img, _sec_off + 0, buffer_u8, 0x00);
            buffer_poke(_img, _sec_off + 1, buffer_u8, 0xFF);
        } else {
            buffer_poke(_img, _sec_off + 0, buffer_u8, 18);
            buffer_poke(_img, _sec_off + 1, buffer_u8, _sec + 1);
        }

        // 8 entries per sector, each 32 bytes. Entries start at sector offsets
        // $00, $20, $40, $60, $80, $A0, $C0, $E0. The first two bytes of entry 0
        // serve double-duty as the sector's chain link (track/sector of next dir
        // sector). For all other entries those two bytes are unused ($00/$00).
        //
        // Within each 32-byte entry slot:
        //   +$00-$01  unused / chain link (entry 0 only)
        //   +$02      file type ($82 = PRG closed, $00 = empty slot)
        //   +$03      first data track
        //   +$04      first data sector
        //   +$05-$14  filename (16 bytes, $A0 padded)
        //   +$15-$1D  unused / REL bookkeeping
        //   +$1E-$1F  block count (lo, hi)
        for (var _ei = 0; _ei < 8; _ei++) {
            var _gei  = _dsi * 8 + _ei;
            var _eoff = _sec_off + (_ei * 32);

            // Zero the slot, but preserve the sector chain link in entry 0
            // (we wrote that earlier and don't want to clobber it)
            var _zero_start = (_ei == 0) ? 2 : 0;
            for (var _eb = _zero_start; _eb < 32; _eb++) {
                buffer_poke(_img, _eoff + _eb, buffer_u8, 0x00);
            }

            if (_gei >= _total_entries) continue; // empty slot

            var _e = _dir_entries[_gei];

            buffer_poke(_img, _eoff + 0x02, buffer_u8, _e.ftype);        // file type
            buffer_poke(_img, _eoff + 0x03, buffer_u8, _e.first_track);  // first track
            buffer_poke(_img, _eoff + 0x04, buffer_u8, _e.first_sector); // first sector

            // Filename: 16 bytes at +$05, padded with $A0
            for (var _c = 0; _c < 16; _c++) {
                var _ch = (_c < string_length(_e.name))
                        ? ord(string_char_at(_e.name, _c + 1)) : 0xA0;
                buffer_poke(_img, _eoff + 0x05 + _c, buffer_u8, _ch);
            }

            // Block count at +$1E-$1F (within the 32-byte slot)
            buffer_poke(_img, _eoff + 0x1E, buffer_u8, _e.block_count & 0xFF);
            buffer_poke(_img, _eoff + 0x1F, buffer_u8, (_e.block_count >> 8) & 0xFF);
        }
    }

    // ================================================================
    // SAVE & CLEANUP
    // ================================================================
    var _d64_path = obj_workspace_manager.export_dir + "program.d64";
    if (_override_path != "") {
        _d64_path = _override_path;
    }
    buffer_save(_img, _d64_path);
    buffer_delete(_img);

    for (var _ti = 0; _ti < array_length(_tmp_bufs); _ti++) {
        if (buffer_exists(_tmp_bufs[_ti])) buffer_delete(_tmp_bufs[_ti]);
    }

    show_debug_message("D64 BUILD: saved " + _d64_path
        + " — " + string(_total_entries) + " file(s)");
    return _d64_path;
}
