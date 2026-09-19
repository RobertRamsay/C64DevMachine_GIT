/// @function scr_import_reu_bmp_batch()
/// @description Batch-import every Koala bitmap in a folder as BITMAP assets,
///              file them under one collapsed asset group named after the
///              folder, then link them in order into a LOAD_REU manifest —
///              reusing an existing one if the project has it, creating one if
///              not.
///
///              GameMaker has no multi-select file dialog, so the user picks any
///              one bitmap and the folder around it is what gets imported.
///              .kla/.koa only: PNG/JPG go through the interactive conversion
///              editor one image at a time, which cannot be batched without
///              throwing away per-image review.

function scr_import_reu_bmp_batch() {

    if (!instance_exists(obj_asset_manager)) exit;
    var _am = obj_asset_manager;

    var _path = get_open_filename(
        "Koala Bitmaps (*.kla;*.koa)|*.kla;*.koa", "");
    // A native dialog steals the key-up, leaving GameMaker convinced the key is
    // still held, which silently kills ESC until the input state is reset.
    io_clear();
    if (_path == "") exit;

    var _dir = filename_dir(_path);

    // ---- collect every Koala file in that folder -------------------------
    var _files = [];
    var _masks = ["*.kla", "*.koa"];
    for (var _mi = 0; _mi < array_length(_masks); _mi++) {
        var _found = file_find_first(_dir + "\\" + _masks[_mi], 0);
        while (_found != "") {
            array_push(_files, _found);
            _found = file_find_next();
        }
        file_find_close();
    }

    if (array_length(_files) == 0) {
        scr_show_message(L("No .kla or .koa files were found in that folder."));
        exit;
    }

    // ---- natural order: frame_2 before frame_10 --------------------------
    // Digit runs are zero-padded into a sort key, so a plain string compare
    // orders numerically without a custom comparator.
    var _keyed = [];
    for (var _fi = 0; _fi < array_length(_files); _fi++) {
        var _nm  = string_lower(_files[_fi]);
        var _key = "";
        var _run = "";
        for (var _ci = 1; _ci <= string_length(_nm); _ci++) {
            var _ch = string_char_at(_nm, _ci);
            if (string_digits(_ch) == _ch && _ch != "") {
                _run += _ch;
            }
            else {
                if (_run != "") {
                    while (string_length(_run) < 8) _run = "0" + _run;
                    _key += _run;
                    _run = "";
                }
                _key += _ch;
            }
        }
        if (_run != "") {
            while (string_length(_run) < 8) _run = "0" + _run;
            _key += _run;
        }
        array_push(_keyed, { file: _files[_fi], key: _key });
    }
    array_sort(_keyed, function(_a, _b) {
        if (_a.key == _b.key) return 0;
        if (_a.key < _b.key) return -1;
        return 1;
    });

    // ---- group name comes from the folder --------------------------------
    var _dir_clean = _dir;
    while (string_length(_dir_clean) > 0
        && (string_char_at(_dir_clean, string_length(_dir_clean)) == "\\"
         || string_char_at(_dir_clean, string_length(_dir_clean)) == "/")) {
        _dir_clean = string_copy(_dir_clean, 1, string_length(_dir_clean) - 1);
    }
    var _group = string_upper(filename_name(_dir_clean));
    if (_group == "") _group = "REU BITMAPS";

    // ---- import each file as a BITMAP asset ------------------------------
    var _made       = [];
    var _skipped    = 0;
    var _first_addr = scr_asset_default_address("BITMAP");

    for (var _ki = 0; _ki < array_length(_keyed); _ki++) {
        var _fname = _keyed[_ki].file;
        var _full  = _dir + "\\" + _fname;

        var _buf = buffer_load(_full);
        if (!buffer_exists(_buf)) { _skipped++; continue; }

        var _size = buffer_get_size(_buf);
        // 10003 = multicolour Koala, 9002 = HiRes. Anything else is not a
        // bitmap this importer can vouch for, so it is left alone rather than
        // imported as something that will not compile.
        if (_size != 10003 && _size != 9002) {
            buffer_delete(_buf);
            _skipped++;
            continue;
        }

        var _base = filename_name(_fname);
        var _ext  = filename_ext(_fname);
        _base = string_copy(_base, 1, string_length(_base) - string_length(_ext));

        // Unique within the project — a second import of the same folder must
        // not collide with the assets already there.
        var _name  = _base;
        var _tries = 2;
        while (!is_undefined(scr_reu_find_asset(_name))) {
            _name  = _base + "_" + string(_tries);
            _tries++;
        }

        var _meta = {
            format        : "koala",
            preview_surf  : -1,
            pixel_backup  : -1,
            pixels_dirty  : false,
            bg_col        : 0,
            bg_mask       : array_create(64000, 0),
            clash_grid    : array_create(1000, false),
            coll_types    : array_create(1000, 0),
            auto_clean    : true,
            is_editing    : false,
            needs_mask_init : true,
            active_color  : 1,
            active_tool   : "DRAW",
            dither_mode   : "NONE",
            dither_invert : false,
            brush_size    : 0,
            bmp_pan_x     : 0,
            bmp_pan_y     : 0,
            last_px       : undefined,
            last_py       : undefined,
            undo_stack    : [],
            redo_stack    : [],
            undo_pending  : false,
            tone_sorted   : false,
            bmp_mode      : "MC",
            source_file   : _full
        };
        if (_size == 9002) _meta.bmp_mode = "HIRES";

        var _asset = {
            type          : "BITMAP",
            name          : _name,
            file          : _full,
            address       : _first_addr,
            buffer        : _buf,
            meta          : _meta,
            load_later    : false,
            d64_filename  : "",
            reu_filename  : "",
            reu_size      : 0,
            reu_used      : 0,
            linked_assets : [],
            group         : _group
        };

        ds_list_add(_am.asset_list, _asset);
        array_push(_made, _name);

        // Same post-load pipeline the single-file importer runs, so a batched
        // asset is indistinguishable from a hand-imported one.
        scr_asset_bmp_build_preview(_asset);
        scr_asset_kla_heal_palette(_asset);
        scr_asset_kla_process_surface(_asset, false, -1);
        if (file_exists(_asset.file)) _asset.meta._mtime = md5_file(_asset.file);
    }

    if (array_length(_made) == 0) {
        scr_show_message(L("No usable Koala bitmaps were found.\nExpected 10003-byte multicolour or 9002-byte HiRes files."));
        exit;
    }

    // ---- fold the new group away ----------------------------------------
    // ds_map_exists on asset_group_open is what marks a group expanded, so
    // simply not adding the key leaves it closed.
    if (ds_map_exists(_am.asset_group_open, _group)) {
        ds_map_delete(_am.asset_group_open, _group);
    }

    // ---- find or create the LOAD_REU manifest ----------------------------
    var _manifest = undefined;
    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
        var _cand = ds_list_find_value(_am.asset_list, _ai);
        if (_cand.type == "LOAD_REU") { _manifest = _cand; break; }
    }

    var _created_manifest = false;
    if (is_undefined(_manifest)) {
        var _mname  = "LOAD_REU";
        var _mtries = 2;
        while (!is_undefined(scr_reu_find_asset(_mname))) {
            _mname = "LOAD_REU_" + string(_mtries);
            _mtries++;
        }
        _manifest = {
            type          : "LOAD_REU",
            name          : _mname,
            file          : "",
            address       : scr_asset_default_address("LOAD_REU"),
            buffer        : buffer_create(1, buffer_fixed, 1),
            meta          : {},
            load_later    : false,
            d64_filename  : "",
            reu_filename  : _mname + ".reu",
            reu_size      : 0x1000000,
            reu_used      : 0x100,
            linked_assets : [],
            group         : ""
        };
        ds_list_add(_am.asset_list, _manifest);
        _created_manifest = true;
    }

    // ---- link the new bitmaps in order -----------------------------------
    for (var _li = 0; _li < array_length(_made); _li++) {
        array_push(_manifest.linked_assets, {
            asset_name  : _made[_li],
            reu_address : 0x100,
            auto_pack   : true
        });
    }
    scr_reu_repack(_manifest);

    global.undo_dirty       = true;
    global.memory_bar_dirty = true;
    global.addresses_dirty  = true;
    global.autosave_dirty   = true;

    var _msg = L("Imported ") + string(array_length(_made)) + L(" bitmaps into group ") + _group
             + L("\nLinked into ") + _manifest.name;
    if (_created_manifest) _msg += L(" (created)");
    if (_skipped > 0) _msg += L("\nSkipped ") + string(_skipped) + L(" file(s) that were not 10003 or 9002 bytes.");
    scr_show_message(_msg);
}
