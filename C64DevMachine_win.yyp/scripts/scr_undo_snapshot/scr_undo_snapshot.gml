/// scr_undo_snapshot()
/// Saves a lightweight state snapshot (no binary blobs) to the undo temp folder.
function scr_undo_snapshot() {
    // Don't snapshot if no workspace yet and temp isn't set up
    var _undo_dir = working_directory + "temp/undo/";
    if (!directory_exists(working_directory + "temp/")) directory_create(working_directory + "temp/");
    if (!directory_exists(_undo_dir)) directory_create(_undo_dir);

    // Load manifest
    var _manifest_path = _undo_dir + "manifest.json";
    var _states  = [];
    var _current = -1;

    if (file_exists(_manifest_path)) {
        var _f = file_text_open_read(_manifest_path);
        var _raw = "";
        while (!file_text_eof(_f)) { _raw += file_text_read_string(_f); file_text_readln(_f); }
        file_text_close(_f);
        var _m = json_parse(_raw);
        _states  = variable_struct_exists(_m, "states")  ? _m.states  : [];
        _current = variable_struct_exists(_m, "current") ? _m.current : -1;
    }

    // Discard forward history if we branched
    if (_current >= 0 && _current < array_length(_states) - 1) {
        for (var _i = _current + 1; _i < array_length(_states); _i++) {
            var _old = _undo_dir + _states[_i];
            if (file_exists(_old)) file_delete(_old);
        }
        var _trimmed = [];
        for (var _i = 0; _i <= _current; _i++) array_push(_trimmed, _states[_i]);
        _states = _trimmed;
    }


    if (array_length(_states) >= global.undo_states) {
        var _old = _undo_dir + _states[0];
        if (file_exists(_old)) file_delete(_old);
        var _shifted = [];
        for (var _i = 1; _i < array_length(_states); _i++) array_push(_shifted, _states[_i]);
        _states = _shifted;
    }

    // Generate filename
    var _idx      = 0;
    var _filename = "state_000.json";
    if (array_length(_states) > 0) {
        var _last = _states[array_length(_states) - 1];
        var _num  = real(string_digits(_last));
        _idx      = (_num + 1) mod 1000;
    }
    var _numstr = string(_idx);
    while (string_length(_numstr) < 3) _numstr = "0" + _numstr;
    _filename = "state_" + _numstr + ".json";

    // --- BUILD NODE DATA (no binary_blob) ---
    var _node_data = [];
    var _p_list    = ds_priority_create();
    with (obj_c64_node) {
        var _sort_key = (node_type == "ORG") ? -99999 + y : y;
        ds_priority_add(_p_list, id, _sort_key);
    }
    while (!ds_priority_empty(_p_list)) {
        var _inst = ds_priority_delete_min(_p_list);
        var _op_x = -1;
        var _op_y = -1;
        if (variable_instance_exists(_inst, "org_parent") &&
            _inst.org_parent != noone &&
            instance_exists(_inst.org_parent)) {
            _op_x = _inst.org_parent.x;
            _op_y = _inst.org_parent.y;
        }
        array_push(_node_data, {
            title:          _inst.node_title,
            type:           _inst.node_type,
            x:              _inst.x,
            y:              _inst.y,
            height:         _inst.height,
            connected:      _inst.is_connected,
            pc_address:     _inst.pc_address,
            end_address:    variable_instance_exists(_inst, "end_address") ? _inst.end_address : _inst.pc_address,
            org_parent_x:   _op_x,
            org_parent_y:   _op_y,
            has_org_parent: (_op_x != -1),
            // ORG fold state. Absent in projects saved before the fold
            // existed, which load expanded — the correct default.
            collapsed:      _inst.collapsed,
            proxy:          variable_instance_exists(_inst, "proxy")        ? _inst.proxy        : false,
            helper_text:    variable_instance_exists(_inst, "helper_text")  ? _inst.helper_text  : "",
            x_indent:       variable_instance_exists(_inst, "x_indent")     ? _inst.x_indent     : 0,
			anim_alias:      variable_instance_exists(_inst, "anim_alias")      ? _inst.anim_alias      : "",
            scroll_alias:    variable_instance_exists(_inst, "scroll_alias")     ? _inst.scroll_alias    : "",
            code_descriptor: variable_instance_exists(_inst, "code_descriptor")  ? _inst.code_descriptor : "",
			show_only_used:  variable_instance_exists(_inst, "show_only_used")   ? _inst.show_only_used  : false,
            org_uid:         variable_instance_exists(_inst, "org_uid")          ? _inst.org_uid          : -1,
            wire_out_target: variable_instance_exists(_inst, "wire_out_target")  ? _inst.wire_out_target  : -1,
            wire_in_source:  variable_instance_exists(_inst, "wire_in_source")   ? _inst.wire_in_source   : -1,
            stable_uid:      variable_instance_exists(_inst, "stable_uid")       ? _inst.stable_uid       : 0,
            code:            variable_clone(_inst.instructions),
            binary_blob:    ""  // intentionally empty — buffers live on disk
        });
    }
    ds_priority_destroy(_p_list);

    // --- BUILD BOX DATA ---
    var _box_data = [];
    with (obj_mapping_box) {
        array_push(_box_data, { x: x, y: y, box_w: box_w, box_h: box_h, box_name: box_name, box_col_idx: box_col_idx });
    }

    // --- BUILD ASSET METADATA (no blob, just enough to know what was loaded) ---
    var _asset_data = [];
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
			var _snap_meta = {};
            if (_a.type == "MAP_DATA" && variable_struct_exists(_a.meta, "map_w")) {
                _snap_meta.map_w       = _a.meta.map_w;
                _snap_meta.map_h       = _a.meta.map_h;
                _snap_meta.grid_w      = variable_struct_exists(_a.meta, "grid_w")      ? _a.meta.grid_w      : _a.meta.map_w;
                _snap_meta.grid_h      = variable_struct_exists(_a.meta, "grid_h")      ? _a.meta.grid_h      : _a.meta.map_h;
                _snap_meta.chr_asset   = variable_struct_exists(_a.meta, "chr_asset")   ? _a.meta.chr_asset   : "";
                _snap_meta.char_grid   = variable_struct_exists(_a.meta, "char_grid")   ? _a.meta.char_grid   : [];
                _snap_meta.colour_grid = variable_struct_exists(_a.meta, "colour_grid") ? _a.meta.colour_grid : [];
                _snap_meta.override_grid = variable_struct_exists(_a.meta, "override_grid") ? _a.meta.override_grid : [];
            }
            if (_a.type == "BITMAP" && variable_struct_exists(_a.meta, "coll_types")) {
                // Clone, not reference — an aliased snapshot would be rewritten
                // by the next tag stroke, making undo a no-op.
                _snap_meta.coll_types = variable_clone(_a.meta.coll_types);
            }
            if (_a.type == "BITMAP_BUILDER" && variable_struct_exists(_a.meta, "records")) {
                _snap_meta.records    = variable_clone(_a.meta.records);
                _snap_meta.prev_entry = variable_struct_exists(_a.meta, "prev_entry") ? _a.meta.prev_entry : 0;
                _snap_meta.bbd_name   = variable_struct_exists(_a.meta, "bbd_name")   ? _a.meta.bbd_name   : "";
                _snap_meta.bbt_name   = variable_struct_exists(_a.meta, "bbt_name")   ? _a.meta.bbt_name   : "";
            }
            if (_a.type == "CHAR_SET" && variable_struct_exists(_a.meta, "tile_types")) {
                _snap_meta.tile_types  = variable_clone(_a.meta.tile_types);
                _snap_meta.char_count  = variable_struct_exists(_a.meta, "char_count") ? _a.meta.char_count : 256;
            }
            if (_a.type == "SPRITE_SET" && variable_struct_exists(_a.meta, "used_count")) {
                _snap_meta.used_count  = _a.meta.used_count;
                _snap_meta.bg_col      = variable_struct_exists(_a.meta, "bg_col")      ? _a.meta.bg_col      : 0;
                _snap_meta.mc1_col     = variable_struct_exists(_a.meta, "mc1_col")     ? _a.meta.mc1_col     : 1;
                _snap_meta.mc2_col     = variable_struct_exists(_a.meta, "mc2_col")     ? _a.meta.mc2_col     : 2;
                _snap_meta.sprite_json = variable_struct_exists(_a.meta, "sprite_json") ? _a.meta.sprite_json : "[]";
                _snap_meta.sprite_mcs  = variable_struct_exists(_a.meta, "sprite_mcs")  ? _a.meta.sprite_mcs  : array_create(64, 0);
                _snap_meta.sprite_ucs  = variable_struct_exists(_a.meta, "sprite_ucs")  ? _a.meta.sprite_ucs  : array_create(64, 1);
            }
            array_push(_asset_data, {
                name:    _a.name,
                type:    _a.type,
                address: _a.address,
                file:    _a.file,
                blob:    "",
                meta:    _snap_meta
            });
        }
    }

    // --- CAMERA STATE ---
var _wm = instance_exists(obj_workspace_manager) ? obj_workspace_manager : noone;
var _cam = {
    cam_x:    (_wm != noone && variable_instance_exists(_wm, "cam_x"))    ? _wm.cam_x    : 0,
    cam_y:    (_wm != noone && variable_instance_exists(_wm, "cam_y"))    ? _wm.cam_y    : 0,
    cam_zoom: (_wm != noone && variable_instance_exists(_wm, "cam_zoom")) ? _wm.cam_zoom : 1
};

    var _root = {
        nodes:           _node_data,
        boxes:           _box_data,
        assets:          _asset_data,
        camera:          _cam,
        basic_unlocked:  global.basic_unlocked,
        kernal_unlocked: global.kernal_unlocked
    };

    var _raw    = json_stringify(_root);
    var _path   = _undo_dir + _filename;
    var _f2     = file_text_open_write(_path);
    file_text_write_string(_f2, _raw);
    file_text_close(_f2);

    // Update manifest
    array_push(_states, _filename);
    _current = array_length(_states) - 1;

    var _mroot = { states: _states, current: _current };
    var _mraw  = json_stringify(_mroot);
    var _mf    = file_text_open_write(_manifest_path);
    file_text_write_string(_mf, _mraw);
    file_text_close(_mf);

   
}