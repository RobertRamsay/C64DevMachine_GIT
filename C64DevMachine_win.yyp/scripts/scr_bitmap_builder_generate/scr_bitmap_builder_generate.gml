/// @function scr_bitmap_builder_generate(_asset)
/// @desc Emits the builder's records as a BYTE_DATA asset that
///       MACRO_MOVE_BMP_BLOCK can pick in ASSET mode.
///
/// Table format — one record per line, decimal, terminated by a hex sentinel:
///     sx, sy, dx, dy, w, h
///     sx, sy, dx, dy, w, h
///     $FF
///
/// The BUILDER is the source of truth; the BYTE_DATA is a DERIVED ARTIFACT.
/// Re-generating overwrites it wholesale — hand edits to the table will be
/// lost. The asset is named BBDSolid_<builder> or BBDMasked_<builder> and its
/// name is remembered in meta.bbd_name, so subsequent generates update that
/// same asset in place rather than spawning a new one each time.
///
/// A trailing $FF is always appended if the last record isn't already an END,
/// so the runtime walk can never run off the end of the list.
function scr_bitmap_builder_generate(_asset) {
    if (!instance_exists(obj_asset_manager)) {
        return;
    }
    var _am = obj_asset_manager;
    var _m  = _asset.meta;

    // ── Build the table text ──
    var _lines = [];
    var _total = array_length(_m.records);
    var _last_was_end = false;

    for (var _i = 0; _i < _total; _i++) {
        var _rec = _m.records[_i];
        if (_rec.kind == "END") {
            // Sentinel must occupy a FULL 6-byte record slot. MACRO_MOVE_BMP_BLOCK
            // seeks with base + (entry_index * 6), so a bare $FF byte would shift
            // every record after the first run by -5 bytes.
            array_push(_lines, "$FF, $00, $00, $00, $00, $00");
            _last_was_end = true;
        } else {
            array_push(_lines, string(_rec.sx) + ", " + string(_rec.sy) + ", "
                             + string(_rec.dx) + ", " + string(_rec.dy) + ", "
                             + string(_rec.w)  + ", " + string(_rec.h));
            _last_was_end = false;
        }
    }
    // Always terminate. Padded to 6 bytes for the same stride reason as above.
    if (!_last_was_end) {
        array_push(_lines, "$FF, $00, $00, $00, $00, $00");
    }

    var _body = string_join_ext("\n", _lines);

    // ── Resolve the target name ──
    var _prefix = (_m.blend == 1) ? "BBDMasked_" : "BBDSolid_";
    var _want   = _prefix + _asset.name;

    // If we already own a BBD, find it and update it in place — even if the
    // blend flag changed since (in which case we also rename it to match).
    var _target = noone;
    if (_m.bbd_name != "") {
        for (var _bi = 0; _bi < ds_list_size(_am.asset_list); _bi++) {
            var _ba = ds_list_find_value(_am.asset_list, _bi);
            if (_ba.type == "BYTE_DATA" && _ba.name == _m.bbd_name) {
                _target = _ba;
                break;
            }
        }
    }

    if (_target != noone) {
        // ── UPDATE EXISTING ──
        // Rename if the blend mode flipped since it was made. Only rename when
        // nothing else already holds the new name.
        if (_target.name != _want) {
            var _clash = false;
            for (var _ci = 0; _ci < ds_list_size(_am.asset_list); _ci++) {
                var _ca = ds_list_find_value(_am.asset_list, _ci);
                if (_ca == _target) {
                    continue;
                }
                if (_ca.name == _want) {
                    _clash = true;
                    break;
                }
            }
            if (!_clash) {
                var _old_name = _target.name;
                _target.name  = _want;
                // Re-point any MOVE_BMP_BLOCK node that referenced the old name
                // (slot 17 = the BYTE_DATA list).
                with (obj_c64_node) {
                    if (node_type != "MACRO_MOVE_BMP_BLOCK") {
                        continue;
                    }
                    if (array_length(instructions[0]) > 17
                    &&  string(instructions[0][17]) == _old_name) {
                        instructions[0][17] = _want;
                    }
                }
            }
        }
        _target.meta.byte_string      = _body;
        _target.meta.inline_edit_text = _body;
        scr_asset_byte_data_flush(_target);
        _m.bbd_name = _target.name;
    } else {
        // ── CREATE NEW ──
        // Deduplicate the name against the whole asset list.
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
        _m.bbd_name = _name;
    }

    // ── COLLISION TAG GRID ──
    // The source sheet's tags, verbatim, as BBT_<builder>. Emitted ONCE — not
    // per room — because the tags belong to the ARTWORK, not to any one scene.
    // MACRO_MOVE_BMP_BLOCK reads it during the blit and writes each source
    // cell's type into $0400 + dest_cell, so the collision map is built by the
    // same pass that draws the pixels and costs a flat 1000 bytes however many
    // rooms the game has.
    scr_bitmap_builder_gen_tags(_asset);

    global.addresses_dirty  = true;
    global.memory_bar_dirty = true;
    global.undo_dirty       = true;
}