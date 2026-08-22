function scr_build_memory_bar_cache() {

var _addr_total = 65536;
    var _danger_zones = [
        [0x0000, 0x07FF, "FIXED"],
        [0xA000, 0xBFFF, "BASIC"],
        [0xD000, 0xFFFF, "KERNAL"]
    ];

    var _segments = [];

    // ORG aggregates — emitted independently of is_connected, since ORG nodes
    // are scaffolding (is_connected = false) but their address spans must
    // appear in the memory bar. no_conflict is true for code ORGs (their
    // children supply the real conflict signal — the aggregate is decorative)
    // and false for VARIABLES / HW REGISTERS where the aggregate IS the real
    // footprint and must conflict with anything overlapping it.
    with (obj_c64_node) {
        if (node_type != "ORG") continue;
        if (end_address <= pc_address) continue;
        var _org_size = end_address - pc_address;
        var _org_col;
        if      (node_title == "VARIABLES")    _org_col = make_color_rgb(60,  140, 200);
        else if (node_title == "HW REGISTERS") _org_col = make_color_rgb(70,  100, 105);
        else                                   _org_col = make_color_rgb(180,  30, 200);
        var _org_label = (node_title == "VARIABLES" || node_title == "HW REGISTERS")
                       ? node_title
                       : ((code_descriptor != "") ? code_descriptor : (node_title != "" ? node_title : "ORG"));
        var _org_addr_hex = string_upper(decimal_to_hex(pc_address));
        while (string_length(_org_addr_hex) < 4) _org_addr_hex = "0" + _org_addr_hex;
        var _org_seg_name = _org_label + " AT $" + _org_addr_hex;
        var _is_var_org = (node_title == "VARIABLES" || node_title == "HW REGISTERS");
        array_push(_segments, {
            addr:        pc_address,
            size:        _org_size,
            col:         _org_col,
            type:        (node_title == "VARIABLES" ? "VARIABLE_BLOCK" : "NODE"),
            name:        _org_seg_name,
            lines:       [],
            node_id:     id,
            no_conflict: !_is_var_org,
            conflict:    false
        });
    }

    // Connected node segments
    with (obj_c64_node) {
        if (!is_connected) continue;
        var _seg_size = 0;
        var _seg_col  = 0;

        switch (node_type) {
            case "ORG":
                // ORG aggregates are emitted by the top "ORG aggregates" loop
                // before this switch. ORGs are is_connected=false scaffolding
                // so they would also be skipped by the outer guard above —
                // nothing to do here.
                break;

            case "INIT":
                if (total_node_size > 0) {
                    var _init_ah = string_upper(decimal_to_hex(pc_address));
                    while (string_length(_init_ah) < 4) _init_ah = "0" + _init_ah;
                    var _init_label = (node_title != "") ? node_title : "INIT";
                    array_push(_segments, {
                        addr:        pc_address,
                        size:        total_node_size,
                        col:         make_color_rgb(40, 180, 40),
                        type:        "NODE",
                        name:        "INIT BLOCK: " + _init_label + " AT $" + _init_ah,
                        lines:       [],
                        node_id:     id,
                        no_conflict: false,
                        conflict:    false
                    });
                    _seg_size = 0;
                }
                break;

            case "NORMAL":
            case "BRANCH":
                if (total_node_size > 0) {
                    _seg_size = total_node_size;
                    _seg_col  = (node_type == "BRANCH") ? make_color_rgb(220, 140, 60) : make_color_rgb(80, 140, 220);
                }
                break;

            case "RAW_DATA":
                if (total_node_size > 0) {
                    _seg_size = total_node_size;
                    _seg_col  = make_color_rgb(40, 160, 200);
                }
                break;

            case "SPR64":
                if (sprite_buffer != noone) {
                    _seg_size = 4096;
                    _seg_col  = make_color_rgb(200, 120, 40);
                }
                break;

            case "DATA_TEXT": {
                var _dt_len = array_length(instructions);
                for (var _j = 0; _j < _dt_len; _j++)
                    _seg_size += string_length(string(instructions[_j][1]));
                _seg_col = make_color_rgb(80, 220, 80);
            } break;

            case "DATA_SID":
                if (sprite_buffer != noone) {
                    _seg_size = buffer_get_size(sprite_buffer);
                    var _in_danger = false;
                    for (var _dz = 0; _dz < array_length(_danger_zones); _dz++) {
                        if (pc_address >= _danger_zones[_dz][0] && pc_address <= _danger_zones[_dz][1]) { _in_danger = true; break; }
                    }
                    _seg_col = _in_danger ? make_color_rgb(255, 60, 0) : make_color_rgb(40, 120, 200);
                }
                break;

            case "BITMAP_KLA":
                if (buffer_exists(kla_buffer)) {
                    _seg_size = buffer_get_size(kla_buffer);
                    var _in_danger = false;
                    for (var _dz = 0; _dz < array_length(_danger_zones); _dz++) {
                        if (pc_address >= _danger_zones[_dz][0] && pc_address <= _danger_zones[_dz][1]) { _in_danger = true; break; }
                    }
                    _seg_col = _in_danger ? make_color_rgb(255, 60, 0) : make_color_rgb(40, 120, 200);
                }
                break;

            case "MACRO_CODE": {
                if (array_length(instructions) > 0 && array_length(instructions[0]) > 1) {
                    if (array_length(code_seg_cache) == 0 || code_cache_dirty) {
                        var _code_text = string(instructions[0][1]);
                        var _parsed    = scr_parse_asm_text(_code_text);
                        var _plen      = array_length(_parsed);
                        code_seg_cache = [];
                        var _data_pc    = -1;
                        var _data_sz    = 0;
                        var _data_lines = [];
                        var _cur_line   = -1;
                        for (var _pi = 0; _pi < _plen; _pi++) {
                            var _pt = string_lower(_parsed[_pi][0]);
                            if (_pt == "_line_map_") {
                                _cur_line = _parsed[_pi][1];
                            } else if (_pt == "pc") {
                                if (_data_pc >= 0 && _data_sz > 0)
                                    array_push(code_seg_cache, { addr: _data_pc, size: _data_sz, lines: _data_lines, no_conflict: false });
                                _data_pc    = _parsed[_pi][1];
                                _data_sz    = 0;
                                _data_lines = [];
                            } else if (_pt == "const") {
                                if (array_length(_parsed[_pi]) > 2 && is_real(_parsed[_pi][2])) {
                                    array_push(code_seg_cache, { addr: _parsed[_pi][2], size: 2, lines: [_cur_line], no_conflict: false });
                                }
                            } else if (_pt == "byte" || _pt == "string") {
                                _data_sz += array_length(_parsed[_pi]) - 1;
                                if (_cur_line > 0) {
                                    var _has_line = false;
                                    for (var _li = 0; _li < array_length(_data_lines); _li++) {
                                        if (_data_lines[_li] == _cur_line) { _has_line = true; break; }
                                    }
                                    if (!_has_line) array_push(_data_lines, _cur_line);
                                }
                            } else if (_pt != "label") {
                                if (instance_exists(obj_opCodeManager)) _data_sz += obj_opCodeManager.get_size(_pt);
                                else _data_sz += 3;
                                if (array_length(_parsed[_pi]) > 1 && is_real(_parsed[_pi][1])) {
                                    if (string_pos("_abs", _pt) > 0 || string_pos("_ind", _pt) > 0 || string_pos("_zp", _pt) > 0) {
                                        array_push(code_seg_cache, { addr: _parsed[_pi][1], size: 2, lines: [_cur_line], no_conflict: true });
                                    }
                                }
                                if (_cur_line > 0) {
                                    var _has_line = false;
                                    for (var _li = 0; _li < array_length(_data_lines); _li++) {
                                        if (_data_lines[_li] == _cur_line) { _has_line = true; break; }
                                    }
                                    if (!_has_line) array_push(_data_lines, _cur_line);
                                }
                            }
                        }
                        if (_data_pc >= 0 && _data_sz > 0)
                            array_push(code_seg_cache, { addr: _data_pc, size: _data_sz, lines: _data_lines, no_conflict: false });
                        code_cache_dirty = false;
                    }
                    var _mc_name = (code_descriptor != "") ? code_descriptor : (node_title != "" ? node_title : "MACRO_CODE");
                    for (var _sci = 0; _sci < array_length(code_seg_cache); _sci++) {
                        var _csc = code_seg_cache[_sci];
                        array_push(_segments, { addr: _csc.addr, size: _csc.size, lines: _csc.lines, col: make_color_rgb(180, 120, 255), type: "CODE", name: _mc_name, node_id: id, no_conflict: _csc.no_conflict, conflict: false });
                    }
                    if (total_node_size > 0) {
                        array_push(_segments, { addr: pc_address, size: total_node_size, col: make_color_rgb(180, 120, 255), type: "CODE", name: _mc_name, lines: [], node_id: id, no_conflict: true, conflict: false });
                    }
                }
            } break;

            case "MACRO_SCROLL": {
                var _n_name = (node_title != "") ? node_title : "MAP H SCROLL";
                if (total_node_size > 0) {
                    var _pc_hex = string_upper(decimal_to_hex(pc_address));
                    while (string_length(_pc_hex) < 4) _pc_hex = "0" + _pc_hex;
                    array_push(_segments, { addr: pc_address, size: total_node_size, col: make_color_rgb(40, 180, 160), type: "MACRO", name: _n_name + " AT $" + _pc_hex, lines: [], node_id: id, no_conflict: false, conflict: false });
                }

                // META_TILESET source mode is flattened by MACRO_SCROLL at
                // compile time. Those bytes really occupy the BASE range from
                // instructions[0][9], but previously the memory bar showed the
                // editor-only packed META_TILESET at its asset address instead.
                // Mirror the compiler's geometry exactly: LIT packs the chosen
                // map; VAR packs every map sequentially into one contiguous
                // character-plane allocation.
                var _flat_src_mode = (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) ? real(instructions[0][6]) : 0;
                if (_flat_src_mode == 1) {
                    var _flat_ts_name = (array_length(instructions[0]) > 7) ? string(instructions[0][7]) : "";
                    var _flat_map_idx = (array_length(instructions[0]) > 8 && is_real(instructions[0][8])) ? real(instructions[0][8]) : 0;
                    var _flat_base    = (array_length(instructions[0]) > 9 && is_real(instructions[0][9])) ? real(instructions[0][9]) : 0x4000;
                    var _flat_varmode = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
                    if (_flat_base < 0x0400) _flat_base = 0x4000;

                    var _flat_ts = noone;
                    if (_flat_ts_name != "" && instance_exists(obj_asset_manager)) {
                        var _flat_am = obj_asset_manager;
                        for (var _flat_ai = 0; _flat_ai < ds_list_size(_flat_am.asset_list); _flat_ai++) {
                            var _flat_a = ds_list_find_value(_flat_am.asset_list, _flat_ai);
                            if (_flat_a.type == "META_TILESET" && _flat_a.name == _flat_ts_name) {
                                _flat_ts = _flat_a;
                                break;
                            }
                        }
                    }

                    if (_flat_ts != noone) {
                        var _flat_tm    = _flat_ts.meta;
                        var _flat_sw    = max(1, _flat_tm.stamp_w);
                        var _flat_sh    = max(1, _flat_tm.stamp_h);
                        var _flat_size  = 0;
                        var _flat_count = 0;
                        var _flat_first = (_flat_varmode == 1) ? 0 : _flat_map_idx;
                        var _flat_last  = (_flat_varmode == 1) ? (_flat_tm.map_count - 1) : _flat_map_idx;

                        for (var _flat_mi = _flat_first; _flat_mi <= _flat_last; _flat_mi++) {
                            if (_flat_mi < 0 || _flat_mi >= _flat_tm.map_count) continue;
                            if (_flat_mi >= array_length(_flat_tm.maps)) continue;
                            var _flat_grid = _flat_tm.maps[_flat_mi];
                            var _flat_w    = 40;
                            if (_flat_mi < array_length(_flat_tm.map_w)) {
                                _flat_w = _flat_tm.map_w[_flat_mi];
                            }
                            var _flat_cols = max(1, floor(_flat_w / _flat_sw));
                            var _flat_rows = floor(array_length(_flat_grid) / _flat_cols);
                            var _flat_h    = _flat_rows * _flat_sh;
                            _flat_size += _flat_w * _flat_h;
                            _flat_count++;
                        }

                        if (_flat_size > 0) {
                            var _flat_hex = string_upper(decimal_to_hex(_flat_base));
                            while (string_length(_flat_hex) < 4) _flat_hex = "0" + _flat_hex;
                            var _flat_end_hex = string_upper(decimal_to_hex(_flat_base + _flat_size - 1));
                            while (string_length(_flat_end_hex) < 4) _flat_end_hex = "0" + _flat_end_hex;
                            var _flat_mode_name = (_flat_varmode == 1)
                                ? ("VAR " + string(_flat_count) + " MAPS")
                                : ("LIT MAP " + string(_flat_map_idx));
                            array_push(_segments, {
                                addr:        _flat_base,
                                size:        _flat_size,
                                col:         make_color_rgb(245, 210, 70),
                                type:        "ASSET",
                                name:        _flat_ts_name + " HSCROLL FLAT DATA " + _flat_mode_name
                                           + " $" + _flat_hex + "-$" + _flat_end_hex
                                           + " (" + string(_flat_size) + " BYTES)",
                                lines:       [],
                                node_id:     id,
                                no_conflict: false,
                                conflict:    false
                            });
                        }
                    }
                }

                // Buffer 2 sits at screen RAM base + $0800 — resolve from MACRO_VIC
                var _scroll_scr1 = scr_resolve_screen_ram();
                var _scroll_buf2 = _scroll_scr1 + 0x0800;
                var _buf2_hex = string_upper(decimal_to_hex(_scroll_buf2));
                while (string_length(_buf2_hex) < 4) _buf2_hex = "0" + _buf2_hex;
                array_push(_segments, { addr: _scroll_buf2, size: 0x0400, col: make_color_rgb(40, 180, 160), type: "MACRO", name: _n_name + " (BUF) AT $" + _buf2_hex, lines: [], node_id: id, no_conflict: false, conflict: false });
            } break;

            case "MACRO_TEXT_SCROLL": {
                var _n_name = (node_title != "") ? node_title : "MACRO TEXT SCROLL";
                if (total_node_size > 0) {
                    var _pc_hex = string_upper(decimal_to_hex(pc_address));
                    while (string_length(_pc_hex) < 4) _pc_hex = "0" + _pc_hex;
                    array_push(_segments, { addr: pc_address, size: total_node_size, col: make_color_rgb(80, 200, 160), type: "MACRO", name: _n_name + " AT $" + _pc_hex, lines: [], node_id: id, no_conflict: false, conflict: false });
                }
                if (array_length(instructions[0]) > 6) {
                    var _src = (array_length(instructions[0]) > 9 && is_real(instructions[0][9])) ? real(instructions[0][9]) : 0;
                    var _taddr = is_real(instructions[0][5]) ? real(instructions[0][5]) : 0xC000;
                    var _tlen  = string_length(string(instructions[0][6])) + 1;

                    // If in Asset Mode, fetch the real address from the Asset Manager
                    if (_src == 1 && array_length(instructions[0]) > 10) {
                        var _asset_name = string(instructions[0][10]);
                        if (instance_exists(obj_asset_manager)) {
                            for (var _aci = 0; _aci < ds_list_size(obj_asset_manager.asset_list); _aci++) {
                                var _ac = ds_list_find_value(obj_asset_manager.asset_list, _aci);
                                if (_ac.type == "TEXT_DATA" && _ac.name == _asset_name) {
                                    _taddr = _ac.address;
                                    // Sync index [5] so the node displays the correct hex address
                                    instructions[0][5] = _taddr;
                                    break;
                                }
                            }
                        }
                    }
                    if (_taddr > 0 && _tlen > 0) {
                        var _already_asset = false;
                        if (instance_exists(obj_asset_manager)) {
                            var _am_chk     = obj_asset_manager;
                            var _am_chk_len = ds_list_size(_am_chk.asset_list);
                            for (var _aci = 0; _aci < _am_chk_len; _aci++) {
                                var _ac = ds_list_find_value(_am_chk.asset_list, _aci);
                                if (_ac.type == "TEXT_DATA" && _ac.address == _taddr) {
                                    _already_asset = true;
                                    break;
                                }
                            }
                        }
                        if (!_already_asset) {
                            var _loc_hex = string_upper(decimal_to_hex(_taddr));
                            while (string_length(_loc_hex) < 4) _loc_hex = "0" + _loc_hex;
                            array_push(_segments, { addr: _taddr, size: _tlen, col: make_color_rgb(160, 230, 160), type: "ASSET", name: _n_name + " (TXT) AT $" + _loc_hex, lines: [], node_id: id, no_conflict: false, conflict: false });
                        }
                    }
                }
            } break;

            case "MACRO_PRINT": {
                var _n_name = (node_title != "") ? node_title : "MACRO PRINT";
                if (total_node_size > 0) {
                    var _pc_hex = string_upper(decimal_to_hex(pc_address));
                    while (string_length(_pc_hex) < 4) _pc_hex = "0" + _pc_hex;
                    array_push(_segments, { addr: pc_address, size: total_node_size, col: make_color_rgb(80, 220, 80), type: "MACRO", name: _n_name + " AT $" + _pc_hex, lines: [], node_id: id, no_conflict: false, conflict: false });
                }
                if (array_length(instructions) > 0 && array_length(instructions[0]) > 6) {
                    var _loc  = real(instructions[0][6]);
                    var _txt  = string(instructions[0][5]);
                    var _tlen = string_length(_txt);
                    if (_loc > 0 && _tlen > 0) {
                        var _loc_hex = string_upper(decimal_to_hex(_loc));
                        while (string_length(_loc_hex) < 4) _loc_hex = "0" + _loc_hex;
                        array_push(_segments, { addr: _loc, size: _tlen, col: make_color_rgb(160, 240, 160), type: "ASSET", name: _n_name + " (TXT) AT $" + _loc_hex, lines: [], node_id: id, no_conflict: false, conflict: false });
                    }
                }
            } break;

            case "MACRO_VECTOR_BMP": {
                var _n_name = (node_title != "") ? node_title : "VECTOR BMP";
                // 1. Runtime + per-node spine code
                if (total_node_size > 0) {
                    var _pc_hex = string_upper(decimal_to_hex(pc_address));
                    while (string_length(_pc_hex) < 4) _pc_hex = "0" + _pc_hex;
                    array_push(_segments, { addr: pc_address, size: total_node_size, col: make_color_rgb(120, 200, 220), type: "MACRO", name: _n_name + " AT $" + _pc_hex, lines: [], node_id: id, no_conflict: false, conflict: false });
                }
                // 2. Off-spine command stream — resolve asset + stream_addr + byte size
                var _vbmp_name = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
                if (_vbmp_name != "" && instance_exists(obj_asset_manager)) {
                    var _am_vb = obj_asset_manager;
                    for (var _vbi = 0; _vbi < ds_list_size(_am_vb.asset_list); _vbi++) {
                        var _vba = ds_list_find_value(_am_vb.asset_list, _vbi);
                        if (_vba.type != "VECTOR_BITMAP" || _vba.name != _vbmp_name) continue;
                        var _vm2 = _vba.meta;
                        // Single base drives both regions: node instructions[0][2] = fill-stack
                        // base ($C000 default). Stream sits at base + $0800.
                        var _vb_base = (array_length(instructions[0]) > 2 && is_real(instructions[0][2]) && real(instructions[0][2]) != 0)
                            ? real(instructions[0][2]) : 0x8000;
                        var _saddr = _vb_base + 0x0800;
                        // Byte size: walk commands the same way the compiler does
                        // Sum bytes across ALL pages — each page's stream is
                        // emitted back-to-back off-spine, each ending in an END
                        // byte. Fall back to top-level commands if pages absent.
                        var _sbytes = 0;
                        var _mb_pages = (variable_struct_exists(_vm2, "pages") && is_array(_vm2.pages) && array_length(_vm2.pages) > 0)
                            ? _vm2.pages
                            : [ { commands: (variable_struct_exists(_vm2, "commands") ? _vm2.commands : []) } ];
                        for (var _mpg = 0; _mpg < array_length(_mb_pages); _mpg++) {
                            _sbytes += 1; // this page's END byte
                            var _mb_cmds = (is_struct(_mb_pages[_mpg]) && variable_struct_exists(_mb_pages[_mpg], "commands") && is_array(_mb_pages[_mpg].commands))
                                ? _mb_pages[_mpg].commands : [];
                            for (var _sci = 0; _sci < array_length(_mb_cmds); _sci++) {
                                var _scmd = _mb_cmds[_sci];
                                if (!is_struct(_scmd) || !variable_struct_exists(_scmd, "op")) continue;
                                switch (string(_scmd.op)) {
                                    case "setcol": _sbytes += 2; break;
                                    case "plot":   _sbytes += 4; break;
                                    case "line":   _sbytes += 5; break; // native $02 opcode
                                    case "rect":   _sbytes += 5; break; // native $03 opcode
                                    case "rectfill":    _sbytes += 5; break; // native $04 opcode
                                    case "ellipse":     _sbytes += 5; break; // native $05 opcode
                                    case "ellipsefill": _sbytes += 5; break; // native $06 opcode
                                    case "fill":        _sbytes += 5; break; // $07 + x y pattern colb
                                    default: break;
                                }
                            }
                        }
                        // ── Var-driven LUTs pack immediately after the last
                        // page's END byte, inside the same stream org block
                        // (see MACRO_VECTOR_BMP compile case). They're only
                        // emitted when a var-driven MACRO_VECTOR_PAGE node
                        // targets THIS asset, so mirror that pre-scan here and
                        // extend the stream footprint by 5xN bytes (scrval,
                        // col3, bg, strlo, strhi — one byte per page each).
                        // The dispatch ROUTINE itself is on-spine and already
                        // counted in total_node_size, so it's not added here.
                        var _mb_vp_dispatch = false;
                        with (obj_c64_node) {
                            if (node_type == "MACRO_VECTOR_PAGE") {
                                var _mbp_uv = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 0;
                                if (_mbp_uv == 1) {
                                    var _mbp_asset = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
                                    if (_mbp_asset == _vbmp_name) { _mb_vp_dispatch = true; break; }
                                }
                            }
                        }
                        if (_mb_vp_dispatch) {
                            var _mb_np = array_length(_mb_pages);
                            _sbytes += 5 * _mb_np; // 5 LUTs, 1 byte/page each
                        }

                        var _s_hex = string_upper(decimal_to_hex(_saddr));
                        while (string_length(_s_hex) < 4) _s_hex = "0" + _s_hex;
                        array_push(_segments, { addr: _saddr, size: _sbytes, col: make_color_rgb(80, 160, 200), type: "ASSET", name: _n_name + " STREAM AT $" + _s_hex, lines: [], node_id: id, no_conflict: false, conflict: false });
                        // Fill stack — runtime scratch for FILL $07 span-seed algorithm.
                        // Base $C000, grows upward. 256 bytes (128 x/y seed pairs) is the
                        // working ceiling for the span-seed version. no_conflict = false so
                        // it flags if any asset/code overlaps it.
                        var _fs_hex  = string_upper(decimal_to_hex(_vb_base));
                        while (string_length(_fs_hex) < 4) _fs_hex = "0" + _fs_hex;
                        array_push(_segments, { addr: _vb_base, size: 2048, col: make_color_rgb(200, 100, 160), type: "MACRO", name: _n_name + " FILL STACK AT $" + _fs_hex, lines: [], node_id: id, no_conflict: false, conflict: false });
                        break;
                    }
                }
            } break;
        }

        if (_seg_size > 0) {
            var _n_name = (code_descriptor != "") ? code_descriptor : (node_title != "" ? node_title : node_type);
            array_push(_segments, { addr: pc_address, size: _seg_size, col: _seg_col, type: "NODE", name: _n_name, lines: [], node_id: id, no_conflict: false, conflict: false });
        }
    }

    // Asset segments
    if (instance_exists(obj_asset_manager)) {
        var _am     = obj_asset_manager;
        var _am_len = ds_list_size(_am.asset_list);

        // Build set of asset names that are streamed in rather than resident:
        //   - LOAD_ORG links (load_later) live on disk and are pulled in on
        //     demand by MACRO_LOADER.
        //   - LOAD_REU links live in REU memory and are DMA'd to their C64
        //     address by MACRO_REU one at a time.
        // Neither must participate in conflict detection against other data at
        // the same address — they're temporally separated, not spatially
        // overlapping. A bitmap animation is the normal case here: every frame
        // is allocated at the same C64 address (e.g. $4000) by design, so the
        // overlap is expected rather than a mistake.
        var _membar_load_later = ds_map_create();
        for (var _lli = 0; _lli < _am_len; _lli++) {
            var _lla = ds_list_find_value(_am.asset_list, _lli);
            if (_lla.type != "LOAD_ORG" && _lla.type != "LOAD_REU") continue;
            if (!variable_struct_exists(_lla, "linked_assets")) continue;
            for (var _llj = 0; _llj < array_length(_lla.linked_assets); _llj++) {
                var _lllink = _lla.linked_assets[_llj];
                if (variable_struct_exists(_lllink, "asset_name") && _lllink.asset_name != "") {
                    ds_map_replace(_membar_load_later, _lllink.asset_name, true);
                }
            }
        }
        for (var _ai = 0; _ai < _am_len; _ai++) {
            // Remember which segments this asset creates. Once its switch has
            // finished, stamp those segments with the stable asset-list index so
            // the memory bar can identify/open the owning asset after sorting.
            var _asset_seg_first = array_length(_segments);
            var _a        = ds_list_find_value(_am.asset_list, _ai);
            var _seg_size = 0;
            var _seg_col  = 0;
            var _a_is_load_later = ds_map_exists(_membar_load_later, _a.name);
            switch (_a.type) {
                case "SPRITE_SET":
                    // Buffer is exactly used_count * 64 bytes of sprite data
                    // (no 2-byte header in the trimmed format). Gate on the
                    // buffer, not the file — created/V2-edited sprite assets
                    // have no source file but a valid buffer.
                    if (buffer_exists(_a.buffer)) {
                        var _spr_used = variable_struct_exists(_a.meta, "used_count")
                            ? clamp(_a.meta.used_count, 1, 64) : 1;
                        _seg_size = _spr_used * 64;
                        _seg_col  = make_color_rgb(200, 120, 40);
                    }
                    break;
                case "BITMAP": {
                    // A bitmap is NOT one contiguous 10192-byte lump — it's three
                    // separate blocks, and in VIC bank 2 they aren't even adjacent
                    // (bitmap at $8000, colour at $9F40, screen way up at $BC00).
                    // The old flat span both over-claimed at the base and completely
                    // missed the screen block, so conflicts against screen RAM went
                    // undetected while phantom ones fired against the gap.
                    //
                    // Emit one segment per real region, all under the SAME asset
                    // name so the conflict detector's name-match rule
                    // (_s1.name == _s2.name && node_id == noone -> skip) keeps them
                    // from flagging against each other. Shade tells them apart:
                    //   bitmap — the standard bright asset blue
                    //   screen — a step darker
                    //   colour — darker still
                    if (_a.file != "" && buffer_exists(_a.buffer) && !_a_is_load_later) {
                        var _mb_br = scr_bmp_regions(_a.address);
                        array_push(_segments, {
                            addr:        _mb_br.bmp_addr,
                            size:        _mb_br.bmp_size,
                            col:         make_color_rgb(80, 180, 220),
                            type:        "ASSET",
                            name:        _a.name,
                            lines:       [],
                            node_id:     noone,
                            no_conflict: false,
                            conflict:    false,
                            load_later:  false
                        });
                        array_push(_segments, {
                            addr:        _mb_br.scr_addr,
                            size:        _mb_br.scr_size,
                            col:         make_color_rgb(50, 120, 160),
                            type:        "ASSET",
                            name:        _a.name,
                            lines:       [],
                            node_id:     noone,
                            no_conflict: false,
                            conflict:    false,
                            load_later:  false
                        });
                        array_push(_segments, {
                            addr:        _mb_br.col_addr,
                            size:        _mb_br.col_size,
                            col:         make_color_rgb(70, 140, 180),
                            type:        "ASSET",
                            name:        _a.name,
                            lines:       [],
                            node_id:     noone,
                            no_conflict: false,
                            conflict:    false,
                            load_later:  false
                        });
                    }
                    // _seg_size stays 0 — the generic push at the bottom of the
                    // switch must NOT also emit a flat span for this asset.
                } break;
                case "SID_MUSIC":
                    if (_a.file != "" && buffer_exists(_a.buffer)) { _seg_size = buffer_get_size(_a.buffer) - 2; _seg_col = make_color_rgb(230, 60, 170); }
                    break;
                case "CHAR_SET":
                    if (buffer_exists(_a.buffer) && buffer_get_size(_a.buffer) >= 8) { _seg_size = buffer_get_size(_a.buffer); _seg_col = make_color_rgb(255, 220, 50); }
                    break;
                case "TEXT_DATA":
                    if (buffer_exists(_a.buffer)) { _seg_size = buffer_get_size(_a.buffer); _seg_col = make_color_rgb(160, 230, 160); }
                    break;
                case "BYTE_DATA":
                    if (buffer_exists(_a.buffer)) { _seg_size = buffer_get_size(_a.buffer); _seg_col = make_color_rgb(180, 120, 255); }
                    break;
                case "SFX_DATA":
                    if (_a.file != "" && array_length(_a.meta.instruments) > 0) {
                        var _sfx_instrs = _a.meta.instruments;
                        var _sfx_sz     = 0;
                        for (var _sfi = 0; _sfi < array_length(_sfx_instrs); _sfi++)
                            _sfx_sz += 3 + array_length(_sfx_instrs[_sfi].wavetable_rows) * 2;
                        _seg_size = max(_sfx_sz, 1);
                        _seg_col  = make_color_rgb(110, 60, 220);
                    }
                    break;
                case "MAP_DATA":
                    if (variable_struct_exists(_a, "meta") && variable_struct_exists(_a.meta, "map_w") && _a.meta.map_w > 0 && _a.meta.map_h > 0) {
                        var _msz = _a.meta.map_w * _a.meta.map_h;
                        array_push(_segments, { addr: _a.address, size: _msz, col: make_color_rgb(40, 200, 180), type: "ASSET", name: _a.name, lines: [], node_id: noone, no_conflict: _a_is_load_later, conflict: false, load_later: _a_is_load_later });
                        array_push(_segments, { addr: _a.address + _msz, size: _msz, col: make_color_rgb(40, 120, 200), type: "ASSET", name: _a.name + " (ATTR)", lines: [], node_id: noone, no_conflict: _a_is_load_later, conflict: false, load_later: _a_is_load_later });
                    }
                    break;
				case "META_TILESET":
				    // Editor/source data only. Runtime macros emit their real C64
				    // representation separately, so reserving the asset's nominal
				    // address here creates a false memory-bar allocation.
				    break;

			case "META_MAP": {
			    var _mm_ts = noone;
			    var _mm_ts_name = _a.meta.tileset_name;
			    if (instance_exists(obj_asset_manager)) {
			        for (var _mmi = 0; _mmi < ds_list_size(obj_asset_manager.asset_list); _mmi++) {
			            var _mma = ds_list_find_value(obj_asset_manager.asset_list, _mmi);
			            if (_mma.type == "META_TILESET" && _mma.name == _mm_ts_name) {
			                _mm_ts = _mma;
			                break;
			            }
			        }
			    }
			    var _mm_stamp_bytes = (_mm_ts != noone) ? (_mm_ts.meta.stamp_w * _mm_ts.meta.stamp_h * 2) : 8;
			    var _mm_ts_size     = (_mm_ts != noone) ? (_mm_ts.meta.stamp_count * _mm_stamp_bytes) : 0;
			    var _mm_idx_size    = array_length(_a.meta.index_data);
			    var _mm_total       = _mm_ts_size + _mm_idx_size;
			    if (_mm_total > 0) {
			        var _mm_hex = string_upper(decimal_to_hex(0x8000));
			        array_push(_segments, {
			            addr:      0x8000,
			            size:      _mm_total,
			            col:       make_color_rgb(80, 140, 255),
			            type:      "ASSET",
			            name:      _a.name + " (META) AT $8000",
			            lines:     [],
			            node_id:   noone,
			            no_conflict: _a_is_load_later,
			            conflict:  false,
			            load_later: _a_is_load_later
			        });
			    }
			} break;

            }
            if (_seg_size > 0)
                array_push(_segments, { addr: _a.address, size: _seg_size, col: _seg_col, type: "ASSET", name: _a.name, lines: [], node_id: noone, no_conflict: _a_is_load_later, conflict: false, load_later: _a_is_load_later });

            for (var _asi = _asset_seg_first; _asi < array_length(_segments); _asi++) {
                _segments[_asi].asset_index = _ai;
            }
        }

        global.memory_bar_disk_assets = [];
        for (var _dli2 = 0; _dli2 < ds_list_size(_am.asset_list); _dli2++) {
            var _lo2 = ds_list_find_value(_am.asset_list, _dli2);
            if (_lo2.type != "LOAD_ORG") continue;
            if (!variable_struct_exists(_lo2, "linked_assets")) continue;
            for (var _loli2 = 0; _loli2 < array_length(_lo2.linked_assets); _loli2++) {
                var _lolink2 = _lo2.linked_assets[_loli2];
                if (!variable_struct_exists(_lolink2, "asset_name") || _lolink2.asset_name == "") continue;
                var _linked_name = _lolink2.asset_name;
                // Find the actual asset
                for (var _lai2 = 0; _lai2 < ds_list_size(_am.asset_list); _lai2++) {
                    var _dla2 = ds_list_find_value(_am.asset_list, _lai2);
                    if (_dla2.name != _linked_name) continue;
                    var _dla_sz2 = 0;
                    if ((_dla2.type == "BITMAP" || _dla2.type == "BITMAP_KLA") && buffer_exists(_dla2.buffer)) {
                        _dla_sz2 = 10192;
                    } else if (_dla2.type == "SID_MUSIC" && buffer_exists(_dla2.buffer)) {
                        _dla_sz2 = buffer_get_size(_dla2.buffer) - 2;
                    } else if (_dla2.type == "SPRITE_SET" && buffer_exists(_dla2.buffer)) {
                        _dla_sz2 = buffer_get_size(_dla2.buffer);
                    } else if (_dla2.type == "CHAR_SET" && buffer_exists(_dla2.buffer)) {
                        _dla_sz2 = buffer_get_size(_dla2.buffer);
                    } else if (_dla2.type == "TEXT_DATA" && buffer_exists(_dla2.buffer)) {
                        _dla_sz2 = buffer_get_size(_dla2.buffer);
                    } else if (_dla2.type == "BYTE_DATA" && buffer_exists(_dla2.buffer)) {
                        _dla_sz2 = buffer_get_size(_dla2.buffer);
                    } else if (_dla2.type == "SFX_DATA" && variable_struct_exists(_dla2.meta, "instruments")) {
                        var _sfx_instrs2 = _dla2.meta.instruments;
                        for (var _sfi2 = 0; _sfi2 < array_length(_sfx_instrs2); _sfi2++) {
                            _dla_sz2 += 3 + array_length(_sfx_instrs2[_sfi2].wavetable_rows) * 2;
                        }
                        _dla_sz2 = max(_dla_sz2, 1);
                    } else if (_dla2.type == "MAP_DATA" && variable_struct_exists(_dla2.meta, "map_w")) {
                        var _mw2 = _dla2.meta.map_w;
                        var _mh2 = _dla2.meta.map_h;
                        _dla_sz2 = _mw2 * _mh2 * 4; // raw + colour + two transposed planes
                    }
                    if (_dla_sz2 > 0) {
                        array_push(global.memory_bar_disk_assets, {
                            addr:          _dla2.address,
                            size:          _dla_sz2,
                            name:          _dla2.name,
                            type:          _dla2.type,
                            load_org_name: _lo2.name
                        });
                    }
                    break;
                }
            }
        }
        ds_map_destroy(_membar_load_later);
    }
    if (!variable_global_exists("memory_bar_disk_assets")) {
        global.memory_bar_disk_assets = [];
    }

    // Sort
    array_sort(_segments, function(_a, _b) { return _a.addr - _b.addr; });

    // Reset conflict flags
    var _seg_total = array_length(_segments);
    for (var _r = 0; _r < _seg_total; _r++) {
        _segments[_r].conflict = false;
    }

    // Conflict detection
    var _conflicts = [];
    for (var _i = 0; _i < _seg_total; _i++) {
        for (var _j = _i + 1; _j < _seg_total; _j++) {
            var _s1 = _segments[_i];
            var _s2 = _segments[_j];
            if (_s1.node_id == _s2.node_id && _s1.node_id != noone) continue;
            if (_s1.name == _s2.name && _s1.node_id == noone && _s2.node_id == noone) continue;
            var _s1_org = (_s1.type == "NODE" || _s1.type == "VARIABLE_BLOCK");
            var _s2_org = (_s2.type == "NODE" || _s2.type == "VARIABLE_BLOCK");
            var _s1_is_dbuf = (string_pos("(BUF)", _s1.name) > 0);
            var _s2_is_dbuf = (string_pos("(BUF)", _s2.name) > 0);
            if (_s1_org && (_s2.type == "MACRO" || _s2.type == "CODE") && !_s2_is_dbuf) continue;
            if (_s2_org && (_s1.type == "MACRO" || _s1.type == "CODE") && !_s1_is_dbuf) continue;
            var _start1 = _s1.addr;
            var _end1   = _s1.addr + _s1.size;
            var _start2 = _s2.addr;
            var _end2   = _s2.addr + _s2.size;
            if (_start1 >= _end2 || _end1 <= _start2) continue;
            var _cstart  = max(_start1, _start2);
            var _cfinish = min(_end1,   _end2);
            var _is_shared = false;
            if      (_cstart <= 0x03FF)                              _is_shared = true;
            else if (_cstart >= 0x0400 && _cstart <= 0x07FF)        _is_shared = true;
            else if (_cstart >= 0xD000 && _cstart <= 0xDFFF)        _is_shared = true;
            if (!_is_shared) {
                var _s1_logical = (_s1.type == "CODE" || _s1.type == "MACRO");
                var _s2_logical = (_s2.type == "CODE" || _s2.type == "MACRO");
                var _s1_asset   = (_s1.type == "ASSET");
                var _s2_asset   = (_s2.type == "ASSET");
                if ((_s1_logical && _s2_asset) || (_s2_logical && _s1_asset)) _is_shared = true;
                if (_s1_logical && _s2_logical) _is_shared = true;
            }
            if (!_is_shared && (_s1.no_conflict || _s2.no_conflict)) _is_shared = true;
            if (!_is_shared) {
                var _screen_block_offset = _cstart & 0x03FF;
                if (_screen_block_offset >= 0x03F8 && _screen_block_offset <= 0x03FF) _is_shared = true;
            }
            // Honour user-ignored conflicts (workspace-scoped suppress list)
            if (!_is_shared) {
                if (scr_is_conflict_ignored(_cstart, _cfinish, _s1.node_id, _s2.node_id)) {
                    _is_shared = true;
                }
            }
            if (!_is_shared) {
                var _merged    = false;
                var _target_cf = noone;
                for (var _c = 0; _c < array_length(_conflicts); _c++) {
                    if (_cstart <= _conflicts[_c].finish + 16 && _cfinish >= _conflicts[_c].start - 16) {
                        _conflicts[_c].start  = min(_conflicts[_c].start,  _cstart);
                        _conflicts[_c].finish = max(_conflicts[_c].finish, _cfinish);
                        _target_cf = _conflicts[_c];
                        _merged    = true;
                        break;
                    }
                }
                if (!_merged) {
                    _target_cf = { start: _cstart, finish: _cfinish, is_var_clash: false };
                    array_push(_conflicts, _target_cf);
                }
                _s1.conflict = true;
                _s2.conflict = true;
                if (_s1.name == "VARIABLES" || _s2.name == "VARIABLES") {
                    _target_cf.is_var_clash = true;
                }
            }
        }
    }



    global.memory_bar_segments  = _segments;
    global.memory_bar_conflicts = _conflicts;
    global.memory_bar_dirty     = false;
}
