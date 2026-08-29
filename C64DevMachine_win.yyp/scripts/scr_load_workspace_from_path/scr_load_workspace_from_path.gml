function scr_load_workspace_from_path(_path) {
    var path = _path;
    if (path == "" || !file_exists(path)) return;
    io_clear();

    global.workspace_path = path;

    var _temp_sprites = working_directory + "temp/sprites";
    if (directory_exists(_temp_sprites)) {
        var _f = file_find_first(_temp_sprites + "/*.png", fa_none);
        while (_f != "") {
            file_delete(_temp_sprites + "/" + _f);
            _f = file_find_next();
        }
        file_find_close();
    }

    global.node_destroy_fx = false;
    instance_destroy(obj_c64_node);
    instance_destroy(obj_mapping_box);
    global.node_destroy_fx = true;

    // Loading a project invalidates any cached flow-overlay edges (they
    // reference the node instances just destroyed above), so drop back
    // to Off rather than leaving a stale/empty overlay toggled on.
    flow_overlay_mode  = 0;
    flow_overlay_edges = [];
    flow_overlay_dirty = true;

    var _jbuf = buffer_load(path);
    var json  = "";
    if (_jbuf != -1) {
        json = buffer_read(_jbuf, buffer_text); // reads entire buffer as one string
        buffer_delete(_jbuf);
    }
    var load_data = json_parse(json);

    var _nodes, _boxes;
    if (is_array(load_data)) {
        _nodes = load_data;
        _boxes = [];
    } else {
        _nodes = variable_struct_exists(load_data, "nodes") ? load_data.nodes : [];
        _boxes = variable_struct_exists(load_data, "boxes") ? load_data.boxes : [];
    }

    var header_h = 20;
    var line_h   = 18;
    var pad      = 10;

    for (var i = 0; i < array_length(_nodes); i++) {
        var d = _nodes[i];
        if (d.type == "EXECUTE") continue;

        var _n = instance_create_layer(d.x, d.y, "Layer_Nodes", obj_c64_node);
        _n.is_dragging = true;

        _n.node_title   = d.title;
        _n.node_type    = d.type;
        _n.instructions = d.code;
        _n.is_connected = d.connected;

        if (variable_struct_exists(d, "pc_address"))   _n.pc_address   = d.pc_address;
        if (variable_struct_exists(d, "end_address"))  _n.end_address  = d.end_address;
        if (variable_struct_exists(d, "x_indent"))     _n.x_indent     = d.x_indent;
        if (variable_struct_exists(d, "anim_alias")   && d.anim_alias   != "") _n.anim_alias   = d.anim_alias;
        if (variable_struct_exists(d, "scroll_alias") && d.scroll_alias != "") _n.scroll_alias = d.scroll_alias;
		if (variable_struct_exists(d, "code_descriptor")) _n.code_descriptor = d.code_descriptor;
		if (variable_struct_exists(d, "helper_text")) _n.helper_text = d.helper_text;
		if (variable_struct_exists(d, "custom_title")) _n.custom_title = string(d.custom_title);
		_n.show_only_used = variable_struct_exists(d, "show_only_used") ? d.show_only_used : false;

		// Restore stable_uid (used by the ignored-conflict suppression list)
		if (variable_struct_exists(d, "stable_uid") && d.stable_uid > 0) {
		    _n.stable_uid = d.stable_uid;
		}
		if (_n.node_type == "MACRO_JOY") {
            _n.height_dirty = true;
            if (array_length(_n.instructions) < 19) {
                array_push(_n.instructions, [0xFF, "NON", 0]);
            }
        }
        if (_n.node_type == "MACRO_TEXT_SCROLL" && array_length(_n.instructions[0]) > 12 && is_string(_n.instructions[0][12]) && string(_n.instructions[0][12]) != "") {
            _n.ts_alias = string(_n.instructions[0][12]);
        }

        // ── MACRO_VECTOR_PAGE layout migration ──
        // House convention: ["macro_vector_page", asset, use_var_flag, page_or_varname]
        //   slot 2 = 0 literal / 1 var,  slot 3 = literal page index OR var name.
        // Legacy saves stored the literal page index in slot 2 with NO slot 3.
        // Discriminator: slot 3 absent => legacy (both new-literal and new-var
        // saves always write slot 3). Migrate legacy: slot 3 = old page, slot 2 = 0.
        if (_n.node_type == "MACRO_VECTOR_PAGE" && array_length(_n.instructions) > 0) {
            if (array_length(_n.instructions[0]) < 4) {
                // Legacy: capture whatever was in slot 2 as the page index.
                var _vp_old_page = (array_length(_n.instructions[0]) > 2 && is_real(_n.instructions[0][2])) ? real(_n.instructions[0][2]) : 0;
                while (array_length(_n.instructions[0]) < 4) {
                    array_push(_n.instructions[0], 0);
                }
                _n.instructions[0][2] = 0;            // use_var flag = literal
                _n.instructions[0][3] = _vp_old_page; // page index moves to slot 3
            } else {
                // Already 4+ slots: just harden slot 2 to a real flag so a
                // corrupt/hand-edited save can't crash the draw/step reads.
                if (!is_real(_n.instructions[0][2])) _n.instructions[0][2] = 0;
            }
        }

        if (variable_struct_exists(d, "binary_blob") && d.binary_blob != "") {
            var _blob     = d.binary_blob;
            var _dec_buf  = scr_blob_decode(_blob);
            var _byte_len = (_dec_buf != noone) ? buffer_get_size(_dec_buf) : 0;

            if (variable_instance_exists(_n, "sprite_buffer")) {
                if (_n.sprite_buffer != noone) buffer_delete(_n.sprite_buffer);
                _n.sprite_buffer = (_dec_buf != noone) ? _dec_buf : buffer_create(1, buffer_fixed, 1);
                _dec_buf = noone; // ownership transferred to sprite_buffer
                if (_n.node_type == "DATA_SID") {
                    _n.sid_load_addr   = real(_n.instructions[0][2]);
                    _n.sid_init_addr   = real(_n.instructions[0][3]);
                    _n.sid_play_addr   = real(_n.instructions[0][4]);
                    _n.sid_songs       = real(_n.instructions[0][5]);
                    _n.sid_start_song  = real(_n.instructions[0][6]);
                    _n.sid_title       = string(_n.instructions[0][7]);
                    _n.sid_author      = (array_length(_n.instructions[0]) > 8) ? string(_n.instructions[0][8]) : "UNKNOWN";
                    _n.total_node_size = buffer_get_size(_n.sprite_buffer);
                    _n.binary_blob     = _blob;
                }
                if (_n.node_type == "SPR64") {
                    _n.total_node_size  = 4096;
                    _n.spr_cached_frame = -1;
                    _n.binary_blob      = _blob;
                }
            }

            if (_n.node_type == "BITMAP_KLA") {
                if (buffer_exists(_n.kla_buffer)) buffer_delete(_n.kla_buffer);
                if (_dec_buf != noone) {
                    _n.kla_buffer = _dec_buf;
                    _dec_buf = noone; // ownership transferred
                } else {
                    _n.kla_buffer = buffer_create(1, buffer_fixed, 1);
                }
                _n.total_node_size = _byte_len;
                _n.binary_blob     = _blob;
                _n.kla_surface     = -1;
            }

            if (_dec_buf != noone) { buffer_delete(_dec_buf); _dec_buf = noone; }
        }

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
            var _text_body_h = string_height_ext(_comment_raw, line_h, _text_w);
            _n.height        = header_h + max(line_h, _text_body_h) + pad;
        } else if (_n.node_type == "ORG") {
            _n.height = header_h + (line_h * 2) + pad;
        } else if (_n.node_type == "SPR64") {
            _n.height = header_h + (21 * 4) + pad + 16;
        } else {
            _n.height = header_h + (array_length(_n.instructions) * line_h) + pad;
        }
        if (variable_struct_exists(d, "height")) _n.height = d.height;

        if (_n.node_type == "INIT") _n.is_draggable = false;
        if (_n.node_type == "ORG") {
            _n.is_draggable = true;
            _n.is_connected = false;
            _n.proxy        = variable_struct_exists(d, "proxy") ? d.proxy : true;
            // Older projects have no fold state; expanded is the default.
            _n.collapsed    = false;
            if (variable_struct_exists(d, "collapsed")) {
                _n.collapsed = d.collapsed;
            }
        }
    }
////
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
        if (!_linked && !is_connected) {
            var _had_org = false;
            for (var _li2 = 0; _li2 < array_length(_nodes); _li2++) {
                var _ld2 = _nodes[_li2];
                if (abs(x - _ld.x) < 4 && abs(y - _ld.y) < 4) {
                    _had_org = variable_struct_exists(_ld2, "has_org_parent") && _ld2.has_org_parent;
                    break;
                }
            }
            if (_had_org) {
                var _best_dist = 999999;
                var _best_org  = noone;
                var _self_x    = x;
                var _self_y    = y;
                with (obj_c64_node) {
                    if (node_type == "ORG" && abs(x - _self_x) < 10) {
                        var _d = abs(y - _self_y);
                        if (_d < _best_dist) { _best_dist = _d; _best_org = id; }
                    }
                }
                if (_best_org != noone) { org_parent = _best_org; is_connected = true; }
            }
        }
    }

    // Restore proxy flags and wire fields for all ORG nodes
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

    with (obj_c64_node) {
        if (node_type != "ORG") continue;
        var _org_ref      = id;
        var _org_children = [];
        with (obj_c64_node) {
            if (org_parent == _org_ref && is_connected) array_push(_org_children, id);
        }
        if (array_length(_org_children) == 0) continue;
        array_sort(_org_children, function(_a, _b) { return _a.y - _b.y; });
        var _stack_y = y + height;
        for (var _ci = 0; _ci < array_length(_org_children); _ci++) {
            _org_children[_ci].y = _stack_y;
            _stack_y += _org_children[_ci].height;
        }
    }

    for (var _bi = 0; _bi < array_length(_boxes); _bi++) {
        var _bd = _boxes[_bi];
        var _mb = instance_create_layer(_bd.x, _bd.y, "Layer_Nodes", obj_mapping_box);
        _mb.box_w       = _bd.box_w;
        _mb.box_h       = _bd.box_h;
        _mb.box_name    = _bd.box_name;
        _mb.box_col_idx = _bd.box_col_idx;
    }

    if (instance_exists(obj_asset_manager) && variable_struct_exists(load_data, "assets")) {
        var _am  = obj_asset_manager;
        var _ads = load_data.assets;

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

        for (var _ai = 0; _ai < array_length(_ads); _ai++) {
            var _ad = _ads[_ai];
            var _buf = noone;
            if (variable_struct_exists(_ad, "blob") && string_length(_ad.blob) > 0) {
                _buf = scr_blob_decode(_ad.blob);
            }
            if (_buf == noone) {
                _buf = buffer_create(1, buffer_fixed, 1);
            }

            var _meta = {};
            if (variable_struct_exists(_ad, "meta")) {
                var _sm = _ad.meta;
                if (variable_struct_exists(_sm, "sprite_mcs"))     _meta.sprite_mcs     = _sm.sprite_mcs;
                if (variable_struct_exists(_sm, "sprite_ucs"))     _meta.sprite_ucs     = _sm.sprite_ucs;
                if (variable_struct_exists(_sm, "mc1_col"))        _meta.mc1_col        = _sm.mc1_col;
                if (variable_struct_exists(_sm, "mc2_col"))        _meta.mc2_col        = _sm.mc2_col;
                if (variable_struct_exists(_sm, "used_count"))     _meta.used_count     = _sm.used_count;
                if (variable_struct_exists(_sm, "bg_col"))         _meta.bg_col         = _sm.bg_col;
                // GRADIENT tool CUSTOM stop run — see scr_save_workspace_as.
                if (variable_struct_exists(_sm, "gradient_custom_active")) _meta.gradient_custom_active = _sm.gradient_custom_active;
                if (variable_struct_exists(_sm, "gradient_custom_cols"))   _meta.gradient_custom_cols   = _sm.gradient_custom_cols;
                if (variable_struct_exists(_sm, "gradient_custom_count"))  _meta.gradient_custom_count  = _sm.gradient_custom_count;
                // Absent = pre-HiRes-support project, which means it was always MC.
                _meta.bmp_mode = variable_struct_exists(_sm, "bmp_mode") ? _sm.bmp_mode : "MC";
                // TONE-SORTED flag. Absent = pre-flag project, which means the
                // bytes were quantised count-sorted, so false is correct.
                _meta.tone_sorted = variable_struct_exists(_sm, "tone_sorted") ? _sm.tone_sorted : false;
                // BITMAP collision tags. Absent = untagged / pre-tag project;
                // scr_asset_bmp_build_preview (called below for every BITMAP)
                // backfills an all-zero grid, so nothing downstream must guard.
                if (variable_struct_exists(_sm, "coll_types") && is_array(_sm.coll_types)) {
                    if (array_length(_sm.coll_types) == 1000) {
                        _meta.coll_types = _sm.coll_types;
                    }
                }
                if (variable_struct_exists(_sm, "sprite_json"))    _meta.sprite_json    = _sm.sprite_json;
                if (variable_struct_exists(_sm, "compositor"))     _meta.compositor     = _sm.compositor;
                if (variable_struct_exists(_sm, "anim"))           _meta.anim           = _sm.anim;
                if (variable_struct_exists(_sm, "sid_init_addr"))  _meta.sid_init_addr  = _sm.sid_init_addr;
                if (variable_struct_exists(_sm, "sid_play_addr"))  _meta.sid_play_addr  = _sm.sid_play_addr;
                if (variable_struct_exists(_sm, "sid_data_start")) _meta.sid_data_start = _sm.sid_data_start;
                if (variable_struct_exists(_sm, "format"))         _meta.format         = _sm.format;
                if (variable_struct_exists(_sm, "tile_types"))     _meta.tile_types     = _sm.tile_types;
                if (variable_struct_exists(_sm, "char_count"))     _meta.char_count     = _sm.char_count;
                if (variable_struct_exists(_sm, "total_size"))     _meta.total_size     = _sm.total_size;
                _meta.mc_mode  = variable_struct_exists(_sm, "mc_mode")  ? _sm.mc_mode  : 0;
                _meta.mc_fg    = variable_struct_exists(_sm, "mc_fg")    ? _sm.mc_fg    : 1;
                _meta.mc_bg    = variable_struct_exists(_sm, "mc_bg")    ? _sm.mc_bg    : 0;
                _meta.mc_col1  = variable_struct_exists(_sm, "mc_col1")  ? _sm.mc_col1  : 1;
                _meta.mc_col2  = variable_struct_exists(_sm, "mc_col2")  ? _sm.mc_col2  : 2;
                _meta.ecm_bg1  = variable_struct_exists(_sm, "ecm_bg1")  ? _sm.ecm_bg1  : 6;
                _meta.ecm_bg2  = variable_struct_exists(_sm, "ecm_bg2")  ? _sm.ecm_bg2  : 14;
                _meta.ecm_bg3  = variable_struct_exists(_sm, "ecm_bg3")  ? _sm.ecm_bg3  : 3;
                _meta.preview_surf = -1;
                _meta.preview_surf = -1;
                if (variable_struct_exists(_sm, "map_w"))          _meta.map_w          = _sm.map_w;
                if (variable_struct_exists(_sm, "map_h"))          _meta.map_h          = _sm.map_h;
                if (variable_struct_exists(_sm, "grid_w"))         _meta.grid_w         = _sm.grid_w;
                if (variable_struct_exists(_sm, "grid_h"))         _meta.grid_h         = _sm.grid_h;
                if (variable_struct_exists(_sm, "char_grid"))      _meta.char_grid      = _sm.char_grid;
                if (variable_struct_exists(_sm, "colour_grid"))    _meta.colour_grid    = _sm.colour_grid;
                if (variable_struct_exists(_sm, "chr_asset"))      _meta.chr_asset      = _sm.chr_asset;
                if (variable_struct_exists(_sm, "scroll_x"))       _meta.scroll_x       = _sm.scroll_x;
                if (variable_struct_exists(_sm, "scroll_y"))       _meta.scroll_y       = _sm.scroll_y;
                if (variable_struct_exists(_sm, "zoom"))           _meta.zoom           = _sm.zoom;
                if (variable_struct_exists(_sm, "active_char"))    _meta.active_char    = _sm.active_char;
                if (variable_struct_exists(_sm, "active_colour"))  _meta.active_colour  = _sm.active_colour;
                if (variable_struct_exists(_sm, "tool"))           _meta.tool           = _sm.tool;
                if (variable_struct_exists(_sm, "text"))           _meta.text           = _sm.text;
                if (variable_struct_exists(_sm, "byte_string"))    _meta.byte_string    = _sm.byte_string;
                if (variable_struct_exists(_sm, "line_string"))    _meta.line_string    = _sm.line_string;
                if (variable_struct_exists(_sm, "lines"))          _meta.lines          = _sm.lines;
                if (variable_struct_exists(_sm, "active_type"))    _meta.active_type    = _sm.active_type;
                if (variable_struct_exists(_sm, "ref_enabled"))    _meta.ref_enabled    = _sm.ref_enabled;
                if (variable_struct_exists(_sm, "ref_asset_name")) _meta.ref_asset_name = _sm.ref_asset_name;
                if (variable_struct_exists(_sm, "ref_offset_x"))   _meta.ref_offset_x   = _sm.ref_offset_x;
                if (variable_struct_exists(_sm, "ref_offset_y"))   _meta.ref_offset_y   = _sm.ref_offset_y;
                if (variable_struct_exists(_sm, "is_save_file"))   _meta.is_save_file   = _sm.is_save_file;
                if (variable_struct_exists(_sm, "save_file_size")) _meta.save_file_size = _sm.save_file_size;
                if (variable_struct_exists(_sm, "mc_mode"))        _meta.mc_mode        = _sm.mc_mode;
                if (variable_struct_exists(_sm, "paint_mc"))       _meta.paint_mc       = _sm.paint_mc;
                if (variable_struct_exists(_sm, "map_mixed"))      _meta.map_mixed      = _sm.map_mixed;
                if (variable_struct_exists(_sm, "override_grid"))  _meta.override_grid  = _sm.override_grid;
                if (variable_struct_exists(_sm, "map_mc_bg"))      _meta.map_mc_bg      = _sm.map_mc_bg;
                if (variable_struct_exists(_sm, "map_mc_col1"))    _meta.map_mc_col1    = _sm.map_mc_col1;
                if (variable_struct_exists(_sm, "map_mc_col2"))    _meta.map_mc_col2    = _sm.map_mc_col2;
            }
            if (_ad.type == "SPRITE_SET") _meta.spr_sprites = array_create(64, -1);

			var _new_asset = {
                name          : _ad.name,
                type          : _ad.type,
                address       : _ad.address,
                file          : variable_struct_exists(_ad, "file") ? _ad.file : "",
                buffer        : _buf,
                meta          : _meta,
                load_later    : variable_struct_exists(_ad, "load_later")    ? _ad.load_later    : false,
                d64_filename  : variable_struct_exists(_ad, "d64_filename")  ? _ad.d64_filename  : "",
                reu_filename  : variable_struct_exists(_ad, "reu_filename")  ? _ad.reu_filename  : ((_ad.type == "LOAD_REU") ? _ad.name + ".reu" : ""),
                reu_size      : variable_struct_exists(_ad, "reu_size")      ? _ad.reu_size      : ((_ad.type == "LOAD_REU") ? 0x1000000 : 0),
                reu_used      : variable_struct_exists(_ad, "reu_used")      ? _ad.reu_used      : ((_ad.type == "LOAD_REU") ? 0x100 : 0),
                linked_assets : variable_struct_exists(_ad, "linked_assets") ? _ad.linked_assets : [],
            };
            if (variable_struct_exists(_ad, "source_file") && _ad.source_file != "")
                _new_asset.meta.source_file = _ad.source_file;

            ds_list_add(_am.asset_list, _new_asset);

            if (_ad.type == "SPRITE_SET") scr_asset_spr_cache_sprites(_new_asset);
            if (_ad.type == "BITMAP"     && buffer_exists(_buf))   scr_asset_bmp_build_preview(_new_asset);
			if (_ad.type == "BITMAP" && buffer_exists(_buf)) {
			    // bmp_mode was just restored onto _new_asset.meta above (or defaulted
			    // to MC), so this is the correct expected size for THIS asset — a
			    // hardcoded 10003 here is exactly what silently dropped HiRes bitmaps:
			    // a valid 9002-byte HiRes buffer always failed both checks below,
			    // so build_preview was never called and the asset looked empty.
			    var _expected_bmp_size = scr_asset_bmp_is_hires(_new_asset) ? 9002 : 10003;
			    if (buffer_get_size(_buf) < _expected_bmp_size && _new_asset.file != "" && file_exists(_new_asset.file)) {
			        buffer_delete(_buf);
			        _buf = buffer_load(_new_asset.file);
			        _new_asset.buffer = _buf;
			    }
			    if (buffer_exists(_buf) && buffer_get_size(_buf) >= _expected_bmp_size) {
			        scr_asset_bmp_build_preview(_new_asset);
			    }
			}
            if (_ad.type == "CHAR_SET"   && buffer_exists(_buf) && buffer_get_size(_buf) > 8) {
                _new_asset.file_name = filename_name(_new_asset.file);
                // Always reload from source file to ensure correct text/binary parsing
                if (_new_asset.file != "" && file_exists(_new_asset.file)) {
                    scr_asset_chr_reload(_new_asset);
                } else {
                    scr_asset_chr_build_preview(_new_asset);
                }
            }
            if (_ad.type == "TEXT_DATA") {
                if (!variable_struct_exists(_new_asset.meta, "text")) _new_asset.meta.text = "";
				_new_asset.meta.inline_edit_open      = false;
				_new_asset.meta.inline_edit_text      = _new_asset.meta.text;
				_new_asset.meta.inline_edit_cursor    = 0;
				_new_asset.meta.inline_edit_scroll_y  = 0;
				_new_asset.meta.inline_edit_sel_start = -1;
				_new_asset.meta.inline_edit_sel_end   = -1;
				_new_asset.meta.inline_edit_blink     = 0;
				_new_asset.meta.inline_edit_key_timer = 0;
				
                scr_asset_text_flush(_new_asset);
            }
			
			
			
            if (_ad.type == "BYTE_DATA") {
               if (!variable_struct_exists(_new_asset.meta, "byte_string")) _new_asset.meta.byte_string = "";
               if (!variable_struct_exists(_new_asset.meta, "is_save_file")) _new_asset.meta.is_save_file = false;
               if (!variable_struct_exists(_new_asset.meta, "save_file_size")) _new_asset.meta.save_file_size = 256;
				_new_asset.meta.inline_edit_open      = false;
				// Sync the edit buffer with the loaded string so the editor isn't empty
				_new_asset.meta.inline_edit_text      = _new_asset.meta.byte_string;
				_new_asset.meta.inline_edit_cursor    = 0;
				_new_asset.meta.inline_edit_scroll_y  = 0;
				_new_asset.meta.inline_edit_sel_start = -1;
				_new_asset.meta.inline_edit_sel_end   = -1;
				_new_asset.meta.inline_edit_blink     = 0;
				_new_asset.meta.inline_edit_key_timer = 0;
                if (!_new_asset.meta.is_save_file) {
                    // Only re-derive the buffer from byte_string for normal BYTE_DATA
                    // assets. Save-file-mode assets already have their real buffer
                    // restored from the saved blob above — byte_string there is just
                    // the stale creation-time default and has nothing to do with the
                    // actual reserved size.
                    scr_asset_byte_data_flush(_new_asset);
                }
            }
            if (_ad.type == "LINE_COLL") {
                if (!variable_struct_exists(_new_asset.meta, "lines"))          _new_asset.meta.lines = [];
                if (!variable_struct_exists(_new_asset.meta, "line_string"))    _new_asset.meta.line_string = "";
                if (!variable_struct_exists(_new_asset.meta, "active_type"))    _new_asset.meta.active_type = 1;
                if (!variable_struct_exists(_new_asset.meta, "ref_enabled"))    _new_asset.meta.ref_enabled = false;
                if (!variable_struct_exists(_new_asset.meta, "ref_asset_name")) _new_asset.meta.ref_asset_name = "";
                if (!variable_struct_exists(_new_asset.meta, "ref_offset_x"))   _new_asset.meta.ref_offset_x = 0;
                if (!variable_struct_exists(_new_asset.meta, "ref_offset_y"))   _new_asset.meta.ref_offset_y = 0;
                _new_asset.meta.draw_x1            = -1;
                _new_asset.meta.draw_y1            = -1;
                _new_asset.meta.line_scroll        = 0;
                _new_asset.meta.ref_picker_open    = false;
                _new_asset.meta.inline_edit_open      = false;
                _new_asset.meta.inline_edit_text      = _new_asset.meta.line_string;
                _new_asset.meta.inline_edit_cursor    = 0;
                _new_asset.meta.inline_edit_scroll_y  = 0;
                _new_asset.meta.inline_edit_sel_start = -1;
                _new_asset.meta.inline_edit_sel_end   = -1;
                _new_asset.meta.inline_edit_blink     = 0;
                _new_asset.meta.inline_edit_key_timer = 0;
                // lines[] is the saved source of truth — rebuild the compiled
                // buffer and line_string from it directly (no text re-parse).
                scr_line_coll_commit(_new_asset);
            }
            if (_ad.type == "SFX_DATA") {
                var _sfx_sm = _ad.meta;
                if (variable_struct_exists(_sfx_sm, "song_name"))   _new_asset.meta.song_name   = _sfx_sm.song_name;
                if (variable_struct_exists(_sfx_sm, "sfx_count"))   _new_asset.meta.sfx_count   = _sfx_sm.sfx_count;
                if (variable_struct_exists(_sfx_sm, "wavetable"))   _new_asset.meta.wavetable   = _sfx_sm.wavetable;
                if (variable_struct_exists(_sfx_sm, "instruments")) {
                    _new_asset.meta.instruments = _sfx_sm.instruments;
                    var _wt     = variable_struct_exists(_new_asset.meta, "wavetable") ? _new_asset.meta.wavetable : noone;
                    var _instrs = _new_asset.meta.instruments;
                    for (var _ii = 0; _ii < array_length(_instrs); _ii++) {
                        var _instr = _instrs[_ii];
                        _instr.wavetable_rows = [];
                        if (_wt == noone || _instr.wave_pos == 0) continue;
                        var _pos    = _instr.wave_pos - 1;
                        var _wt_len = array_length(_wt.left);
                        var _seen   = ds_map_create();
                        while (_pos >= 0 && _pos < _wt_len) {
                            if (ds_map_exists(_seen, _pos)) break;
                            ds_map_add(_seen, _pos, true);
                            var _L = _wt.left[_pos];
                            var _R = _wt.right[_pos];
                            array_push(_instr.wavetable_rows, { left: _L, right: _R, row: _pos + 1 });
                            if (_L == 0xFF) break;
                            _pos++;
                        }
                        ds_map_destroy(_seen);
                    }
                }
            }
            if (_ad.type == "MAP_DATA") {
                if (!variable_struct_exists(_new_asset.meta, "preview_surf"))      _new_asset.meta.preview_surf      = -1;
                if (!variable_struct_exists(_new_asset.meta, "tool"))              _new_asset.meta.tool              = "CHAR";
                if (!variable_struct_exists(_new_asset.meta, "zoom"))              _new_asset.meta.zoom              = 2;
                if (!variable_struct_exists(_new_asset.meta, "scroll_x"))          _new_asset.meta.scroll_x          = 0;
                if (!variable_struct_exists(_new_asset.meta, "scroll_y"))          _new_asset.meta.scroll_y          = 0;
                if (!variable_struct_exists(_new_asset.meta, "active_char"))       _new_asset.meta.active_char       = 0;
                if (!variable_struct_exists(_new_asset.meta, "active_colour"))     _new_asset.meta.active_colour     = 1;
                _new_asset.meta.active_colour = clamp(_new_asset.meta.active_colour, 0, 7);
                if (!variable_struct_exists(_new_asset.meta, "char_strip_offset")) _new_asset.meta.char_strip_offset = 0;
                if (!variable_struct_exists(_new_asset.meta, "mc_mode"))           _new_asset.meta.mc_mode           = 2;
                if (!variable_struct_exists(_new_asset.meta, "paint_mc"))          _new_asset.meta.paint_mc          = 0;
                if (!variable_struct_exists(_new_asset.meta, "map_mixed"))         _new_asset.meta.map_mixed         = obj_workspace_manager.map_global_mixed;
                if (!variable_struct_exists(_new_asset.meta, "map_mc_bg"))         _new_asset.meta.map_mc_bg         = -1;
                if (!variable_struct_exists(_new_asset.meta, "map_mc_col1"))       _new_asset.meta.map_mc_col1       = -1;
                if (!variable_struct_exists(_new_asset.meta, "map_mc_col2"))       _new_asset.meta.map_mc_col2       = -1;
                // Physical stride is grid_w x grid_h, NOT map_w x map_h. Backfill
                // grid dims from saved meta, else from the restored char_grid length,
                // else fall back to logical size for genuinely fresh assets.
                if (!variable_struct_exists(_new_asset.meta, "grid_w") ||
                    !variable_struct_exists(_new_asset.meta, "grid_h")) {
                    var _ml_known = 0;
                    if (variable_struct_exists(_new_asset.meta, "char_grid")) {
                        _ml_known = array_length(_new_asset.meta.char_grid);
                    } else if (variable_struct_exists(_new_asset.meta, "colour_grid")) {
                        _ml_known = array_length(_new_asset.meta.colour_grid);
                    }
                    if (_ml_known > 0 && _new_asset.meta.map_h > 0 &&
                        (_ml_known mod _new_asset.meta.map_h) == 0) {
                        _new_asset.meta.grid_w = _ml_known div _new_asset.meta.map_h;
                        _new_asset.meta.grid_h = _new_asset.meta.map_h;
                    } else {
                        _new_asset.meta.grid_w = _new_asset.meta.map_w;
                        _new_asset.meta.grid_h = _new_asset.meta.map_h;
                    }
                }
                var _ml_phys = _new_asset.meta.grid_w * _new_asset.meta.grid_h;
                // Restore override_grid at physical stride. If the saved array is the
                // wrong size, reallocate but preserve any surviving cells rather than
                // zero-wiping the whole plane (which loses all per-tile HR/MC flags).
                if (!variable_struct_exists(_new_asset.meta, "override_grid")) {
                    _new_asset.meta.override_grid = array_create(_ml_phys, 0);
                } else if (array_length(_new_asset.meta.override_grid) != _ml_phys) {
                    var _ml_old = _new_asset.meta.override_grid;
                    var _ml_old_len = array_length(_ml_old);
                    var _ml_new = array_create(_ml_phys, 0);
                    var _ml_copy = min(_ml_old_len, _ml_phys);
                    for (var _ml_i = 0; _ml_i < _ml_copy; _ml_i++) {
                        _ml_new[_ml_i] = _ml_old[_ml_i];
                    }
                    _new_asset.meta.override_grid = _ml_new;
                }
            }
				if (_ad.type == "META_TILESET") {
	            scr_asset_meta_tileset_create(_new_asset);
	            var _tsm = variable_struct_exists(_ad, "meta") ? _ad.meta : {};
	            _new_asset.meta.stamp_w               = variable_struct_exists(_tsm, "stamp_w")      ? _tsm.stamp_w      : 2;
	            _new_asset.meta.stamp_h               = variable_struct_exists(_tsm, "stamp_h")      ? _tsm.stamp_h      : 2;
	            _new_asset.meta.stamp_count           = variable_struct_exists(_tsm, "stamp_count")  ? _tsm.stamp_count  : 0;
	            _new_asset.meta.chr_asset             = variable_struct_exists(_tsm, "chr_asset")    ? _tsm.chr_asset    : "";
	            _new_asset.meta.stamp_data            = variable_struct_exists(_tsm, "stamp_data")   ? _tsm.stamp_data   : [];
	            // Per-stamp HR(0)/MC(1) flag. Backfill to stamp_count for pre-field saves.
	            if (variable_struct_exists(_tsm, "stamp_mc")) {
	                _new_asset.meta.stamp_mc = _tsm.stamp_mc;
	            } else {
	                _new_asset.meta.stamp_mc = array_create(_new_asset.meta.stamp_count, 0);
	            }
	            while (array_length(_new_asset.meta.stamp_mc) < _new_asset.meta.stamp_count) {
	                array_push(_new_asset.meta.stamp_mc, 0);
	            }
	            // Per-char mode LUT (0 = HR, 1 = MC). Old files lack it: default all-HR, 256 long.
	            if (variable_struct_exists(_tsm, "char_lut")) {
	                _new_asset.meta.char_lut = _tsm.char_lut;
	            } else {
	                _new_asset.meta.char_lut = array_create(256, 0);
	            }
	            while (array_length(_new_asset.meta.char_lut) < 256) {
	                array_push(_new_asset.meta.char_lut, 0);
	            }
	            _new_asset.meta.char_lut_len = variable_struct_exists(_tsm, "char_lut_len") ? _tsm.char_lut_len : 0;
	            // Per-stamp colour override (0-15 = force, $80 = none). Backfill to stamp_count with $80.
	            if (variable_struct_exists(_tsm, "stamp_override")) {
	                _new_asset.meta.stamp_override = _tsm.stamp_override;
	            } else {
	                _new_asset.meta.stamp_override = array_create(_new_asset.meta.stamp_count, 0x80);
	            }
	            while (array_length(_new_asset.meta.stamp_override) < _new_asset.meta.stamp_count) {
	                array_push(_new_asset.meta.stamp_override, 0x80);
	            }
	            _new_asset.meta.zoom                  = variable_struct_exists(_tsm, "zoom")         ? _tsm.zoom         : 4;
				_new_asset.meta.test_zoom             = variable_struct_exists(_tsm, "test_zoom")    ? _tsm.test_zoom    : 1;
	            _new_asset.meta.map_mc_col1           = variable_struct_exists(_tsm, "map_mc_col1")  ? _tsm.map_mc_col1  : 1;
	            _new_asset.meta.map_mc_col2           = variable_struct_exists(_tsm, "map_mc_col2")  ? _tsm.map_mc_col2  : 2;
	            _new_asset.meta.stamp_list_scroll     = 0;
	            _new_asset.meta.char_strip_offset     = 0;
	            _new_asset.meta.stamp_clip            = [];
	            _new_asset.meta.stamp_clip_valid      = false;
	            _new_asset.meta.active_stamp_grid_col  = array_create(_new_asset.meta.stamp_w * _new_asset.meta.stamp_h, 1);
	            // Select stamp 0 (if any) and pre-fill the edit grid from its
	            // stamp_data, so the canvas shows the correct metatile on first
	            // open rather than a blank grid until the user clicks a slot.
	            var _mts_cells = _new_asset.meta.stamp_w * _new_asset.meta.stamp_h;
	            _new_asset.meta.active_stamp_grid_char = array_create(_mts_cells, 0);
	            if (_new_asset.meta.stamp_count > 0)
	            {
	                _new_asset.meta.edit_stamp = 0;
	                for (var _mts_i = 0; _mts_i < _mts_cells; _mts_i++)
	                {
	                    if (_mts_i < array_length(_new_asset.meta.stamp_data))
	                    {
	                        _new_asset.meta.active_stamp_grid_char[_mts_i] = _new_asset.meta.stamp_data[_mts_i];
	                    }
	                }
	            }
	            else
	            {
	                _new_asset.meta.edit_stamp = -1;
	            }
	            // Restore map placement data (flat int arrays, -1 = empty)
	            _new_asset.meta.maps       = variable_struct_exists(_tsm, "maps")       ? _tsm.maps       : [];
	            _new_asset.meta.map_count  = variable_struct_exists(_tsm, "map_count")  ? _tsm.map_count  : array_length(_new_asset.meta.maps);
	            _new_asset.meta.active_map = variable_struct_exists(_tsm, "active_map") ? _tsm.active_map : -1;
	            _new_asset.meta.test_grid  = variable_struct_exists(_tsm, "test_grid")  ? _tsm.test_grid  : [];
	            _new_asset.meta.map_bytes  = array_create(_new_asset.meta.map_count, 0);
	            _new_asset.meta.map_tab_scroll = 0;
	            // Restore per-map dims + the size guard key so the viewer's
	            // "size changed -> clear maps" guard does NOT fire on first open
	            // and wipe the just-loaded maps. If the key is absent (old saves),
	            // rebuild it from the restored stamp size so it still matches.
	            if (variable_struct_exists(_tsm, "map_w")) {
	                _new_asset.meta.map_w = _tsm.map_w;
	            } else {
	                _new_asset.meta.map_w = [];
	            }
	            if (variable_struct_exists(_tsm, "map_h")) {
	                _new_asset.meta.map_h = _tsm.map_h;
	            } else {
	                _new_asset.meta.map_h = [];
	            }
	            if (variable_struct_exists(_tsm, "map_size_key")) {
	                _new_asset.meta.map_size_key = _tsm.map_size_key;
	            } else {
	                _new_asset.meta.map_size_key = string(_new_asset.meta.stamp_w) + "x" + string(_new_asset.meta.stamp_h);
	            }

	            // Backfill per-map dim arrays to map_count so the viewer never
	            // indexes past a short or empty array (old saves store no map_w/map_h).
	            while (array_length(_new_asset.meta.map_w) < _new_asset.meta.map_count) {
	                array_push(_new_asset.meta.map_w, 40);
	            }
	            while (array_length(_new_asset.meta.map_h) < _new_asset.meta.map_count) {
	                array_push(_new_asset.meta.map_h, 25);
	            }

	            // Clamp active_map into the valid range for the restored map set.
	            if (_new_asset.meta.map_count <= 0) {
	                _new_asset.meta.active_map = -1;
	            } else if (_new_asset.meta.active_map >= _new_asset.meta.map_count) {
	                _new_asset.meta.active_map = _new_asset.meta.map_count - 1;
	            }
	        }
			
	        if (_ad.type == "BITMAP_BUILDER") {
	            // Seed every editor field, then overlay the persisted ones.
	            // Transient state (prev_surf, phase, anchors) is deliberately NOT
	            // serialised — it rebuilds on first draw.
	            scr_bitmap_builder_create(_new_asset);
	            var _bbm = variable_struct_exists(_ad, "meta") ? _ad.meta : {};
	            _new_asset.meta.src_asset  = variable_struct_exists(_bbm, "src_asset")  ? _bbm.src_asset  : "";
	            _new_asset.meta.dst_asset  = variable_struct_exists(_bbm, "dst_asset")  ? _bbm.dst_asset  : "";
	            _new_asset.meta.blend      = variable_struct_exists(_bbm, "blend")      ? _bbm.blend      : 0;
	            _new_asset.meta.records    = variable_struct_exists(_bbm, "records")    ? _bbm.records    : [];
	            _new_asset.meta.bbd_name   = variable_struct_exists(_bbm, "bbd_name")   ? _bbm.bbd_name   : "";
	            _new_asset.meta.prev_entry = variable_struct_exists(_bbm, "prev_entry") ? _bbm.prev_entry : 0;
	            _new_asset.meta.bbt_name   = variable_struct_exists(_bbm, "bbt_name")   ? _bbm.bbt_name   : "";
	            _new_asset.meta.tag_type   = variable_struct_exists(_bbm, "tag_type")   ? _bbm.tag_type   : 1;
	            // json_stringify round-trips struct fields as-is, but a hand-edited
	            // or partial save could leave a record short a field. Harden every
	            // entry so the editor and generator can read it without guards.
	            var _bb_recs = _new_asset.meta.records;
	            for (var _bri = 0; _bri < array_length(_bb_recs); _bri++) {
	                var _br = _bb_recs[_bri];
	                if (!is_struct(_br)) {
	                    continue;
	                }
	                if (!variable_struct_exists(_br, "kind")) _br.kind = "REC";
	                if (_br.kind == "END") {
	                    continue;
	                }
	                if (!variable_struct_exists(_br, "sx")) _br.sx = 0;
	                if (!variable_struct_exists(_br, "sy")) _br.sy = 0;
	                if (!variable_struct_exists(_br, "dx")) _br.dx = 0;
	                if (!variable_struct_exists(_br, "dy")) _br.dy = 0;
	                if (!variable_struct_exists(_br, "w"))  _br.w  = 1;
	                if (!variable_struct_exists(_br, "h"))  _br.h  = 1;
	            }
	            _new_asset.meta.prev_dirty = true;
	        }

	        if (_ad.type == "META_MAP") {
	            scr_asset_meta_map_create(_new_asset);
	            var _mmm = variable_struct_exists(_ad, "meta") ? _ad.meta : {};
	            _new_asset.meta.map_w        = variable_struct_exists(_mmm, "map_w")        ? _mmm.map_w        : 40;
	            _new_asset.meta.map_h        = variable_struct_exists(_mmm, "map_h")        ? _mmm.map_h        : 25;
	            _new_asset.meta.tileset_name = variable_struct_exists(_mmm, "tileset_name") ? _mmm.tileset_name : "";
	            _new_asset.meta.index_data   = variable_struct_exists(_mmm, "index_data")   ? _mmm.index_data   : [];
	        }
	        if (_ad.type == "VECTOR_BITMAP") {
	            var _vbm = variable_struct_exists(_ad, "meta") ? _ad.meta : {};
	            _new_asset.meta.mode        = variable_struct_exists(_vbm, "mode")        ? _vbm.mode        : 1;
	            _new_asset.meta.bg          = variable_struct_exists(_vbm, "bg")          ? _vbm.bg          : 0;
	            _new_asset.meta.col1        = variable_struct_exists(_vbm, "col1")        ? _vbm.col1        : 1;
	            _new_asset.meta.col2        = variable_struct_exists(_vbm, "col2")        ? _vbm.col2        : 2;
	            _new_asset.meta.col3        = variable_struct_exists(_vbm, "col3")        ? _vbm.col3        : 3;
	            _new_asset.meta.fill_stack  = variable_struct_exists(_vbm, "fill_stack")  ? _vbm.fill_stack  : 0xC000;
	            _new_asset.meta.stream_addr = variable_struct_exists(_vbm, "stream_addr") ? _vbm.stream_addr : 0xC800;
	            // Migrate legacy $A000 (under BASIC ROM, unreadable) to safe RAM.
	            if (_new_asset.meta.stream_addr == 0xA000) {
	                _new_asset.meta.stream_addr = 0xC800;
	            }
	            _new_asset.meta.commands    = variable_struct_exists(_vbm, "commands")    ? _vbm.commands    : [];
	            // Carry saved multi-page data across so the migration guard below
	            // sees it and does NOT collapse pages 1..N into a single page 0.
	            if (variable_struct_exists(_vbm, "pages"))       _new_asset.meta.pages       = _vbm.pages;
	            if (variable_struct_exists(_vbm, "active_page")) _new_asset.meta.active_page = _vbm.active_page;
	            _new_asset.meta.active_col  = variable_struct_exists(_vbm, "active_col")  ? _vbm.active_col  : 1;
	            _new_asset.meta.active_pat  = variable_struct_exists(_vbm, "active_pat")  ? _vbm.active_pat  : 0;
	            _new_asset.meta.tool        = variable_struct_exists(_vbm, "tool")        ? _vbm.tool        : "LINE";
	            _new_asset.meta.zoom        = variable_struct_exists(_vbm, "zoom")        ? _vbm.zoom        : 2;
	            // editor preview state — never serialised, rebuilt lazily
	            _new_asset.meta.preview_surf    = -1;
	            _new_asset.meta.draw_x1         = -1;
	            _new_asset.meta.draw_y1         = -1;
	            _new_asset.meta.vbmp_undo_stack = [];
	            _new_asset.meta.vbmp_redo_stack = [];
	            // ── MULTI-PAGE MIGRATION ──
	            // Newer saves serialise pages[]. Older saves have only the
	            // top-level commands/bg/col1/col2/col3 — wrap those as page 0
	            // so every asset has a valid pages[] going forward.
	            if (!variable_struct_exists(_new_asset.meta, "pages") || !is_array(_new_asset.meta.pages) || array_length(_new_asset.meta.pages) == 0) {
	                var _p0_cmds = variable_struct_exists(_new_asset.meta, "commands") ? _new_asset.meta.commands : [];
	                var _p0_bg   = variable_struct_exists(_new_asset.meta, "bg")   ? _new_asset.meta.bg   : 0;
	                var _p0_c1   = variable_struct_exists(_new_asset.meta, "col1") ? _new_asset.meta.col1 : 1;
	                var _p0_c2   = variable_struct_exists(_new_asset.meta, "col2") ? _new_asset.meta.col2 : 2;
	                var _p0_c3   = variable_struct_exists(_new_asset.meta, "col3") ? _new_asset.meta.col3 : 3;
	                _new_asset.meta.pages = [ { commands: _p0_cmds, bg: _p0_bg, col1: _p0_c1, col2: _p0_c2, col3: _p0_c3 } ];
	            }
	            if (!variable_struct_exists(_new_asset.meta, "active_page")) _new_asset.meta.active_page = 0;
	            // KLA-compat fields (editor-only, rebuilt fresh — never serialised)
	            _new_asset.meta.bg_mask       = array_create(64000, 0);
	            _new_asset.meta.dither_mode   = "NONE";
	            _new_asset.meta.dither_invert = false;
	            _new_asset.meta.brush_size    = 0;
	        }
	        if (_ad.type == "MUSIC_MAKER") {
	            scr_sound_editor_create(_new_asset);
	            var _sem = variable_struct_exists(_ad, "meta") ? _ad.meta : {};
	            if (variable_struct_exists(_sem, "instruments"))      _new_asset.meta.instruments      = _sem.instruments;
	            _new_asset.meta.sel_instr        = variable_struct_exists(_sem, "sel_instr")        ? _sem.sel_instr        : -1;
	            if (variable_struct_exists(_sem, "patterns"))         _new_asset.meta.patterns         = _sem.patterns;
	            _new_asset.meta.bank_sel_pattern = variable_struct_exists(_sem, "bank_sel_pattern") ? _sem.bank_sel_pattern : 0;
	            // JSON round-trips numerics as strings on some paths, so real()
	            // before it reaches the clamp in the editor.
	            _new_asset.meta.play_speed       = variable_struct_exists(_sem, "play_speed")       ? real(_sem.play_speed) : 6;
	            // songs[] restores first; the editor's migration guard only fires
	            // when it's absent, so a pre-songs[] file still folds its bare
	            // song_order into songs[0] on first open.
	            if (variable_struct_exists(_sem, "songs") && is_array(_sem.songs) && array_length(_sem.songs) > 0) {
	                _new_asset.meta.songs = _sem.songs;
	            }
	            _new_asset.meta.sel_song         = variable_struct_exists(_sem, "sel_song")         ? _sem.sel_song         : 0;
	            if (variable_struct_exists(_sem, "song_order"))       _new_asset.meta.song_order       = _sem.song_order;
	            _new_asset.meta.sel_order_row    = variable_struct_exists(_sem, "sel_order_row")    ? _sem.sel_order_row    : 0;
	            _new_asset.meta.song_loop        = variable_struct_exists(_sem, "song_loop")        ? _sem.song_loop        : true;
	            _new_asset.meta.song_loop_row    = variable_struct_exists(_sem, "song_loop_row")    ? _sem.song_loop_row    : 0;
	            _new_asset.meta.sel_voice        = variable_struct_exists(_sem, "sel_voice")        ? _sem.sel_voice        : 0;
	            _new_asset.meta.sel_step         = variable_struct_exists(_sem, "sel_step")         ? _sem.sel_step         : 0;
	            _new_asset.meta.cur_octave       = variable_struct_exists(_sem, "cur_octave")       ? _sem.cur_octave       : 4;
	            _new_asset.meta.view_mode        = variable_struct_exists(_sem, "view_mode")        ? _sem.view_mode        : "VERTICAL";
	            _new_asset.meta.step_zoom        = variable_struct_exists(_sem, "step_zoom")        ? _sem.step_zoom        : 1;
	            _new_asset.meta.list_scroll      = variable_struct_exists(_sem, "list_scroll")      ? _sem.list_scroll      : 0;
	        }
        }
    }

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
        var _data_pc = -1, _data_sz = 0;
        for (var _pi = 0; _pi < array_length(_parsed); _pi++) {
            var _pt = string_lower(_parsed[_pi][0]);
            if (_pt == "pc") {
                if (_data_pc >= 0 && _data_sz > 0)
                    array_push(code_seg_cache, { addr: _data_pc, size: _data_sz });
                _data_pc = _parsed[_pi][1];
                _data_sz = 0;
            } else if (_pt == "byte") {
                _data_sz += array_length(_parsed[_pi]) - 1;
            }
        }
        if (_data_pc >= 0 && _data_sz > 0)
            array_push(code_seg_cache, { addr: _data_pc, size: _data_sz });
        code_cache_dirty = false;
    }

    with (obj_c64_node) {
        if (node_type != "NAMED_LOC") continue;
        var _name = string(instructions[0][1]);
        if (_name == "" || _name == "< NO NAME >") continue;
        if (scr_nloc_find_meta(_name) != undefined) continue;
        var _is_hw = (string_pos("HW_", _name) == 1);
        if (!_is_hw) {
            var _enc  = (array_length(instructions[0]) > 2) ? string(instructions[0][2]) : "byte";
            var _size = (_enc == "word" || _enc == "bcd2") ? 2 : ((_enc == "bcd" || _enc == "bcd3") ? 3 : 1);
            // name: preserved display case (for UI). Map key: canonical uppercase,
            // so this matches whatever case any SET/GET/INC/DEC_VAR/IF node stored.
            var _meta = {
                name: _name, type: "UV", addr: pc_address,
                size: _size, encoding: _enc, chip: ""
            };
            if (!variable_struct_exists(_meta, "encoding")) { _meta.encoding = "byte"; }
	array_push(global.named_loc_meta, _meta);
	global.named_loc_meta_dirty = true;
            ds_map_replace(global.named_loc_map, string_upper(_name), -1);
        }
    }

    with (obj_c64_node) { is_dragging = false; }

    global.current_filename = path;
    global.autosave_dirty   = false;
    global.manual_saved     = true;
    window_set_caption(game_project_name + " - " + global.current_filename);

    global.addresses_dirty = true;
    scr_c64_do_update_addresses();

    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _asset = ds_list_find_value(_am.asset_list, _ai);
            if (_asset.type == "SPRITE_SET") scr_asset_spr_cache_sprites(_asset);
        }
    }

global.kernal_unlocked = variable_struct_exists(load_data, "kernal_unlocked") ? load_data.kernal_unlocked : false;
    global.basic_unlocked  = variable_struct_exists(load_data, "basic_unlocked")  ? load_data.basic_unlocked  : false;

    // Restore the stable-UID allocator: take the higher of the persisted value
    // and one past every restored node's UID, so future allocations never collide.
    var _restored_next_uid = variable_struct_exists(load_data, "next_stable_uid")
                           ? load_data.next_stable_uid
                           : 100000;
    with (obj_c64_node) {
        if (variable_instance_exists(id, "stable_uid") && stable_uid >= _restored_next_uid) {
            _restored_next_uid = stable_uid + 1;
        }
    }
    global.next_stable_uid = _restored_next_uid;

    // Restore the ignored-conflicts suppression list, then prune entries whose
    // referenced owner nodes no longer exist (range-only entries are kept).
    var _restored_ignores = variable_struct_exists(load_data, "ignored_conflicts")
                          ? load_data.ignored_conflicts
                          : [];
    var _pruned_ignores = [];
    for (var _ii = 0; _ii < array_length(_restored_ignores); _ii++) {
        var _ie = _restored_ignores[_ii];
        // Defensive: ensure all four expected fields exist
        if (!variable_struct_exists(_ie, "range_start"))  continue;
        if (!variable_struct_exists(_ie, "range_end"))    continue;
        if (!variable_struct_exists(_ie, "owner_a_uid")) _ie.owner_a_uid = -1;
        if (!variable_struct_exists(_ie, "owner_b_uid")) _ie.owner_b_uid = -1;

        // Verify at least one referenced owner still exists, or fall back to
        // range-only matching (keep entries even if owners are gone).
        array_push(_pruned_ignores, _ie);
    }
    global.ignored_conflicts = _pruned_ignores;
    code_editor_font_index = variable_struct_exists(load_data, "code_editor_font_index")
        ? clamp(load_data.code_editor_font_index, 0, array_length(code_editor_fonts) - 1)
        : 1;
    obj_workspace_manager.map_global_mixed = variable_struct_exists(load_data, "map_global_mixed")
        ? load_data.map_global_mixed : 0;
    obj_asset_manager.asset_sort_mode = variable_struct_exists(load_data, "asset_sort_mode")
        ? load_data.asset_sort_mode : "ADDR";
    global.map_tile_bank     = variable_struct_exists(load_data, "map_tile_bank")     ? load_data.map_tile_bank     : [];
    global.map_tile_bank_sel = variable_struct_exists(load_data, "map_tile_bank_sel") ? load_data.map_tile_bank_sel : -1;
    if (!global.kernal_unlocked || !global.basic_unlocked) {
        with (obj_c64_node) {
            if (node_title == "KERNAL RAM UNLOCK") global.kernal_unlocked = true;
            if (node_title == "BASIC RAM UNLOCK")  global.basic_unlocked  = true;
        }
    }

    var _undo_dir      = working_directory + "temp/undo/";
    var _manifest_path = _undo_dir + "manifest.json";
    if (file_exists(_manifest_path)) file_delete(_manifest_path);
    scr_undo_snapshot();
    
    // Reset scanline effect to prevent math breaks from sudden camera shifts
    if (instance_exists(obj_workspace_manager)) {
        obj_workspace_manager.scan_active = false;
        obj_workspace_manager.scan_y = 0;
    }
}
