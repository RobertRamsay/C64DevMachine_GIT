function scr_autosave() {

    var _dir = working_directory + "autosave/";
    if (!directory_exists(_dir)) directory_create(_dir);

    // Build timestamp: yymmddhhmmss
    var _dt  = date_current_datetime();
    var _ts  = string(date_get_year(_dt)  mod 100)
             + string_replace_all(string(date_get_month(_dt)),  " ", "0")
             + string_replace_all(string(date_get_day(_dt)),    " ", "0")
             + string_replace_all(string(date_get_hour(_dt)),   " ", "0")
             + string_replace_all(string(date_get_minute(_dt)), " ", "0")
             + string_replace_all(string(date_get_second(_dt)), " ", "0");
    // Zero-pad each component
    var _yy  = string_format(date_get_year(_dt)   mod 100, 2, 0); _yy  = string_replace_all(_yy,  " ", "0");
    var _mo  = string_format(date_get_month(_dt),           2, 0); _mo  = string_replace_all(_mo,  " ", "0");
    var _dd  = string_format(date_get_day(_dt),             2, 0); _dd  = string_replace_all(_dd,  " ", "0");
    var _hh  = string_format(date_get_hour(_dt),            2, 0); _hh  = string_replace_all(_hh,  " ", "0");
    var _mm  = string_format(date_get_minute(_dt),          2, 0); _mm  = string_replace_all(_mm,  " ", "0");
    var _ss  = string_format(date_get_second(_dt),          2, 0); _ss  = string_replace_all(_ss,  " ", "0");
    _ts = _yy + _mo + _dd + _hh + _mm + _ss;

var _base = "unsaved";
    if (global.workspace_path != "" && string_pos("autosave", global.workspace_path) == 0) {
        _base = filename_name(filename_change_ext(global.workspace_path, ""));
    }
    var _path = _dir + "autosave_" + _base + "_" + _ts + ".json";

    // --- Serialise (mirrors scr_save_workspace_as, no file dialog) ---
    var node_data = [];
    var p_list    = ds_priority_create();
    with (obj_c64_node) ds_priority_add(p_list, id, (node_type == "ORG") ? -99999 + y : y);
    while (!ds_priority_empty(p_list)) {
        var inst         = ds_priority_delete_min(p_list);
        var _hex_data    = "";
        var _src_buf     = noone;
        if (variable_instance_exists(inst, "kla_buffer")    && buffer_exists(inst.kla_buffer))    _src_buf = inst.kla_buffer;
        else if (variable_instance_exists(inst, "sprite_buffer") && buffer_exists(inst.sprite_buffer)) _src_buf = inst.sprite_buffer;
        if (_src_buf != noone) {
            _hex_data = scr_blob_encode(_src_buf);
        }
        var _op_x = -1; var _op_y = -1;
        if (variable_instance_exists(inst, "org_parent") && inst.org_parent != noone && instance_exists(inst.org_parent)) {
            _op_x = inst.org_parent.x; _op_y = inst.org_parent.y;
        }
        var _save_code = variable_clone(inst.instructions);
        if (inst.node_type == "NAMED_LOC" && array_length(_save_code) > 0) {
            var _nlm = scr_nloc_find_meta(string(_save_code[0][1]));
            if (_nlm != undefined) {
                var _nlm_enc = variable_struct_exists(_nlm, "encoding") ? _nlm.encoding : "byte";
                var _nlm_sz  = variable_struct_exists(_nlm, "size")     ? _nlm.size     : 1;
                while (array_length(_save_code[0]) < 4) array_push(_save_code[0], "");
                _save_code[0][2] = _nlm_enc; _save_code[0][3] = _nlm_sz;
            }
        }
        array_push(node_data, {
            title: inst.node_title, type: inst.node_type,
            x: inst.x, y: inst.y, height: inst.height,
            connected: inst.is_connected, pc_address: inst.pc_address,
            end_address:  variable_instance_exists(inst, "end_address") ? inst.end_address : inst.pc_address,
            org_parent_x: _op_x, org_parent_y: _op_y, has_org_parent: (_op_x != -1),
            proxy:        variable_instance_exists(inst, "proxy")       ? inst.proxy       : false,
            x_indent:     variable_instance_exists(inst, "x_indent")    ? inst.x_indent    : 0,
			helper_text:  variable_instance_exists(inst, "helper_text") ? inst.helper_text : "",
			anim_alias:      variable_instance_exists(inst, "anim_alias")       ? inst.anim_alias       : "",
            scroll_alias:    variable_instance_exists(inst, "scroll_alias")     ? inst.scroll_alias     : "",
            code_descriptor: variable_instance_exists(inst, "code_descriptor")  ? inst.code_descriptor  : "Code Block",
			show_only_used:  variable_instance_exists(inst, "show_only_used")   ? inst.show_only_used   : false,
            org_uid:         variable_instance_exists(inst, "org_uid")          ? inst.org_uid          : -1,
            wire_out_target: variable_instance_exists(inst, "wire_out_target")  ? inst.wire_out_target  : -1,
            wire_in_source:  variable_instance_exists(inst, "wire_in_source")   ? inst.wire_in_source   : -1,
            stable_uid:      variable_instance_exists(inst, "stable_uid")       ? inst.stable_uid       : -1,
			custom_title:    variable_instance_exists(inst, "custom_title")     ? inst.custom_title     : "",
            code: _save_code, binary_blob: _hex_data
			
        });
    }
    ds_priority_destroy(p_list);

    var box_data = [];
    with (obj_mapping_box) array_push(box_data, { x:x, y:y, box_w:box_w, box_h:box_h, box_name:box_name, box_col_idx:box_col_idx });

    var asset_data = [];
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a     = ds_list_find_value(_am.asset_list, _ai);
            var _hex   = "";
            if (buffer_exists(_a.buffer)) {
                _hex = scr_blob_encode(_a.buffer);
            }
            // Full meta mirror — reuse the same field list as scr_save_workspace_as
            var _mo = {};
            var _me = _a.meta;
            var _fields = ["sprite_mcs","sprite_ucs","mc1_col","mc2_col","used_count","bg_col","bmp_mode","tone_sorted",
                           "sprite_json","compositor","anim",
                           "sid_init_addr","sid_play_addr","sid_data_start",
                           "format","char_count","total_size","mc_mode","mc_fg","mc_bg","mc_col1","mc_col2",
                           "ecm_bg1","ecm_bg2","ecm_bg3",
                           "map_w","map_h","grid_w","grid_h","char_grid","colour_grid","chr_asset",
                           "scroll_x","scroll_y","zoom","active_char","active_colour","tool",
                           "text","byte_string","is_save_file","save_file_size","paint_mc","map_mixed","override_grid","map_mc_bg","map_mc_col1","map_mc_col2",
                           "song_name","sfx_count","instruments","wavetable","source_file",
                           "tile_types",
                           "line_string","lines","active_type","ref_enabled","ref_asset_name","ref_offset_x","ref_offset_y",
                           "gradient_custom_active","gradient_custom_cols","gradient_custom_count"];
            for (var _fi = 0; _fi < array_length(_fields); _fi++) {
                var _fk = _fields[_fi];
                if (variable_struct_exists(_me, _fk)) _mo[$ _fk] = _me[$ _fk];
            }
            if (_a.type == "META_TILESET") {
                _mo.stamp_w     = _me.stamp_w;
                _mo.stamp_h     = _me.stamp_h;
                _mo.stamp_count = _me.stamp_count;
                _mo.chr_asset   = _me.chr_asset;
                _mo.stamp_data  = _me.stamp_data;
                _mo.stamp_mc    = variable_struct_exists(_me, "stamp_mc") ? _me.stamp_mc : [];
                _mo.char_lut       = variable_struct_exists(_me, "char_lut")       ? _me.char_lut       : array_create(256, 0);
                _mo.char_lut_len   = variable_struct_exists(_me, "char_lut_len")   ? _me.char_lut_len   : 0;
                _mo.stamp_override = variable_struct_exists(_me, "stamp_override") ? _me.stamp_override : [];
                _mo.zoom        = _me.zoom;
                _mo.test_zoom   = _me.test_zoom;
                _mo.map_mc_bg   = _me.map_mc_bg;
                _mo.map_mc_col1 = _me.map_mc_col1;
                _mo.map_mc_col2 = _me.map_mc_col2;
                _mo.maps       = variable_struct_exists(_me, "maps")       ? _me.maps       : [];
                _mo.map_count  = variable_struct_exists(_me, "map_count")  ? _me.map_count  : 0;
                _mo.active_map = variable_struct_exists(_me, "active_map") ? _me.active_map : -1;
                _mo.test_grid  = variable_struct_exists(_me, "test_grid")  ? _me.test_grid  : [];
                // Size-guard key + per-map dims — without these the viewer's
                // "size changed -> clear maps" guard fires on first open after
                // an autosave recovery and wipes the maps.
                _mo.map_size_key = variable_struct_exists(_me, "map_size_key") ? _me.map_size_key : "";
                _mo.map_w        = variable_struct_exists(_me, "map_w")        ? _me.map_w        : [];
                _mo.map_h        = variable_struct_exists(_me, "map_h")        ? _me.map_h        : [];
            }
            if (_a.type == "MUSIC_MAKER") {
                _mo.instruments      = variable_struct_exists(_me, "instruments")      ? _me.instruments      : [];
                _mo.sel_instr        = variable_struct_exists(_me, "sel_instr")        ? _me.sel_instr        : -1;
                _mo.patterns         = variable_struct_exists(_me, "patterns")         ? _me.patterns         : [];
                _mo.bank_sel_pattern = variable_struct_exists(_me, "bank_sel_pattern") ? _me.bank_sel_pattern : 0;
                _mo.play_speed       = variable_struct_exists(_me, "play_speed")       ? _me.play_speed       : 6;
                // songs[] is the source of truth. song_order/song_loop/song_loop_row
                // are legacy and written only so an older build can still open the
                // file; nothing in the current editor or emitter reads them.
                _mo.songs            = variable_struct_exists(_me, "songs")            ? _me.songs            : [];
                _mo.sel_song         = variable_struct_exists(_me, "sel_song")         ? _me.sel_song         : 0;
                _mo.song_order       = variable_struct_exists(_me, "song_order")       ? _me.song_order       : [];
                _mo.sel_order_row    = variable_struct_exists(_me, "sel_order_row")    ? _me.sel_order_row    : 0;
                _mo.song_loop        = variable_struct_exists(_me, "song_loop")        ? _me.song_loop        : true;
                _mo.song_loop_row    = variable_struct_exists(_me, "song_loop_row")    ? _me.song_loop_row    : 0;
                _mo.sel_voice        = variable_struct_exists(_me, "sel_voice")        ? _me.sel_voice        : 0;
                _mo.sel_step         = variable_struct_exists(_me, "sel_step")         ? _me.sel_step         : 0;
                _mo.cur_octave       = variable_struct_exists(_me, "cur_octave")       ? _me.cur_octave       : 4;
                _mo.view_mode        = variable_struct_exists(_me, "view_mode")        ? _me.view_mode        : "VERTICAL";
                _mo.step_zoom        = variable_struct_exists(_me, "step_zoom")        ? _me.step_zoom        : 1;
                _mo.list_scroll      = variable_struct_exists(_me, "list_scroll")      ? _me.list_scroll      : 0;
            }
            if (_a.type == "META_MAP") {
                _mo.map_w        = _me.map_w;
                _mo.map_h        = _me.map_h;
                _mo.tileset_name = _me.tileset_name;
                _mo.index_data   = _me.index_data;
            }
            if (_a.type == "BITMAP" && variable_struct_exists(_me, "coll_types") && is_array(_me.coll_types)) {
                // Autosave writes unconditionally — a crash net shouldn't drop a
                // tagged sheet to save 1000 zero bytes.
                _mo.coll_types = _me.coll_types;
            }
            if (_a.type == "BITMAP_BUILDER") {
                _mo.src_asset  = variable_struct_exists(_me, "src_asset")  ? _me.src_asset  : "";
                _mo.dst_asset  = variable_struct_exists(_me, "dst_asset")  ? _me.dst_asset  : "";
                _mo.blend      = variable_struct_exists(_me, "blend")      ? _me.blend      : 0;
                _mo.records    = variable_struct_exists(_me, "records")    ? _me.records    : [];
                _mo.bbd_name   = variable_struct_exists(_me, "bbd_name")   ? _me.bbd_name   : "";
                _mo.prev_entry = variable_struct_exists(_me, "prev_entry") ? _me.prev_entry : 0;
                _mo.bbt_name   = variable_struct_exists(_me, "bbt_name")   ? _me.bbt_name   : "";
                _mo.tag_type   = variable_struct_exists(_me, "tag_type")   ? _me.tag_type   : 1;
            }
            if (_a.type == "VECTOR_BITMAP") {
                // Flush the live editor fields into pages[active_page] so the
                // currently-edited page is captured even if the user never
                // switched pages since drawing. Makes pages[] authoritative.
                scr_vbmp_page_store(_a);
                _mo.mode        = variable_struct_exists(_me, "mode")        ? _me.mode        : 1;
                _mo.bg          = variable_struct_exists(_me, "bg")          ? _me.bg          : 0;
                _mo.col1        = variable_struct_exists(_me, "col1")        ? _me.col1        : 1;
                _mo.col2        = variable_struct_exists(_me, "col2")        ? _me.col2        : 2;
                _mo.col3        = variable_struct_exists(_me, "col3")        ? _me.col3        : 3;
                _mo.fill_stack  = variable_struct_exists(_me, "fill_stack")  ? _me.fill_stack  : 0xC000;
                _mo.stream_addr = variable_struct_exists(_me, "stream_addr") ? _me.stream_addr : 0xC800;
                _mo.commands    = variable_struct_exists(_me, "commands")    ? _me.commands    : [];
                _mo.pages       = variable_struct_exists(_me, "pages")       ? _me.pages       : [];
                _mo.active_page = variable_struct_exists(_me, "active_page") ? _me.active_page : 0;
                _mo.active_col  = variable_struct_exists(_me, "active_col")  ? _me.active_col  : 1;
                _mo.active_pat  = variable_struct_exists(_me, "active_pat")  ? _me.active_pat  : 0;
                _mo.tool        = variable_struct_exists(_me, "tool")        ? _me.tool        : "LINE";
                _mo.zoom        = variable_struct_exists(_me, "zoom")        ? _me.zoom        : 2;
            }
            array_push(asset_data, {
                name          : _a.name,
                type          : _a.type,
                address       : _a.address,
                file          : _a.file,
                blob          : _hex,
                meta          : _mo,
                load_later    : variable_struct_exists(_a, "load_later")    ? _a.load_later    : false,
                d64_filename  : variable_struct_exists(_a, "d64_filename")  ? _a.d64_filename  : "",
                reu_filename  : variable_struct_exists(_a, "reu_filename")  ? _a.reu_filename  : "",
                reu_size      : variable_struct_exists(_a, "reu_size")      ? _a.reu_size      : 0,
                reu_used      : variable_struct_exists(_a, "reu_used")      ? _a.reu_used      : 0,
                linked_assets : variable_struct_exists(_a, "linked_assets") ? _a.linked_assets : [],
            });
        }
    }

var _root = { nodes:node_data, boxes:box_data, assets:asset_data,
                  basic_unlocked:global.basic_unlocked, kernal_unlocked:global.kernal_unlocked,
                  code_editor_font_index: code_editor_font_index,
                  map_global_mixed: obj_workspace_manager.map_global_mixed,
                  map_tile_bank:     variable_global_exists("map_tile_bank") ? global.map_tile_bank : [],
                  map_tile_bank_sel: variable_global_exists("map_tile_bank_sel") ? global.map_tile_bank_sel : -1,
                  next_stable_uid:   variable_global_exists("next_stable_uid")   ? global.next_stable_uid   : 100000,
                  ignored_conflicts: variable_global_exists("ignored_conflicts") ? global.ignored_conflicts : [],
                  asset_sort_mode:   obj_asset_manager.asset_sort_mode };
    var _json = json_stringify(_root);
    var _f = file_text_open_write(_path);
    file_text_write_string(_f, _json);
    file_text_close(_f);

    global.autosave_dirty       = false;
    global.autosave_last_path   = _path;
    ini_open("c64devmachine.ini");
    ini_write_string("autosave", "last_path", _path);
    ini_close();
    show_debug_message("AUTOSAVE: " + _path);
	obj_workspace_manager.autosave_last_path = _path;
	obj_workspace_manager.autosave_hour = current_hour;
	obj_workspace_manager.autosave_minute = current_minute;
	with (obj_workspace_manager) { autosave_flash_timer = game_get_speed(gamespeed_fps) * 3; }
}