function scr_compile_macro_save_game(_list, _curr) {
    var _id        = _curr;
    var _org_name  = (array_length(_id.instructions[0]) > 1) ? string(_id.instructions[0][1]) : "";
    var _file_name = (array_length(_id.instructions[0]) > 2) ? string(_id.instructions[0][2]) : "";

    if (_org_name == "" || _file_name == "") {
        show_debug_message("MACRO_SAVE_GAME WARNING: org=[" + _org_name + "] file=[" + _file_name + "] — incomplete, skipping emit");
        exit;
    }

    var _d64_filename = "";
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "LOAD_ORG" && _a.name == _org_name) {
                if (variable_struct_exists(_a, "linked_assets")) {
                    var _lks = _a.linked_assets;
                    for (var _lki = 0; _lki < array_length(_lks); _lki++) {
                        if (_lks[_lki].asset_name == _file_name) {
                            _d64_filename = variable_struct_exists(_lks[_lki], "d64_filename")
                                          ? _lks[_lki].d64_filename : string_upper(_file_name);
                            break;
                        }
                    }
                }
                break;
            }
        }
    }
    if (_d64_filename == "") {
        show_debug_message("MACRO_SAVE_GAME WARNING: '" + _file_name + "' not linked to LOAD_ORG '" + _org_name + "'");
        exit;
    }

    var _save_addr = -1;
    var _save_size = 0;
    if (instance_exists(obj_asset_manager)) {
        var _am2 = obj_asset_manager;
        for (var _bi = 0; _bi < ds_list_size(_am2.asset_list); _bi++) {
            var _b = ds_list_find_value(_am2.asset_list, _bi);
            if (_b.name == _file_name) {
                _save_addr = _b.address;
                _save_size = buffer_exists(_b.buffer) ? buffer_get_size(_b.buffer) : 0;
                if (_b.type != "BYTE_DATA" || !variable_struct_exists(_b.meta, "is_save_file") || !_b.meta.is_save_file) {
                    show_debug_message("MACRO_SAVE_GAME WARNING: '" + _file_name + "' is not a BYTE_DATA asset with USE AS SAVE FILE enabled");
                }
                break;
            }
        }
    }
    if (_save_addr < 0 || _save_size <= 0) {
        show_debug_message("MACRO_SAVE_GAME WARNING: could not resolve save range for '" + _file_name + "' — skipping emit");
        exit;
    }
    var _end_addr = _save_addr + _save_size;

    var _d64n_save = string_upper("@0:" + _d64_filename);
    if (string_length(_d64n_save) > 16) {
        _d64n_save = string_copy(_d64n_save, 1, 16);
    }
    var _fn_len = string_length(_d64n_save);

    var _p         = "svg" + string(real(_id)) + "_";
    var _lbl_skip  = _p + "skip";
    var _lbl_fname = _p + "fname";

    show_debug_message("MACRO_SAVE_GAME: org=" + _org_name + " file=" + _file_name
        + " d64=" + _d64n_save + " addr=$" + string_upper(decimal_to_hex(_save_addr))
        + " size=" + string(_save_size));

    array_push(_list, ["jmp_abs", _lbl_skip, _id]);
    array_push(_list, ["label",   _lbl_fname]);
    for (var _si = 1; _si <= _fn_len; _si++) {
        var _ch = string_ord_at(_d64n_save, _si);
        array_push(_list, ["byte", _ch & 0xFF, _id]);
    }
    array_push(_list, ["label", _lbl_skip]);

    array_push(_list, ["lda_imm", _save_addr & 0xFF,        _id]);
    array_push(_list, ["sta_zp",  0xFB,                     _id]);
    array_push(_list, ["lda_imm", (_save_addr >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_zp",  0xFC,                     _id]);

    array_push(_list, ["lda_imm", 0x01,   _id]);
    array_push(_list, ["ldx_imm", 0x08,   _id]);
    array_push(_list, ["ldy_imm", 0x00,   _id]);
    array_push(_list, ["jsr",     0xFFBA, _id]);

    array_push(_list, ["lda_imm",    _fn_len,    _id]);
    array_push(_list, ["ldx_lab_lo", _lbl_fname, _id]);
    array_push(_list, ["ldy_lab_hi", _lbl_fname, _id]);
    array_push(_list, ["jsr",        0xFFBD,     _id]);

    array_push(_list, ["lda_imm", 0xFB,                   _id]);
    array_push(_list, ["ldx_imm", _end_addr & 0xFF,        _id]);
    array_push(_list, ["ldy_imm", (_end_addr >> 8) & 0xFF, _id]);
    array_push(_list, ["jsr",     0xFFD8,                 _id]);
}