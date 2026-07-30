function scr_asset_sid_import(_asset) {
    var _is_sfx = (_asset.type == "SID_SFX");
    var _filter  = _is_sfx ? "SFX File|*.snd;*.ins;*.bin" : "SID Music|*.sid";
    var _file    = get_open_filename(_filter, "");
    io_clear();
    if (_file == "") { io_clear(); exit; }

    // .ins → convert to .snd via ins2snd2.exe
    var _ext_lower = string_lower(filename_ext(_file));
    if (_ext_lower == ".ins") {
        var _snd_file = string_copy(_file, 1, string_length(_file) - string_length(filename_ext(_file))) + ".snd";
        var _exe      = working_directory + "Ins2snd2/ins2snd2.exe";
        execute_shell_simple(_exe, "\"" + _file + "\" \"" + _snd_file + "\"");
        var _timeout = 180;
        while (!file_exists(_snd_file) && _timeout > 0) { _timeout--; }
        if (!file_exists(_snd_file)) {
            scr_show_message("ins2snd2 conversion failed — .snd not found.");
            io_clear();
            exit;
        }
        _file = _snd_file;
    }

    _asset.file = _file;
	
	// new add 16APR:
	// ---------------------------------------------------
	// AUTO-NAME FROM IMPORTED FILE
	// ---------------------------------------------------
	if (_asset.file != "") {
	    var _old_name = _asset.name;
	    var _filename_only = filename_name(_asset.file);
	    var _extension = filename_ext(_asset.file);
	    var _clean_name = string_replace(_filename_only, _extension, "");

	    // Only overwrite if it currently has a generic name (e.g., "BITMAP_2")
	    if (string_pos(_asset.type, _old_name) == 1) { 
	        _asset.name = _clean_name;
        
	        // Sweep nodes to update any that might be holding the generic name
	        with (obj_c64_node) {
	            if (array_length(instructions) > 0 && array_length(instructions[0]) > 1) {
	                if (is_string(instructions[0][1]) && instructions[0][1] == _old_name) {
	                    instructions[0][1] = _clean_name;
	                }
	            }
	        }
	    }
	}
	// ---------------------------------------------------

	
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    _asset.buffer = buffer_load(_file);
    if (!buffer_exists(_asset.buffer)) {
        _asset.file   = "";
        _asset.buffer = -1;
        exit;
    }

    var _buf    = _asset.buffer;
    var _buf_sz = buffer_get_size(_asset.buffer);
    var _ext    = string_lower(filename_ext(_asset.file));

    if (_ext == ".snd" || _ext == ".bin") {
        // Raw GT SFX BIN — no SID header, inject verbatim
        // Set default address if not manually set
        if (_asset.address == 0 || _asset.address == scr_asset_default_address("SID_SFX"))
            _asset.address = 0x3000;

        // Store fixed entry points relative to load address
        // +0 = init (call once at startup)
        // +3 = play (call every frame)
        // +6 = trigger SFX (A=data lo, Y=data hi, X=channel)
        _asset.meta.sid_init_addr  = _asset.address + 0; // jsr once at startup
        _asset.meta.sid_play_addr  = _asset.address + 3; // jsr every frame
        _asset.meta.sfx_trig_addr  = _asset.address + 6; // jmp to trigger
        _asset.meta.sid_data_start = 0;

        // Parse instrument data offsets
        // BIN structure: [playroutine] [freq table ending with $FF $00] [instr 0] $FF $00 [instr 1] $FF $00 ...
        var _sfx_offsets = [];
        // Detect 2-byte PRG load address header and skip it
        var _prg_skip = 0;
        if (_buf_sz > 2 &&
            buffer_peek(_asset.buffer, 0, buffer_u8) == (_asset.address & 0xFF) &&
            buffer_peek(_asset.buffer, 1, buffer_u8) == ((_asset.address >> 8) & 0xFF)) {
            _prg_skip = 2;
        }
        var _scan = _prg_skip + $000C; // skip PRG header + JMP table

        // Find end of frequency table — terminated by $FF $00
        while (_scan < _buf_sz - 1) {
            if (buffer_peek(_asset.buffer, _scan,     buffer_u8) == $FF &&
                buffer_peek(_asset.buffer, _scan + 1, buffer_u8) == $00) {
                _scan += 2; // skip $FF $00
                break;
            }
            _scan++;
        }

        // Collect instrument blocks — each ends with $FF $00
        while (_scan < _buf_sz - 1) {
            array_push(_sfx_offsets, _scan - _prg_skip);
            while (_scan < _buf_sz - 1) {
                if (buffer_peek(_asset.buffer, _scan,     buffer_u8) == $FF &&
                    buffer_peek(_asset.buffer, _scan + 1, buffer_u8) == $00) {
                    _scan += 2;
                    break;
                }
                _scan++;
            }
            if (_scan >= _buf_sz - 1) break;
        }

        _asset.meta.sfx_offsets = _sfx_offsets;
        show_debug_message("SFX BIN loaded at $" + string_upper(decimal_to_hex(_asset.address)));
        show_debug_message("  init  = $" + string_upper(decimal_to_hex(_asset.meta.sid_init_addr)));
        show_debug_message("  play  = $" + string_upper(decimal_to_hex(_asset.meta.sid_play_addr)));
        show_debug_message("  trig  = $" + string_upper(decimal_to_hex(_asset.meta.sfx_trig_addr)));
        show_debug_message("  instruments found: " + string(array_length(_sfx_offsets)));
        for (var _oi = 0; _oi < array_length(_sfx_offsets); _oi++)
            show_debug_message("  [" + string(_oi) + "] file offset=$" + string_upper(decimal_to_hex(_sfx_offsets[_oi]))
                + "  mem addr=$" + string_upper(decimal_to_hex(_asset.address + _sfx_offsets[_oi])));

    } else {
        // Standard SID file — parse header
        var _header_size = (buffer_peek(_buf, 6, buffer_u8) << 8) | buffer_peek(_buf, 7, buffer_u8);
        if (_header_size != 0x76 && _header_size != 0x7C) _header_size = 0x76;
        var _raw_load   = (buffer_peek(_buf, 8, buffer_u8) << 8) | buffer_peek(_buf, 9, buffer_u8);
        var _data_start = (_raw_load == 0) ? _header_size + 2 : _header_size;
        var _load_addr  = (_raw_load != 0) ? _raw_load
                        : (buffer_peek(_buf, _header_size,     buffer_u8) |
                          (buffer_peek(_buf, _header_size + 1, buffer_u8) << 8));
        var _init_addr  = (buffer_peek(_buf, 0x0A, buffer_u8) << 8) | buffer_peek(_buf, 0x0B, buffer_u8);
        var _play_addr  = (buffer_peek(_buf, 0x0C, buffer_u8) << 8) | buffer_peek(_buf, 0x0D, buffer_u8);
        if (_init_addr == 0) _init_addr = _load_addr;
    if (_play_addr == 0) _play_addr = _load_addr + 3;

// --- JMP dereference: if play addr points to a JMP opcode, follow it one level ---
    // Only follows if: opcode is $4C, target is within SID data range, and play_addr == load_addr+3
    // (i.e. only dereference the canonical dispatch table pattern, not arbitrary play addresses)
    if (_play_addr == _load_addr + 3) {
        var _play_offset = _play_addr - _load_addr + ((_raw_load == 0) ? 2 : 0) + _header_size;
        var _sid_end     = _header_size + ((_raw_load == 0) ? 2 : 0) + (buffer_get_size(_buf) - _header_size);
        if (_play_offset >= 0 && _play_offset + 2 < buffer_get_size(_buf)) {
            var _play_opcode = buffer_peek(_buf, _play_offset, buffer_u8);
            if (_play_opcode == 0x4C) {
                var _jmp_lo       = buffer_peek(_buf, _play_offset + 1, buffer_u8);
                var _jmp_hi       = buffer_peek(_buf, _play_offset + 2, buffer_u8);
                var _resolved_play = _jmp_lo | (_jmp_hi << 8);
                // Only follow if target lands within the SID's own data (not Kernal/ROM/zero)
                if (_resolved_play >= _load_addr && _resolved_play < (_load_addr + buffer_get_size(_buf))) {
                    show_debug_message("SID IMPORT: play $" + string_upper(decimal_to_hex(_play_addr))
                        + " is JMP -> resolved to $" + string_upper(decimal_to_hex(_resolved_play)));
                    _play_addr = _resolved_play;
                }
            }
        }
    }

    _asset.address              = _load_addr;
    _asset.meta.sid_init_addr   = _init_addr;
    _asset.meta.sid_play_addr   = _play_addr;
    _asset.meta.sid_data_start  = _data_start;
    }

// Keep file pointing at source — no local copy needed
    _asset.file = _file;
    show_debug_message("SID IMPORT COMPLETE: buf=" + string(buffer_exists(_asset.buffer)) + " sz=" + string(buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : -1) + " addr=$" + string_upper(decimal_to_hex(_asset.address)));
	
	if (variable_struct_exists(_asset, "meta")) _asset.meta._mtime = md5_file(_asset.file);
	
}