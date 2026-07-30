/// @function scr_bitmap_builder_gen_tags(_asset)
/// @desc Emits the SOURCE sheet's collision tag grid as a BYTE_DATA asset.
///
/// 1000 bytes: 40x25 char cells, one byte each, 0 = no collision, 1..16 = type.
/// Emitted ONCE, not per room — this is the source sheet's tags, and every grab
/// of a tagged cell carries its type wherever it lands.
///
/// MACRO_MOVE_BMP_BLOCK reads it during the blit:
///     coll_type = BBT[src_row * 40 + src_col]
///     poke $0400 + (dst_row * 40 + dst_col), coll_type
///
/// Screen RAM is unused in bitmap mode (the VIC is pointed at $6000), so $0400
/// is 1000 bytes of free RAM that MACRO_COLL_ADV already reads. The collision
/// map therefore builds itself from the same pass that draws the pixels, at a
/// flat 1000-byte cost regardless of how many rooms the game has — and COLL_ADV
/// needs no changes at all.
///
/// Asset name: BBT_<builder>. Remembered in meta.bbt_name so re-generating
/// updates it in place. Skipped entirely when the sheet has no tags, so a
/// builder used purely for visuals costs nothing.
function scr_bitmap_builder_gen_tags(_asset) {
    if (!instance_exists(obj_asset_manager)) {
        return;
    }
    var _am = obj_asset_manager;
    var _m  = _asset.meta;

    // ── Resolve the source sheet and its tag grid ──
    var _src = noone;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "BITMAP" && _a.name == _m.src_asset) {
            _src = _a;
            break;
        }
    }
    if (_src == noone) {
        return;
    }
    if (!variable_struct_exists(_src.meta, "coll_types")) {
        return;
    }
    var _tags = _src.meta.coll_types;
    if (!is_array(_tags) || array_length(_tags) != 1000) {
        return;
    }

    // Untagged sheet -> no table. Bail before spawning 1000 bytes of zeros.
    var _any = false;
    for (var _ti = 0; _ti < 1000; _ti++) {
        if (_tags[_ti] != 0) {
            _any = true;
            break;
        }
    }
    if (!_any) {
        return;
    }

    // ── Body: 40 bytes per line — one screen row per line, so the table stays
    //    legible if anyone opens it in the BYTE_DATA editor.
    var _lines = [];
    for (var _row = 0; _row < 25; _row++) {
        var _cells = [];
        for (var _col = 0; _col < 40; _col++) {
            var _v = _tags[(_row * 40) + _col] & 0xFF;
            var _d = string(_v);
            if (string_length(_d) < 2) {
                _d = "0" + _d;
            }
            array_push(_cells, _d);
        }
        array_push(_lines, string_join_ext(", ", _cells));
    }
    var _body = string_join_ext("\n", _lines);
    var _want = _asset.name + "_TAGS";

    // ── Update in place if we already own one ──
    var _target = noone;
    if (_m.bbt_name != "") {
        for (var _bi = 0; _bi < ds_list_size(_am.asset_list); _bi++) {
            var _ba = ds_list_find_value(_am.asset_list, _bi);
            if (_ba.type == "BYTE_DATA" && _ba.name == _m.bbt_name) {
                _target = _ba;
                break;
            }
        }
    }

    if (_target != noone) {
        _target.meta.byte_string      = _body;
        _target.meta.inline_edit_text = _body;
        scr_asset_byte_data_flush(_target);
        _m.bbt_name = _target.name;
        global.addresses_dirty  = true;
        global.memory_bar_dirty = true;
        return;
    }

    // ── Create new, deduplicating the name against the whole list ──
    var _name   = _want;
    var _suffix = 2;
    var _dup    = true;
    while (_dup) {
        _dup = false;
        for (var _di = 0; _di < ds_list_size(_am.asset_list); _di++) {
            if (ds_list_find_value(_am.asset_list, _di).name == _name) {
                _name = _want + "_" + string(_suffix);
                _suffix += 1;
                _dup = true;
                break;
            }
        }
    }

    var _new_asset = {
        type          : "BYTE_DATA",
        name          : _name,
        file          : "",
        address       : scr_asset_default_address("BYTE_DATA"),
        buffer        : buffer_create(1, buffer_fixed, 1),
        meta          : {
            byte_string           : _body,
            inline_edit_open      : false,
            inline_edit_text      : _body,
            inline_edit_cursor    : 0,
            inline_edit_scroll_y  : 0,
            inline_edit_sel_start : -1,
            inline_edit_sel_end   : -1,
            inline_edit_blink     : 0,
            inline_edit_key_timer : 0
        },
        load_later    : false,
        d64_filename  : "",
        linked_assets : []
    };
    scr_asset_byte_data_flush(_new_asset);
    ds_list_add(_am.asset_list, _new_asset);
    _m.bbt_name = _name;

    global.addresses_dirty  = true;
    global.memory_bar_dirty = true;
    global.undo_dirty       = true;
}