/// scr_undo_restore(_path)
/// Restores node/asset state from a snapshot JSON. Does not touch workspace path globals.
function scr_undo_restore(_path) {
    if (!file_exists(_path)) {
        show_debug_message("UNDO RESTORE: File not found: " + _path);
        exit;
    }

    var _f = file_text_open_read(_path);
    var _raw = "";
    while (!file_text_eof(_f)) { _raw += file_text_read_string(_f); file_text_readln(_f); }
    file_text_close(_f);
    var _data = json_parse(_raw);

    var _nodes  = variable_struct_exists(_data, "nodes")  ? _data.nodes  : [];
    var _boxes  = variable_struct_exists(_data, "boxes")  ? _data.boxes  : [];
    var _assets = variable_struct_exists(_data, "assets") ? _data.assets : [];

    // --- CLEAR CURRENT STATE ---
    global.node_destroy_fx = false;
    instance_destroy(obj_c64_node);
    instance_destroy(obj_mapping_box);
    global.node_destroy_fx = true;
/*
// removed in V096_A1 : unwanted clearing on UNDO
    // Clear asset manager (no buffer delete — files live on disk)
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = ds_list_size(_am.asset_list) - 1; _ai >= 0; _ai--) {
            var _old = ds_list_find_value(_am.asset_list, _ai);
            if (buffer_exists(_old.buffer)) buffer_delete(_old.buffer);
            if (_old.type == "SPRITE_SET" && variable_struct_exists(_old.meta, "spr_sprites")) {
                for (var _si = 0; _si < array_length(_old.meta.spr_sprites); _si++) {
                    if (sprite_exists(_old.meta.spr_sprites[_si])) sprite_delete(_old.meta.spr_sprites[_si]);
                }
            }
        }
        ds_list_clear(_am.asset_list);
    }

*/ 
    var _header_h   = 24;
    var _line_h   = 12;
    var _pad      = 10;

    // --- REBUILD NODES (reuse load logic) ---
    for (var _i = 0; _i < array_length(_nodes); _i++) {
        var _d = _nodes[_i];
        if (_d.type == "EXECUTE") continue;
        var _n = instance_create_layer(_d.x, _d.y, "Layer_Nodes", obj_c64_node);
        _n.is_dragging  = true;
        _n.node_title   = _d.title;
        _n.node_type    = _d.type;
        _n.instructions = _d.code;
        _n.is_connected = _d.connected;
        if (variable_struct_exists(_d, "pc_address"))   _n.pc_address   = _d.pc_address;
        if (variable_struct_exists(_d, "end_address"))  _n.end_address  = _d.end_address;
        if (variable_struct_exists(_d, "x_indent"))     _n.x_indent     = _d.x_indent;
        if (variable_struct_exists(_d, "stable_uid"))   _n.stable_uid   = _d.stable_uid;
		if (variable_struct_exists(_d, "anim_alias") && _d.anim_alias != "")         _n.anim_alias       = _d.anim_alias;
        if (variable_struct_exists(_d, "scroll_alias") && _d.scroll_alias != "")     _n.scroll_alias     = _d.scroll_alias;
        if (variable_struct_exists(_d, "code_descriptor") && _d.code_descriptor != "") _n.code_descriptor = _d.code_descriptor;
		_n.show_only_used = variable_struct_exists(_d, "show_only_used") ? _d.show_only_used : false;
        if (_n.node_type == "MACRO_JOY") _n.height_dirty = true; // Force height update for Joy nodes

        // Heights/widths
        if (_n.node_type == "DATA_TEXT") {
            draw_set_font(fnt_c64_code);
            var _txt        = (array_length(_n.instructions) > 0) ? string(_n.instructions[0][1]) : "";
            var _measured_w = string_width("\"" + _txt + "\"") + 20;
            _n.width        = clamp(max(global.node_display_width, _measured_w), 200, 480);
        } else if (_n.node_type == "SPR64") {
            _n.width = 200;
        } else {
            _n.width = global.node_display_width;
        }

        if (_n.node_type == "COMMENT") {
            draw_set_font(fnt_c64_code);
            var _comment_raw = (array_length(_n.instructions) > 0) ? string(_n.instructions[0][1]) : "";
            var _text_w      = global.node_display_width - 20;
            var _text_body_h = string_height_ext(_comment_raw, _line_h, _text_w);
            _n.height        = _header_h + max(_line_h, _text_body_h) + _pad;
        } else if (_n.node_type == "ORG") {
            _n.height = _header_h + (_line_h * 2) + _pad;
        } else if (_n.node_type == "SPR64") {
            _n.height = _header_h + (21 * 4) + _pad + 16;
        } else {
            _n.height = _header_h + (array_length(_n.instructions) * _line_h) + _pad;
        }
        if (variable_struct_exists(_d, "height")) _n.height = _d.height;

        if (_n.node_type == "INIT") _n.is_draggable = false;
        if (_n.node_type == "ORG") {
            _n.is_draggable = true;
            _n.is_connected = false;
            _n.proxy        = variable_struct_exists(_d, "proxy") ? _d.proxy : true;
            // Snapshots taken before the fold existed restore expanded.
            _n.collapsed    = false;
            if (variable_struct_exists(_d, "collapsed")) {
                _n.collapsed = _d.collapsed;
            }
        }
    }

    // Restore ORG parent links (same pattern as scr_load_workspace_dialog 5A)
    with (obj_c64_node) {
        if (node_type == "ORG" || node_type == "INIT") continue;
        var _linked = false;
        for (var _li = 0; _li < array_length(_nodes); _li++) {
            var _ld = _nodes[_li];
            if (abs(x - _ld.x) < 4 && abs(y - _ld.y) < 4) {
                if (variable_struct_exists(_ld, "org_parent_x") && _ld.org_parent_x != -1) {
                    _target_ox = _ld.org_parent_x;
                    _target_oy = _ld.org_parent_y;
                    with (obj_c64_node) {
                        if (node_type == "ORG" && abs(x - other._target_ox) < 4 && abs(y - other._target_oy) < 4) {
                            other.org_parent   = id;
                            other.is_connected = true;
                            other._linked      = true;
                        }
                    }
                }
                break;
            }
        }
    }

// Restore proxy flags and wire fields (5B)
    with (obj_c64_node) {
        if (node_type != "ORG") continue;
        for (var _li = 0; _li < array_length(_nodes); _li++) {
            var _ld = _nodes[_li];
            if (abs(x - _ld.x) < 2 && abs(y - _ld.y) < 2) {
                proxy = variable_struct_exists(_ld, "proxy") ? _ld.proxy : true;
                if (variable_struct_exists(_ld, "org_uid") && _ld.org_uid > 0) {
                    org_uid = _ld.org_uid;
                    if (org_uid >= global.next_org_uid) {
                        global.next_org_uid = org_uid + 1;
                    }
                }
                wire_out_target = variable_struct_exists(_ld, "wire_out_target") ? _ld.wire_out_target : -1;
                wire_in_source  = variable_struct_exists(_ld, "wire_in_source")  ? _ld.wire_in_source  : -1;
                break;
            }
        }
    }

    // Validate wires — clear any that point to now-missing nodes
    with (obj_c64_node) {
        if (node_type != "ORG") continue;
        if (wire_in_source != -1) {
            var _found = false;
            with (obj_c64_node) {
                if (node_type == "ORG" && org_uid == other.wire_in_source) {
                    _found = true;
                    break;
                }
            }
            if (!_found) {
                wire_in_source = -1;
            }
        }
        if (wire_out_target != -1) {
            var _found = false;
            with (obj_c64_node) {
                if (node_type == "ORG" && org_uid == other.wire_out_target) {
                    _found = true;
                    break;
                }
            }
            if (!_found) {
                wire_out_target = -1;
            }
        }
    }

    // --- REBUILD BOXES ---
    for (var _bi = 0; _bi < array_length(_boxes); _bi++) {
        var _bd = _boxes[_bi];
        var _mb = instance_create_layer(_bd.x, _bd.y, "Layer_Nodes", obj_mapping_box);
        _mb.box_w       = _bd.box_w;
        _mb.box_h       = _bd.box_h;
        _mb.box_name    = _bd.box_name;
        _mb.box_col_idx = _bd.box_col_idx;
    }

    //// --- REBUILD ASSETS from disk ---
    //if (instance_exists(obj_asset_manager)) {
    //    var _am = obj_asset_manager;
    //    for (var _ai = 0; _ai < array_length(_assets); _ai++) {
    //        var _ad = _assets[_ai];
    //        var _buf = buffer_create(1, buffer_fixed, 1);
    //        // Reload buffer from disk if file exists
	//		if (variable_struct_exists(_ad, "file") && _ad.file != "" && file_exists(_ad.file)) {
	//		    buffer_delete(_buf);
	//		    _buf = buffer_load(_ad.file);
	//		    if (!buffer_exists(_buf)) { _buf = buffer_create(1, buffer_fixed, 1); show_debug_message("UNDO RESTORE: buffer_load FAILED for " + _ad.file); }
	//		    else show_debug_message("UNDO RESTORE: loaded " + _ad.file + " size=" + string(buffer_get_size(_buf)));
    //        }
    //        var _meta = {};
    //        var _new_asset = {
    //            name:    _ad.name,
    //            type:    _ad.type,
    //            address: _ad.address,
    //            file:    variable_struct_exists(_ad, "file") ? _ad.file : "",
    //            buffer:  _buf,
    //            meta:    _meta
    //        };
    //        // Re-derive meta from buffer using the same import helpers
    //        switch (_ad.type) {
    //            case "SID_MUSIC":
	//			    show_debug_message("SID_MUSIC restore: buf_size=" + string(buffer_get_size(_buf)) + " file=" + _ad.file);
	//			    if (buffer_exists(_buf) && buffer_get_size(_buf) >= 0x7E) {
    //                    var _bx = _buf;
    //                    var _header_size = (buffer_peek(_bx, 6, buffer_u8) << 8) | buffer_peek(_bx, 7, buffer_u8);
    //                    if (_header_size != 0x76 && _header_size != 0x7C) _header_size = 0x76;
    //                    var _raw_load   = (buffer_peek(_bx, 8, buffer_u8) << 8) | buffer_peek(_bx, 9, buffer_u8);
    //                    var _data_start = (_raw_load == 0) ? _header_size + 2 : _header_size;
    //                    var _load_addr  = (_raw_load != 0) ? _raw_load
    //                                    : (buffer_peek(_bx, _header_size, buffer_u8) | (buffer_peek(_bx, _header_size + 1, buffer_u8) << 8));
    //                    var _init_addr  = (buffer_peek(_bx, 0x0A, buffer_u8) << 8) | buffer_peek(_bx, 0x0B, buffer_u8);
    //                    var _play_addr  = (buffer_peek(_bx, 0x0C, buffer_u8) << 8) | buffer_peek(_bx, 0x0D, buffer_u8);
    //                    if (_init_addr == 0) _init_addr = _load_addr;
    //                    if (_play_addr == 0) _play_addr = _load_addr + 3;
    //                    _meta.sid_init_addr  = _init_addr;
    //                    _meta.sid_play_addr  = _play_addr;
	//					show_debug_message("SID_MUSIC meta: init=$" + string_upper(decimal_to_hex(_init_addr)) + " play=$" + string_upper(decimal_to_hex(_play_addr)));
    //                    _meta.sid_data_start = _data_start;
    //                    _new_asset.address   = _load_addr;
    //                }
    //                break;
	//				case "SPRITE_SET":
    //                _meta.spr_sprites = array_create(64, -1);
    //                if (variable_struct_exists(_ad, "meta")) {
    //                    var _sm = _ad.meta;
    //                    if (variable_struct_exists(_sm, "used_count"))  _meta.used_count  = _sm.used_count;
    //                    if (variable_struct_exists(_sm, "bg_col"))      _meta.bg_col      = _sm.bg_col;
    //                    if (variable_struct_exists(_sm, "mc1_col"))     _meta.mc1_col     = _sm.mc1_col;
    //                    if (variable_struct_exists(_sm, "mc2_col"))     _meta.mc2_col     = _sm.mc2_col;
    //                    if (variable_struct_exists(_sm, "sprite_json")) _meta.sprite_json = _sm.sprite_json;
    //                    if (variable_struct_exists(_sm, "sprite_mcs"))  _meta.sprite_mcs  = _sm.sprite_mcs;
    //                    if (variable_struct_exists(_sm, "sprite_ucs"))  _meta.sprite_ucs  = _sm.sprite_ucs;
    //                }
    //                if (_new_asset.file != "" && variable_struct_exists(_meta, "used_count"))
    //                    scr_asset_spr_cache_sprites(_new_asset);
    //                break;
    //            case "BITMAP":
    //                scr_asset_bmp_build_preview(_new_asset);
    //                break;
    //            case "CHAR_SET":
    //                if (buffer_exists(_buf) && buffer_get_size(_buf) > 8) {
    //                    var _char_count  = buffer_get_size(_buf) div 8;
    //                    _meta.format     = "binary";
    //                    _meta.char_count = _char_count;
    //                    _meta.total_size = _char_count * 8;
    //                    _meta.preview_surf = -1;
    //                    _meta.mc_mode = 0; _meta.mc_fg = 1; _meta.mc_bg = 0;
    //                    _meta.mc_col1 = 1; _meta.mc_col2 = 2;
    //                    _new_asset.file_name = filename_name(_new_asset.file);
    //                    scr_asset_chr_build_preview(_new_asset);
    //                }
    //                break;
    //            case "TEXT_DATA":
    //                _meta.text = "";
    //                scr_asset_text_flush(_new_asset);
    //                break;
	//			case "BYTE_DATA":
    //                _meta.byte_string = "";
    //                scr_asset_byte_data_flush(_new_asset);
    //                break;
    //            case "SFX_DATA":
    //                if (_new_asset.file != "" && file_exists(_new_asset.file)) {
    //                    var _buf2 = buffer_load(_new_asset.file);
    //                    if (buffer_exists(_buf2)) {
    //                        if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
    //                        _new_asset.buffer = _buf2;
    //                        scr_asset_sfx_data_import(_new_asset, _new_asset.file);
    //                    } else {
    //                        show_debug_message("UNDO RESTORE: SFX_DATA buffer_load failed for " + _new_asset.file);
    //                    }
    //                } else {
    //                    show_debug_message("UNDO RESTORE: SFX_DATA file missing: " + string(_new_asset.file));
    //                }
    //                break;
	//			case "MAP_DATA":
    //                _meta.preview_surf  = -1;
    //                _meta.tool          = "CHAR";
    //                _meta.zoom          = 2;
    //                _meta.scroll_x      = 0;
    //                _meta.scroll_y      = 0;
    //                _meta.active_char   = 0;
    //                _meta.active_colour = 1;
    //                _meta.mc_mode       = 2;
    //                _meta.paint_mc      = 0;
    //                _meta.map_mc_bg     = -1;
    //                _meta.map_mc_col1   = -1;
    //                _meta.map_mc_col2   = -1;
    //                _meta.map_mc_col2   = -1;
    //                _meta.override_grid = [];
    //                // Derive map_w/map_h from snapshot asset entry if available
    //                if (variable_struct_exists(_ad, "meta")) {
    //                    var _sm = _ad.meta;
    //                    if (variable_struct_exists(_sm, "map_w"))       _meta.map_w       = _sm.map_w;
    //                    if (variable_struct_exists(_sm, "map_h"))       _meta.map_h       = _sm.map_h;
    //                    if (variable_struct_exists(_sm, "grid_w"))      _meta.grid_w      = _sm.grid_w;
    //                    if (variable_struct_exists(_sm, "grid_h"))      _meta.grid_h      = _sm.grid_h;
    //                    if (variable_struct_exists(_sm, "chr_asset"))   _meta.chr_asset   = _sm.chr_asset;
    //                    if (variable_struct_exists(_sm, "char_grid"))   _meta.char_grid   = _sm.char_grid;
    //                    if (variable_struct_exists(_sm, "colour_grid")) _meta.colour_grid = _sm.colour_grid;
    //                    if (variable_struct_exists(_sm, "override_grid")) _meta.override_grid = _sm.override_grid;
    //                }
    //                break;
    //        }
    //        ds_list_add(_am.asset_list, _new_asset);
    //    }
    //}


// --- PRIME MACRO_CODE CACHE ---
    with (obj_c64_node) {
        if (node_type != "MACRO_CODE") continue;
        if (array_length(instructions) == 0 || array_length(instructions[0]) < 2) continue;
        var _ct = string(instructions[0][1]);
        if (_ct == "") continue;
        var _stats = scr_parse_asm_byte_count(_ct);
        code_cached_bytes  = _stats[0];
        code_cached_cycles = _stats[1];
        code_cached_lines  = array_length(string_split(_ct, "\n"));
var _parsed = scr_parse_asm_text(_ct);
        code_seg_cache = [];
        var _data_pc = -1, _data_sz = 0, _data_lines = [], _cur_line = -1;
        for (var _pi = 0; _pi < array_length(_parsed); _pi++) {
            var _pt = string_lower(_parsed[_pi][0]);
            if (_pt == "_line_map_") {
                _cur_line = _parsed[_pi][1];
            } else if (_pt == "pc") {
                if (_data_pc >= 0 && _data_sz > 0)
                    array_push(code_seg_cache, { addr: _data_pc, size: _data_sz, lines: _data_lines });
                _data_pc = _parsed[_pi][1];
                _data_sz = 0;
                _data_lines = [];
            } else if (_pt == "const") {
                if (array_length(_parsed[_pi]) > 2 && is_real(_parsed[_pi][2]))
                    array_push(code_seg_cache, { addr: _parsed[_pi][2], size: 2, lines: [_cur_line] });
            } else if (_pt == "byte") {
                _data_sz += array_length(_parsed[_pi]) - 1;
            } else if (_pt != "label") {
                if (instance_exists(obj_opCodeManager)) _data_sz += obj_opCodeManager.get_size(_pt);
                else _data_sz += 3;
                if (array_length(_parsed[_pi]) > 1 && is_real(_parsed[_pi][1])) {
                    if (string_pos("_abs", _pt) > 0 || string_pos("_ind", _pt) > 0 || string_pos("_zp", _pt) > 0)
                        array_push(code_seg_cache, { addr: _parsed[_pi][1], size: 2, lines: [_cur_line] });
                }
            }
        }
        if (_data_pc >= 0 && _data_sz > 0)
            array_push(code_seg_cache, { addr: _data_pc, size: _data_sz, lines: _data_lines });
        code_cache_dirty = false;
    }

// --- REBUILD NAMED_LOC META ---
    with (obj_c64_node) {
        if (node_type != "NAMED_LOC") continue;
        var _name = string(instructions[0][1]);
        if (_name == "" || _name == "< NO NAME >") continue;
        if (scr_nloc_find_meta(_name) != undefined) continue;
        var _is_hw = (string_pos("HW_", _name) == 1);
        if (!_is_hw) {
            var _enc  = (array_length(instructions[0]) > 2) ? string(instructions[0][2]) : "byte";
            var _size = (_enc == "word" || _enc == "bcd2") ? 2 : ((_enc == "bcd" || _enc == "bcd3") ? 3 : 1);
            var _meta = {
                name:     _name,
                type:     "UV",
                addr:     pc_address,
                size:     _size,
                encoding: _enc,
                chip:     ""
            };
            if (!variable_struct_exists(_meta, "encoding")) { _meta.encoding = "byte"; }
	array_push(global.named_loc_meta, _meta);
	global.named_loc_meta_dirty = true;
            ds_map_replace(global.named_loc_map, _name, pc_address);
        }
    }


    // --- RESTORE CAMERA ---
    if (variable_struct_exists(_data, "camera")) {
        var _wm = obj_workspace_manager;
        _wm.cam_x          = _data.camera.cam_x;
        _wm.cam_y          = _data.camera.cam_y;
        _wm.cam_zoom       = _data.camera.cam_zoom;
        _wm.cam_zoom_target = _data.camera.cam_zoom;
    }

    // --- GLOBALS ---
    global.kernal_unlocked = variable_struct_exists(_data, "kernal_unlocked") ? _data.kernal_unlocked : false;
    global.basic_unlocked  = variable_struct_exists(_data, "basic_unlocked")  ? _data.basic_unlocked  : false;

with (obj_c64_node) { 
        is_dragging = false;
        if (node_type == "MACRO_CODE") code_cache_dirty = true;
    }
    // Heights are DERIVED from node type and content, and a restore writes
    // both straight onto the instances without going through whatever normally
    // raises height_dirty. Without this the restored graph keeps whatever
    // heights the pre-undo nodes happened to have, so the layout pass packs to
    // stale sizes and nodes sit visibly out of place until something unrelated
    // dirties them. Cheap to just re-derive the lot.
    with (obj_c64_node) {
        height_dirty        = true;
        stats_cache_dirty   = true;
        overlap_check_dirty = true;
        last_overlap_check  = false;
    }

    global.addresses_dirty = true;
	
	
	with (obj_c64_node) {
    if (node_type == "MACRO_SFX") {
        show_debug_message("RESTORED MACRO_SFX: instr=" + string(instructions[0][2]) 
            + " voice=" + string(instructions[0][3])
            + " is_real_voice=" + string(is_real(instructions[0][3])));
    }
}
	
    scr_c64_do_update_addresses();

    show_debug_message("UNDO RESTORE: " + _path);
}