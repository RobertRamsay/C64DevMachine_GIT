/// @desc scr_node_build_inject(p_buf, base_pc)
/// @param {Id.Buffer} p_buf     - the PRG output buffer
/// @param {real}      base_pc   - base load address ($0801)
/// Writes all asset and data node byte payloads into the PRG buffer.
/// Called once per build after the assembler pass.

function scr_node_build_inject(_p_buf, _base_pc) {

    with (obj_c64_node) {

        switch (node_type) {

            // -------------------------------------------------------
            // SPR64 — binary buffer injection (legacy node)
            // -------------------------------------------------------
            case "SPR64": {
                var _dest = (pc_address - _base_pc) + 2;
                if (_dest >= 2 && _dest < 65536 && buffer_exists(sprite_buffer)) {
                    buffer_copy(sprite_buffer, 0, 4096, _p_buf, _dest);
                }
            } break;

            // -------------------------------------------------------
            // MACRO_PRINT — inline text to user-specified data address
            // -------------------------------------------------------
            case "MACRO_PRINT": {
                if (!is_connected) break;
                var _str       = (array_length(instructions[0]) > 5) ? string(instructions[0][5]) : "";
                var _data_addr = (array_length(instructions[0]) > 6) ? real(instructions[0][6]) : 0x2000;
                if (_str == "") break;
                var _offset = (_data_addr - _base_pc) + 2;
                if (_offset >= 15 && _offset < 65535) {
                    buffer_seek(_p_buf, buffer_seek_start, _offset);
                    for (var _s = 1; _s <= string_length(_str); _s++) {
                        var _cc = string_ord_at(_str, _s);
                        if (_cc >= 65 && _cc <= 90)       _cc -= 64;  // A-Z → PETSCII
                        else if (_cc >= 97 && _cc <= 122) _cc -= 96;  // a-z → PETSCII
                        buffer_write(_p_buf, buffer_u8, _cc);
                    }
                }
            } break;

            // -------------------------------------------------------
            // RAW_DATA — comma separated hex bytes
            // -------------------------------------------------------
            case "RAW_DATA": {
                if (!is_connected) break;
                var _raw_str   = (array_length(instructions) > 0) ? string(instructions[0][1]) : "";
                var _raw_bytes = string_split(_raw_str, ",");
                var _offset    = (pc_address - _base_pc) + 2;
                for (var _rb = 0; _rb < array_length(_raw_bytes); _rb++) {
                    var _byte_hex = string_upper(string_trim(_raw_bytes[_rb]));
                    if (string_char_at(_byte_hex, 1) == "$") _byte_hex = string_delete(_byte_hex, 1, 1);
                    var _byte_val = hex_to_decimal(_byte_hex);
                    var _buf_pos  = _offset + _rb;
                    if (_buf_pos >= 2 && _buf_pos < 65535) {
                        buffer_seek(_p_buf, buffer_seek_start, _buf_pos);
                        buffer_write(_p_buf, buffer_u8, _byte_val);
                    }
                }
            } break;

            // -------------------------------------------------------
            // MACRO_SPR — sprite bank injection from named asset
            // -------------------------------------------------------
            case "MACRO_SPR": {
                if (!is_connected) break;
                if (!instance_exists(obj_asset_manager)) break;
                var _asset_name = string(instructions[0][1]);
                if (_asset_name == "") break;
                var _am = obj_asset_manager;
                for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                    var _asset = ds_list_find_value(_am.asset_list, _ai);
                    if (_asset.type == "SPRITE_SET" && _asset.name == _asset_name) {
                        if (buffer_exists(_asset.buffer)) {
                            var _dest = (_asset.address - _base_pc) + 2;
                            var _sz   = buffer_get_size(_asset.buffer);
                            if (_dest >= 2 && _dest < 65536)
                                buffer_copy(_asset.buffer, 0, _sz, _p_buf, _dest);
                        }
                        break;
                    }
                }
            } break;

            // -------------------------------------------------------
            // MACRO_MAP — removed legacy viewport inject
            // Map data is now fully handled by Pass 3 in scr_compile_chain
            // which injects the MAP_DATA buffer at _a.address correctly.
            // This case intentionally left empty.
            // -------------------------------------------------------

        }
    }
}