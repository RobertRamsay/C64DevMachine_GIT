function scr_save_workspace_as_path(_path) {

var path = _path;
if (path == "") return;

global.workspace_path = path;

    // ================================================================
    // 2. GATHER AND SORT NODES
    // ================================================================
    var node_data = [];
    var p_list    = ds_priority_create();
    with (obj_c64_node) {
        var _sort_key = (node_type == "ORG") ? -99999 + y : y;
        ds_priority_add(p_list, id, _sort_key);
    }
    while (!ds_priority_empty(p_list)) {
        var inst = ds_priority_delete_min(p_list);
        var _hex_data    = "";
        var _kla_src_buf = noone;
        if (variable_instance_exists(inst, "kla_buffer") && buffer_exists(inst.kla_buffer)) {
            _kla_src_buf = inst.kla_buffer;
        } else if (variable_instance_exists(inst, "sprite_buffer") && buffer_exists(inst.sprite_buffer)) {
            _kla_src_buf = inst.sprite_buffer;
        }
        if (_kla_src_buf != noone) {
            _hex_data = scr_blob_encode(_kla_src_buf);
        }
        var _op_x = -1;
        var _op_y = -1;
        if (variable_instance_exists(inst, "org_parent") &&
            inst.org_parent != noone &&
            instance_exists(inst.org_parent)) {
            _op_x = inst.org_parent.x;
            _op_y = inst.org_parent.y;
        }
		var _save_code = variable_clone(inst.instructions);
		        if (inst.node_type == "NAMED_LOC" && array_length(_save_code) > 0) {
		            var _nlm = scr_nloc_find_meta(string(_save_code[0][1]));
		            if (_nlm != undefined) {
		                var _nlm_enc  = variable_struct_exists(_nlm, "encoding") ? _nlm.encoding : "byte";
		                var _nlm_size = variable_struct_exists(_nlm, "size")     ? _nlm.size     : 1;
		                while (array_length(_save_code[0]) < 4) array_push(_save_code[0], "");
		                _save_code[0][2] = _nlm_enc;
		                _save_code[0][3] = _nlm_size;
		            }
		        }
        array_push(node_data, {
            title:          inst.node_title,
            type:           inst.node_type,
            x:              inst.x,
            y:              inst.y,
            height:         inst.height,
            connected:      inst.is_connected,
            pc_address:     inst.pc_address,
            end_address:    variable_instance_exists(inst, "end_address") ? inst.end_address : inst.pc_address,
            org_parent_x:   _op_x,
            org_parent_y:   _op_y,
            has_org_parent: (_op_x != -1),
			proxy:          variable_instance_exists(inst, "proxy") ? inst.proxy : false,
            helper_text:    variable_instance_exists(inst, "helper_text") ? inst.helper_text : "",
			x_indent:       variable_instance_exists(inst, "x_indent") ? inst.x_indent : 0,
            anim_alias:     variable_instance_exists(inst, "anim_alias") ? inst.anim_alias : "",
            scroll_alias:   variable_instance_exists(inst, "scroll_alias") ? inst.scroll_alias : "",
			code_descriptor: variable_instance_exists(inst, "code_descriptor") ? inst.code_descriptor : "Code Block",
			show_only_used:  variable_instance_exists(inst, "show_only_used")  ? inst.show_only_used  : false,
            org_uid:         variable_instance_exists(inst, "org_uid")         ? inst.org_uid         : -1,
            wire_out_target: variable_instance_exists(inst, "wire_out_target") ? inst.wire_out_target : -1,
            wire_in_source:  variable_instance_exists(inst, "wire_in_source")  ? inst.wire_in_source  : -1,
            stable_uid:      variable_instance_exists(inst, "stable_uid")      ? inst.stable_uid      : -1,
			custom_title:    variable_instance_exists(inst, "custom_title")    ? inst.custom_title    : "",
			code:           _save_code,
            binary_blob:    _hex_data
        });
    }
    ds_priority_destroy(p_list);

    // ================================================================
    // 3. GATHER MAPPING BOXES
    // ================================================================
    var box_data = [];
    with (obj_mapping_box) {
        array_push(box_data, {
            x:           x,
            y:           y,
            box_w:       box_w,
            box_h:       box_h,
            box_name:    box_name,
            box_col_idx: box_col_idx
        });
    }
	
	// ================================================================
// 3B. GATHER ASSET MANAGER DATA
// ================================================================
var asset_data = [];
if (instance_exists(obj_asset_manager)) {
    var _am = obj_asset_manager;
    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
        var _a = ds_list_find_value(_am.asset_list, _ai);
        var _entry = {
            name:    _a.name,
            type:    _a.type,
            address: _a.address,
            file:    _a.file
        };
        // Serialize buffer as base64 blob (HYBRID)
        var _hex = "";
        if (buffer_exists(_a.buffer)) {
            _hex = scr_blob_encode(_a.buffer);
        }
        _entry.blob = _hex;
        _entry.load_later    = variable_struct_exists(_a, "load_later")    ? _a.load_later    : false;
        _entry.d64_filename  = variable_struct_exists(_a, "d64_filename")  ? _a.d64_filename  : "";
        _entry.reu_filename  = variable_struct_exists(_a, "reu_filename")  ? _a.reu_filename  : "";
        _entry.reu_size      = variable_struct_exists(_a, "reu_size")      ? _a.reu_size      : 0;
        _entry.reu_used      = variable_struct_exists(_a, "reu_used")      ? _a.reu_used      : 0;
        _entry.linked_assets = variable_struct_exists(_a, "linked_assets") ? _a.linked_assets : [];
		if (variable_struct_exists(_a.meta, "source_file")) _entry.source_file = _a.meta.source_file;
        // Serialize meta struct
        var _meta_out = {};
        if (variable_struct_exists(_a.meta, "sprite_mcs"))   _meta_out.sprite_mcs   = _a.meta.sprite_mcs;
        if (variable_struct_exists(_a.meta, "sprite_ucs"))   _meta_out.sprite_ucs   = _a.meta.sprite_ucs;
        if (variable_struct_exists(_a.meta, "mc1_col"))      _meta_out.mc1_col      = _a.meta.mc1_col;
        if (variable_struct_exists(_a.meta, "mc2_col"))      _meta_out.mc2_col      = _a.meta.mc2_col;
        if (variable_struct_exists(_a.meta, "used_count"))   _meta_out.used_count   = _a.meta.used_count;
        if (variable_struct_exists(_a.meta, "bg_col"))       _meta_out.bg_col       = _a.meta.bg_col;
	        // Persist HiRes/MC mode — without this a HiRes bitmap round-trips
	        // through save/load as if it were MC, and build_preview's size check
	        // (9002 vs 10003 bytes) silently fails, leaving the asset looking empty.
	        if (variable_struct_exists(_a.meta, "bmp_mode"))     _meta_out.bmp_mode     = _a.meta.bmp_mode;
        // GRADIENT tool CUSTOM stop run — the colours allocated to the 12
        // slots, the toggle state, and how many of the 12 are actually in
        // play. Pure tool state (like active_color), but explicitly asked to
        // survive save/load rather than reset every session.
        if (variable_struct_exists(_a.meta, "gradient_custom_active")) _meta_out.gradient_custom_active = _a.meta.gradient_custom_active;
        if (variable_struct_exists(_a.meta, "gradient_custom_cols"))   _meta_out.gradient_custom_cols   = _a.meta.gradient_custom_cols;
        if (variable_struct_exists(_a.meta, "gradient_custom_count"))  _meta_out.gradient_custom_count  = _a.meta.gradient_custom_count;
        // TONE-SORTED flag — see scr_c64_tone_group. The bytes on disk are
        // already tone-sorted; losing the flag reverts them on the next save.
        if (variable_struct_exists(_a.meta, "tone_sorted"))  _meta_out.tone_sorted  = _a.meta.tone_sorted;
        if (_a.type == "BITMAP" && variable_struct_exists(_a.meta, "coll_types") && is_array(_a.meta.coll_types)) {
            var _ct_any = false;
            for (var _cti = 0; _cti < array_length(_a.meta.coll_types); _cti++) {
                if (_a.meta.coll_types[_cti] != 0) { _ct_any = true; break; }
            }
            if (_ct_any) _meta_out.coll_types = _a.meta.coll_types;
        }
		if (variable_struct_exists(_a.meta, "sprite_mcs"))   _meta_out.sprite_mcs   = _a.meta.sprite_mcs;
		if (variable_struct_exists(_a.meta, "sprite_json"))  _meta_out.sprite_json  = _a.meta.sprite_json; 
		if (variable_struct_exists(_a.meta, "compositor"))   _meta_out.compositor   = _a.meta.compositor;
		if (variable_struct_exists(_a.meta, "anim"))         _meta_out.anim         = _a.meta.anim;
		
		// SID meta
        if (variable_struct_exists(_a.meta, "sid_init_addr"))  _meta_out.sid_init_addr  = _a.meta.sid_init_addr;
        if (variable_struct_exists(_a.meta, "sid_play_addr"))  _meta_out.sid_play_addr  = _a.meta.sid_play_addr;
        if (variable_struct_exists(_a.meta, "sid_data_start")) _meta_out.sid_data_start = _a.meta.sid_data_start;
		
		// SFX_DATA meta
        if (_a.type == "SFX_DATA") {
            if (variable_struct_exists(_a.meta, "song_name"))   _meta_out.song_name   = _a.meta.song_name;
            if (variable_struct_exists(_a.meta, "sfx_count"))   _meta_out.sfx_count   = _a.meta.sfx_count;
            if (variable_struct_exists(_a.meta, "instruments")) _meta_out.instruments = _a.meta.instruments;
            if (variable_struct_exists(_a.meta, "wavetable"))   _meta_out.wavetable   = _a.meta.wavetable;
        }
		
// CHAR_SET meta
        if (variable_struct_exists(_a.meta, "format"))        _meta_out.format        = _a.meta.format;
        if (variable_struct_exists(_a.meta, "char_count"))    _meta_out.char_count    = _a.meta.char_count;
        if (variable_struct_exists(_a.meta, "total_size"))    _meta_out.total_size    = _a.meta.total_size;
        if (variable_struct_exists(_a.meta, "mc_mode"))       _meta_out.mc_mode       = _a.meta.mc_mode;
        if (variable_struct_exists(_a.meta, "mc_fg"))         _meta_out.mc_fg         = _a.meta.mc_fg;
        if (variable_struct_exists(_a.meta, "mc_bg"))         _meta_out.mc_bg         = _a.meta.mc_bg;
        if (variable_struct_exists(_a.meta, "mc_col1"))       _meta_out.mc_col1       = _a.meta.mc_col1;
        if (variable_struct_exists(_a.meta, "mc_col2"))       _meta_out.mc_col2       = _a.meta.mc_col2;
	    if (variable_struct_exists(_a.meta, "ecm_bg1"))       _meta_out.ecm_bg1       = _a.meta.ecm_bg1;
	    if (variable_struct_exists(_a.meta, "ecm_bg2"))       _meta_out.ecm_bg2       = _a.meta.ecm_bg2;
	    if (variable_struct_exists(_a.meta, "ecm_bg3"))       _meta_out.ecm_bg3       = _a.meta.ecm_bg3;
	    if (variable_struct_exists(_a.meta, "tile_types"))    _meta_out.tile_types    = _a.meta.tile_types;
        // MAP_DATA metaa
        if (variable_struct_exists(_a.meta, "map_w"))         _meta_out.map_w         = _a.meta.map_w;
        if (variable_struct_exists(_a.meta, "map_h"))         _meta_out.map_h         = _a.meta.map_h;
        if (variable_struct_exists(_a.meta, "grid_w"))        _meta_out.grid_w        = _a.meta.grid_w;
        if (variable_struct_exists(_a.meta, "grid_h"))        _meta_out.grid_h        = _a.meta.grid_h;
        if (variable_struct_exists(_a.meta, "char_grid"))     _meta_out.char_grid     = _a.meta.char_grid;
        if (variable_struct_exists(_a.meta, "colour_grid"))   _meta_out.colour_grid   = _a.meta.colour_grid;
        if (variable_struct_exists(_a.meta, "chr_asset"))     _meta_out.chr_asset     = _a.meta.chr_asset;
        if (variable_struct_exists(_a.meta, "scroll_x"))      _meta_out.scroll_x      = _a.meta.scroll_x;
        if (variable_struct_exists(_a.meta, "scroll_y"))      _meta_out.scroll_y      = _a.meta.scroll_y;
        if (variable_struct_exists(_a.meta, "zoom"))          _meta_out.zoom          = _a.meta.zoom;
        if (variable_struct_exists(_a.meta, "active_char"))   _meta_out.active_char   = _a.meta.active_char;
        if (variable_struct_exists(_a.meta, "active_colour")) _meta_out.active_colour = _a.meta.active_colour;
        if (variable_struct_exists(_a.meta, "tool"))          _meta_out.tool          = _a.meta.tool;
        if (variable_struct_exists(_a.meta, "text"))          _meta_out.text          = _a.meta.text;
        if (variable_struct_exists(_a.meta, "byte_string"))   _meta_out.byte_string   = _a.meta.byte_string;
        if (variable_struct_exists(_a.meta, "line_string"))   _meta_out.line_string   = _a.meta.line_string;
        if (variable_struct_exists(_a.meta, "lines"))         _meta_out.lines         = _a.meta.lines;
        if (variable_struct_exists(_a.meta, "active_type"))   _meta_out.active_type   = _a.meta.active_type;
        if (variable_struct_exists(_a.meta, "ref_enabled"))   _meta_out.ref_enabled   = _a.meta.ref_enabled;
        if (variable_struct_exists(_a.meta, "ref_asset_name")) _meta_out.ref_asset_name = _a.meta.ref_asset_name;
        if (variable_struct_exists(_a.meta, "ref_offset_x"))  _meta_out.ref_offset_x  = _a.meta.ref_offset_x;
        if (variable_struct_exists(_a.meta, "ref_offset_y"))  _meta_out.ref_offset_y  = _a.meta.ref_offset_y;
        if (variable_struct_exists(_a.meta, "is_save_file"))  _meta_out.is_save_file  = _a.meta.is_save_file;
        if (variable_struct_exists(_a.meta, "save_file_size")) _meta_out.save_file_size = _a.meta.save_file_size;
        if (variable_struct_exists(_a.meta, "paint_mc"))      _meta_out.paint_mc      = _a.meta.paint_mc;
        if (variable_struct_exists(_a.meta, "map_mixed"))     _meta_out.map_mixed     = _a.meta.map_mixed;
        if (variable_struct_exists(_a.meta, "override_grid")) _meta_out.override_grid = _a.meta.override_grid;
        if (variable_struct_exists(_a.meta, "map_mc_bg"))     _meta_out.map_mc_bg     = _a.meta.map_mc_bg;
        if (variable_struct_exists(_a.meta, "map_mc_col1"))   _meta_out.map_mc_col1   = _a.meta.map_mc_col1;
        if (variable_struct_exists(_a.meta, "map_mc_col2"))   _meta_out.map_mc_col2   = _a.meta.map_mc_col2;

        if (_a.type == "META_TILESET") {
            _meta_out.stamp_w     = _a.meta.stamp_w;
            _meta_out.stamp_h     = _a.meta.stamp_h;
            _meta_out.stamp_count = _a.meta.stamp_count;
            _meta_out.chr_asset   = _a.meta.chr_asset;
            _meta_out.stamp_data  = _a.meta.stamp_data;
            _meta_out.stamp_mc    = variable_struct_exists(_a.meta, "stamp_mc") ? _a.meta.stamp_mc : [];
            _meta_out.char_lut       = variable_struct_exists(_a.meta, "char_lut")       ? _a.meta.char_lut       : array_create(256, 0);
            _meta_out.char_lut_len   = variable_struct_exists(_a.meta, "char_lut_len")   ? _a.meta.char_lut_len   : 0;
            _meta_out.stamp_override = variable_struct_exists(_a.meta, "stamp_override") ? _a.meta.stamp_override : [];
            _meta_out.zoom        = _a.meta.zoom;
            _meta_out.test_zoom   = _a.meta.test_zoom;
            _meta_out.map_mc_bg   = _a.meta.map_mc_bg;
            _meta_out.map_mc_col1 = _a.meta.map_mc_col1;
            _meta_out.map_mc_col2 = _a.meta.map_mc_col2;
            // Map placement data (flat int arrays, -1 = empty)
            _meta_out.maps       = variable_struct_exists(_a.meta, "maps")       ? _a.meta.maps       : [];
            _meta_out.map_count  = variable_struct_exists(_a.meta, "map_count")  ? _a.meta.map_count  : 0;
            _meta_out.active_map = variable_struct_exists(_a.meta, "active_map") ? _a.meta.active_map : -1;
            _meta_out.test_grid  = variable_struct_exists(_a.meta, "test_grid")  ? _a.meta.test_grid  : [];
            // Per-map-size guard key. MUST persist, or the viewer's "size changed
            // -> clear all maps" guard fires on first open after load and wipes
            // the maps (they'd have data but no key).
            _meta_out.map_size_key = variable_struct_exists(_a.meta, "map_size_key") ? _a.meta.map_size_key : "";
            _meta_out.map_w        = variable_struct_exists(_a.meta, "map_w") ? _a.meta.map_w : [];
            _meta_out.map_h        = variable_struct_exists(_a.meta, "map_h") ? _a.meta.map_h : [];
        }
		
		
		 if (_a.type == "MUSIC_MAKER") {
            _meta_out.instruments      = variable_struct_exists(_a.meta, "instruments")      ? _a.meta.instruments      : [];
            _meta_out.sel_instr        = variable_struct_exists(_a.meta, "sel_instr")        ? _a.meta.sel_instr        : -1;
            _meta_out.patterns         = variable_struct_exists(_a.meta, "patterns")         ? _a.meta.patterns         : [];
            _meta_out.bank_sel_pattern = variable_struct_exists(_a.meta, "bank_sel_pattern") ? _a.meta.bank_sel_pattern : 0;
            _meta_out.play_speed       = variable_struct_exists(_a.meta, "play_speed")       ? _a.meta.play_speed       : 6;
            // songs[] is the source of truth. song_order/song_loop/song_loop_row
            // are legacy and written only so an older build can still open the
            // file; nothing in the current editor or emitter reads them.
            _meta_out.songs            = variable_struct_exists(_a.meta, "songs")            ? _a.meta.songs            : [];
            _meta_out.sel_song         = variable_struct_exists(_a.meta, "sel_song")         ? _a.meta.sel_song         : 0;
            _meta_out.song_order       = variable_struct_exists(_a.meta, "song_order")       ? _a.meta.song_order       : [];
            _meta_out.sel_order_row    = variable_struct_exists(_a.meta, "sel_order_row")    ? _a.meta.sel_order_row    : 0;
            _meta_out.song_loop        = variable_struct_exists(_a.meta, "song_loop")        ? _a.meta.song_loop        : true;
            _meta_out.song_loop_row    = variable_struct_exists(_a.meta, "song_loop_row")    ? _a.meta.song_loop_row    : 0;
            _meta_out.sel_voice        = variable_struct_exists(_a.meta, "sel_voice")        ? _a.meta.sel_voice        : 0;
            _meta_out.sel_step         = variable_struct_exists(_a.meta, "sel_step")         ? _a.meta.sel_step         : 0;
            _meta_out.cur_octave       = variable_struct_exists(_a.meta, "cur_octave")       ? _a.meta.cur_octave       : 4;
            _meta_out.view_mode        = variable_struct_exists(_a.meta, "view_mode")        ? _a.meta.view_mode        : "VERTICAL";
            _meta_out.step_zoom        = variable_struct_exists(_a.meta, "step_zoom")        ? _a.meta.step_zoom        : 1;
            _meta_out.list_scroll      = variable_struct_exists(_a.meta, "list_scroll")      ? _a.meta.list_scroll      : 0;
        }
		
		
        if (_a.type == "META_MAP") {
            _meta_out.map_w        = _a.meta.map_w;
            _meta_out.map_h        = _a.meta.map_h;
            _meta_out.tileset_name = _a.meta.tileset_name;
            _meta_out.index_data   = _a.meta.index_data;
        }
        if (_a.type == "BITMAP_BUILDER") {
            // The builder is the source of truth; the BBD BYTE_DATA it emits is
            // a derived artifact and is saved as a normal asset in its own right.
            _meta_out.src_asset  = variable_struct_exists(_a.meta, "src_asset")  ? _a.meta.src_asset  : "";
            _meta_out.dst_asset  = variable_struct_exists(_a.meta, "dst_asset")  ? _a.meta.dst_asset  : "";
            _meta_out.blend      = variable_struct_exists(_a.meta, "blend")      ? _a.meta.blend      : 0;
            _meta_out.records    = variable_struct_exists(_a.meta, "records")    ? _a.meta.records    : [];
            _meta_out.bbd_name   = variable_struct_exists(_a.meta, "bbd_name")   ? _a.meta.bbd_name   : "";
            _meta_out.prev_entry = variable_struct_exists(_a.meta, "prev_entry") ? _a.meta.prev_entry : 0;
            _meta_out.bbt_name   = variable_struct_exists(_a.meta, "bbt_name")   ? _a.meta.bbt_name   : "";
            _meta_out.tag_type   = variable_struct_exists(_a.meta, "tag_type")   ? _a.meta.tag_type   : 1;
        }
        if (_a.type == "VECTOR_BITMAP") {
            // Flush live editor fields into pages[active_page] before saving,
            // so the visible page is captured whether or not it was switched.
            scr_vbmp_page_store(_a);
            _meta_out.mode        = variable_struct_exists(_a.meta, "mode")        ? _a.meta.mode        : 1;
            _meta_out.bg          = variable_struct_exists(_a.meta, "bg")          ? _a.meta.bg          : 0;
            _meta_out.col1        = variable_struct_exists(_a.meta, "col1")        ? _a.meta.col1        : 1;
            _meta_out.col2        = variable_struct_exists(_a.meta, "col2")        ? _a.meta.col2        : 2;
            _meta_out.col3        = variable_struct_exists(_a.meta, "col3")        ? _a.meta.col3        : 3;
            _meta_out.fill_stack  = variable_struct_exists(_a.meta, "fill_stack")  ? _a.meta.fill_stack  : 0xC000;
            _meta_out.stream_addr = variable_struct_exists(_a.meta, "stream_addr") ? _a.meta.stream_addr : 0xC800; // legacy field; unused by compiler (stream = fill_stack + $0800)
            _meta_out.commands    = variable_struct_exists(_a.meta, "commands")    ? _a.meta.commands    : [];
	        _meta_out.pages       = variable_struct_exists(_a.meta, "pages")       ? _a.meta.pages       : [];
	        _meta_out.active_page = variable_struct_exists(_a.meta, "active_page") ? _a.meta.active_page : 0;
	        _meta_out.active_col  = variable_struct_exists(_a.meta, "active_col")  ? _a.meta.active_col  : 1;
            _meta_out.active_pat  = variable_struct_exists(_a.meta, "active_pat")  ? _a.meta.active_pat  : 0;
            _meta_out.tool        = variable_struct_exists(_a.meta, "tool")        ? _a.meta.tool        : "LINE";
            _meta_out.zoom        = variable_struct_exists(_a.meta, "zoom")        ? _a.meta.zoom        : 2;
        }

        _entry.meta = _meta_out;
        array_push(asset_data, _entry);
    }
}

    // ================================================================
    // 4. COMBINE AND PRETTY-PRINT
    // ================================================================
	var save_root = {
	        nodes:              node_data,
	        boxes:              box_data,
	        assets:             asset_data,
	        basic_unlocked:     global.basic_unlocked,
	        kernal_unlocked:    global.kernal_unlocked,
	        code_editor_font_index: code_editor_font_index,
	        map_global_mixed:   obj_workspace_manager.map_global_mixed,
	        map_tile_bank:      variable_global_exists("map_tile_bank") ? global.map_tile_bank : [],
	        map_tile_bank_sel:  variable_global_exists("map_tile_bank_sel") ? global.map_tile_bank_sel : -1,
	        next_stable_uid:    variable_global_exists("next_stable_uid")   ? global.next_stable_uid   : 100000,
	        ignored_conflicts:  variable_global_exists("ignored_conflicts") ? global.ignored_conflicts : [],
	        asset_sort_mode:    obj_asset_manager.asset_sort_mode
	    };
    var _raw = json_stringify(save_root);
    var f = file_text_open_write(path);
    file_text_write_string(f, _raw);
    file_text_close(f);

	global.current_filename = path;
    global.autosave_dirty   = false;
    global.manual_saved     = true;
    window_set_caption(game_project_name + " - " + global.current_filename);
}