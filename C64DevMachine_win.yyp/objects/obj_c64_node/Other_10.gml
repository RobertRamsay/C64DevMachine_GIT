/// @desc Address Defaults
// Check if we are a data node immediately on creation
if (string_pos("DATA", node_type) > 0) {
    pc_address = 0x1200;
} else if (node_type == "SPR64") {
    pc_address = 0x7000;
	
} else if (node_type == "BITMAP_KLA") {
    macro_link_mode  = false;
    kla_buffer       = -1;       // no file loaded yet
    preview_surf     = -1;       // preview surface, rebuilt on load
    kla_filename     = "";       // display name only

} else if (node_type == "MACRO_FLIP_X") {
    pc_address = global.start_pc;
} else if (node_type == "ORG") {
    pc_address = global.start_pc;
    if (org_uid == -1) {
        org_uid = global.next_org_uid;
        global.next_org_uid += 1;
    }
} else {
    pc_address = 0256; // $0100
}

is_data_node = (string_pos("DATA", node_type) > 0 ||
                node_type == "RAW_DATA" || node_type == "SPR64" || node_type == "BITMAP_KLA");
is_free_node = is_data_node;

// Prime MACRO_CODE cache immediately after node_type is confirmed
if (node_type == "MACRO_CODE" && array_length(instructions) > 0 && array_length(instructions[0]) > 1) {
    var _ct = string(instructions[0][1]);
    if (_ct != "") {
        var _stats = scr_parse_asm_byte_count(_ct);
        code_cached_bytes  = _stats[0];
        code_cached_cycles = _stats[1];
        code_cached_lines  = array_length(string_split(_ct, "\n"));
        var _parsed = scr_parse_asm_text(_ct);
        code_seg_cache = [];
        var _data_pc = -1, _data_sz = 0;
        for (var _pi = 0; _pi < array_length(_parsed); _pi++) {
            var _pt = string_lower(_parsed[_pi][0]);
            if (_pt == "pc") {
                if (_data_pc >= 0 && _data_sz > 0)
                    array_push(code_seg_cache, { addr: _data_pc, size: _data_sz, no_conflict: false });
                _data_pc = _parsed[_pi][1];
                _data_sz = 0;
            } else if (_pt == "byte") {
                _data_sz += array_length(_parsed[_pi]) - 1;
            }
        }
        if (_data_pc >= 0 && _data_sz > 0)
            array_push(code_seg_cache, { addr: _data_pc, size: _data_sz, no_conflict: false });
        code_cache_dirty = false;
    }
}
