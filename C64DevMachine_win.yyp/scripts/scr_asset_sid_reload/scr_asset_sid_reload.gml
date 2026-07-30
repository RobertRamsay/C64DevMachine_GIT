/// scr_asset_sid_reload(_asset)
function scr_asset_sid_reload(_asset) {
    show_debug_message("SID RELOAD CALLED");
    if (!variable_struct_exists(_asset, "file") || _asset.file == "") exit;
    if (!file_exists(_asset.file)) {
        show_debug_message("SID RELOAD: File not found — " + _asset.file);
        exit;
    }
    global.asset_reload_in_progress = true;
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    var _buf = buffer_load(_asset.file);
    if (!buffer_exists(_buf)) {
        show_debug_message("SID RELOAD: Buffer load failed");
        global.asset_reload_in_progress = false;
        exit;
    }
    _asset.buffer = _buf;
    var _buf_sz   = buffer_get_size(_buf);
    // Re-parse SID header — mirrors scr_asset_sid_import SID branch
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

    _asset.address             = _load_addr;
    _asset.meta.sid_init_addr  = _init_addr;
    _asset.meta.sid_play_addr  = _play_addr;
    _asset.meta.sid_data_start = _data_start;
    show_debug_message("SID RELOAD: OK — " + filename_name(_asset.file)
        + "  init=$" + string_upper(decimal_to_hex(_init_addr))
        + "  play=$" + string_upper(decimal_to_hex(_play_addr)));
    global.asset_reload_in_progress = false;
}