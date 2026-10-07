/// ====================================================================
/// CODE BLOCK IMPORT  (all editions; code text is view-only in LITE)
///
/// The mirror of the EXPORT button in scr_code_editor_draw. Two ways in:
///
///   * IMPORT button, inside the code editor. Acts on the block being
///     edited: appends or replaces, and asks which when the block already
///     holds code.
///
///   * IMPORT menu -> CODE BLOCK (.ASM). Spawns a NEW code block holding
///     the file and latches it to the pointer, so the drop position is a
///     click rather than a guess. The menu entry is built only when
///     !global.lite, so there is nothing to choose in the Lite build.
///
/// Functions:
///   scr_import_code_block_read()     file dialog -> text ("" on cancel)
///   scr_import_code_block_menu()     menu entry: spawn + latch
///   scr_code_import_step()           ride the pointer, drop, cancel
///   scr_code_import_draw_banner()    the "click to drop it" strip
///   scr_code_import_primary_pressed() one platform seam, as elsewhere
/// ====================================================================

/// ====================================================================
/// BLOCK NAME CARRIED IN THE FILE
///
/// code_descriptor is the name on the node header — the thing you rename
/// by clicking the title. It lives on the instance, not in the text, so a
/// plain .asm export dropped it and every import came back as "Code Block".
///
/// So the export writes it as a `// @name <descriptor>` line at the top and
/// the import reads it back. scr_parse_asm_text skips `//` lines outright,
/// so the marker is inert in every other consumer — the assembler, the byte
/// counter, the label picker and the round-trip verifier all ignore it.
///
/// It is STRIPPED from the text on import rather than left in place, so the
/// descriptor stays the single source of truth: rename the block afterwards
/// and the next export writes the new name, with no stale line to disagree
/// with the header.
/// ====================================================================

/// @function scr_code_block_name_read(_txt)
/// @desc Pull the `// @name ...` value out of a code listing.
/// @return {String} the name, or "" when the file does not carry one.
function scr_code_block_name_read(_txt) {
    var _lines = string_split(string(_txt), "\n");
    for (var _i = 0; _i < array_length(_lines); _i++) {
        var _l = string_trim(_lines[_i]);
        if (string_length(_l) < 8) {
            continue;
        }
        if (string_upper(string_copy(_l, 1, 8)) != "// @NAME") {
            continue;
        }
        return string_trim(string_delete(_l, 1, 8));
    }
    return "";
}

/// @function scr_code_block_name_strip(_txt)
/// @desc Remove every `// @name ...` line, so re-exporting cannot stack them up.
function scr_code_block_name_strip(_txt) {
    var _lines = string_split(string(_txt), "\n");
    var _out   = "";
    var _first = true;
    for (var _i = 0; _i < array_length(_lines); _i++) {
        var _l = string_trim(_lines[_i]);
        if (string_length(_l) >= 8 && string_upper(string_copy(_l, 1, 8)) == "// @NAME") {
            continue;
        }
        if (!_first) {
            _out += "\n";
        }
        _out += _lines[_i];
        _first = false;
    }
    return _out;
}

/// @function scr_code_block_name_apply(_txt, _name)
/// @desc Put one `// @name` line at the top of a listing, replacing any it had.
function scr_code_block_name_apply(_txt, _name) {
    var _clean = scr_code_block_name_strip(_txt);
    if (string_trim(string(_name)) == "") {
        return _clean;
    }
    return "// @name " + string_trim(string(_name)) + "\n" + _clean;
}

/// @function scr_import_code_block_read()
/// @desc Open a file dialog and read an assembly listing whole.
/// @return {String} the file text, or "" when cancelled or unreadable.
function scr_import_code_block_read() {
    var _path = get_open_filename("Assembly Files|*.asm;*.txt|All Files|*.*", "");
    // A native file dialog takes focus, so the key-up that ends the keypress is
    // delivered to the dialog and not to the game. GameMaker is left thinking the
    // key is still held, and keyboard_check_pressed() needs an up->down edge — so
    // ESC silently stops working until the input state is reset. Every importer
    // in this project does this immediately after its dialog returns.
    io_clear();

    if (_path == "") {
        return "";
    }
    if (!file_exists(_path)) {
        scr_show_message("CODE IMPORT\n\nThat file could not be found.");
        return "";
    }

    // buffer_load + buffer_text reads the whole file as one string, newlines
    // intact. The file_text_read_string loop the asset importers use drops the
    // line breaks, which is fine for a byte list and useless for source.
    var _buf = buffer_load(_path);
    if (_buf < 0) {
        scr_show_message("CODE IMPORT\n\nThat file could not be read.");
        return "";
    }
    var _txt = buffer_read(_buf, buffer_text);
    buffer_delete(_buf);

    // A Windows-authored .asm opened on macOS otherwise carries CRs into
    // scr_parse_asm_text, which reads them as part of the operand.
    _txt = string_replace_all(_txt, "\r\n", "\n");
    _txt = string_replace_all(_txt, "\r",   "\n");

    if (string_trim(_txt) == "") {
        scr_show_message("CODE IMPORT\n\nThat file is empty.");
        return "";
    }
    return _txt;
}

/// @function scr_import_code_block_menu()
/// @desc IMPORT menu entry. Reads a file, spawns a code block holding it, and
///       latches that block to the pointer until the next click drops it.
function scr_import_code_block_menu() {
    if (global.code_import_node != noone) {
        return;   // one in flight is enough
    }

    var _txt = scr_import_code_block_read();
    if (_txt == "") {
        return;
    }

    var _n = scr_node_spawn("MACRO_CODE", mouse_x, mouse_y);
    // The file names the block when it carries a `// @name` line — which is
    // what this project's own exports write — so a block exported as
    // "Border Flash" comes back as "Border Flash" and not "Code Block".
    var _name = scr_code_block_name_read(_txt);
    _txt = scr_code_block_name_strip(_txt);
    if (_name == "") {
        _name = "IMPORTED CODE";
    }
    _n.code_descriptor    = _name;
    _n.instructions[0][1] = _txt;
    _n.code_cache_dirty   = true;
    _n.height_dirty       = true;
    with (_n) { event_user(0); }

    global.code_import_node    = _n;
    global.code_import_release = 0;

    // obj_c64_node's Step exits wholesale on this, so the latched block cannot
    // be grabbed, dragged or edited by the very click meant to drop it.
    global.canEditNode = false;
}

/// @function scr_code_import_step()
/// @desc Call early in obj_workspace_manager's Step. While a block is latched
///       this owns the frame, the same way the code editor and welcome screen
///       do, so no workspace shortcut fires under the pointer.
/// @return {Bool} true while the import owns the frame.
function scr_code_import_step() {
    // Input is handed back a frame late on purpose. Instance Step order is not
    // defined, so releasing canEditNode in the same frame as the drop click can
    // let obj_c64_node see that same press and start a drag on the block that
    // was just placed.
    if (global.code_import_release > 0) {
        global.code_import_release -= 1;
        if (global.code_import_release == 0) {
            global.canEditNode = true;
        }
        return true;
    }

    if (global.code_import_node == noone) {
        return false;
    }
    if (!instance_exists(global.code_import_node)) {
        global.code_import_node = noone;
        global.canEditNode      = true;
        return false;
    }

    var _n = global.code_import_node;
    _n.x = mouse_x - (_n.width / 2);
    _n.y = mouse_y - 12;

    // ESC abandons the import rather than leaving a block stuck to the pointer
    // with no way off it.
    if (keyboard_check_pressed(vk_escape)) {
        instance_destroy(_n);
        global.code_import_node = noone;
        global.canEditNode      = true;
        keyboard_clear(vk_escape);
        return true;
    }

    if (scr_code_import_primary_pressed()) {
        global.code_import_node    = noone;
        global.code_import_release = 2;

        global.addresses_dirty = true;
        global.undo_dirty      = true;
        global.autosave_dirty  = true;

        with (obj_c64_node) {
            stats_cache_dirty = true;
            height_dirty      = true;
        }
    }
    return true;
}

/// @function scr_code_import_draw_banner()
/// @desc The strip along the bottom of the GUI while a block is latched.
///       Call from obj_workspace_manager's Draw GUI.
function scr_code_import_draw_banner() {
    if (global.code_import_node == noone)          { exit; }
    if (!instance_exists(global.code_import_node)) { exit; }

    // Same plate the CONVERT button speaks from — one place on screen for
    // everything this feature has to say, and it sits well clear of the bottom
    // edge rather than hugging it.
    var _msg = "IMPORTED CODE LATCHED TO MOUSE - CLICK TO DROP IT   (ESC CANCELS)";
    var _r   = scr_cbc_message_rect(_msg);
    var _bx  = _r.x;
    var _by  = _r.y;
    var _bw  = _r.w;
    var _bh  = _r.h;

    draw_sprite_stretched(spr_glassSlice, niceSliceFrm, _bx, _by, _bw, _bh);

    var _font_before   = draw_get_font();
    var _halign_before = draw_get_halign();
    var _valign_before = draw_get_valign();

    draw_set_font_l(fnt_C64_Angled);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_color(make_color_rgb(255, 210, 80));
    draw_rectangle(_bx + 2, _by + 2, _bx + _bw - 2, _by + _bh - 2, true);
    draw_text_l(_bx + (_bw / 2), _by + (_bh / 2), _msg);

    draw_set_font_l(_font_before);
    draw_set_halign(_halign_before);
    draw_set_valign(_valign_before);
    draw_set_color(c_white);
}

// Windows uses the raw button; the macOS port swaps the body of this one
// function for `return scr_primary_pressed();` and nothing else changes.
function scr_code_import_primary_pressed() {
    return mouse_check_button_pressed(mb_left);
}

// =====================================================================
// MAPPING BOX FILE (.c64box) — a box and the nodes in it, so a block of
// work can move to another project. JSON:
//   { format:"C64DM_MAPPING_BOX", version:1, box:{...}, nodes:[record...] }
// Each record is exactly what a project save writes (scr_node_save_record),
// with x/y relative to the box and parent_idx = index of its ORG in nodes[]
// (-1 when it has none). Import builds nodes through the loader's own
// scr_node_from_record and gives them fresh uids, so it can't collide with
// what is already in the project.
// =====================================================================

/// Nodes a box carries: everything whose centre is inside it (the same test
/// the box drag uses), plus the stacked children of any ORG it holds, which
/// can hang below the box. SYSTEM INIT and EXECUTE are one-per-project.
function scr_mapping_box_contents(_box) {
    var _out = [];
    with (obj_c64_node) {
        if (node_type == "EXECUTE" || node_type == "INIT") continue;
        var _nx = x + (width * 0.5);
        var _ny = y + (height * 0.5);
        if (_nx >= _box.x && _nx <= _box.x + _box.box_w && _ny >= _box.y && _ny <= _box.y + _box.box_h) {
            array_push(_out, id);
        }
    }
    var _n0 = array_length(_out);
    for (var _i = 0; _i < _n0; _i++) {
        var _org = _out[_i];
        if (_org.node_type != "ORG") continue;
        with (obj_c64_node) {
            if (org_parent != _org) continue;
            var _have = false;
            for (var _j = 0; _j < array_length(_out); _j++) if (_out[_j] == id) { _have = true; break; }
            if (!_have) array_push(_out, id);
        }
    }
    return _out;
}

/// EXPORT button in the mapping box popup. _name is the name in the popup.
function scr_mapping_box_export(_box, _name) {
    if (!instance_exists(_box)) return;
    var _nodes = scr_mapping_box_contents(_box);
    if (array_length(_nodes) == 0) {
        scr_show_message("EXPORT MAPPING BOX\n\nThere are no nodes inside '" + _name + "'.");
        return;
    }
    var _fn = get_save_filename("C64DM Mapping Box|*.c64box", _name + ".c64box");
    io_clear();
    if (_fn == "") return;
    if (string_lower(filename_ext(_fn)) != ".c64box") _fn += ".c64box";

    var _recs = [];
    for (var _i = 0; _i < array_length(_nodes); _i++) {
        var _n = _nodes[_i];
        var _r = scr_node_save_record(_n);
        _r.x -= _box.x;
        _r.y -= _box.y;
        // Parent by index into this file, not by canvas position
        _r.parent_idx = -1;
        if (_n.org_parent != noone && instance_exists(_n.org_parent)) {
            for (var _j = 0; _j < array_length(_nodes); _j++) {
                if (_nodes[_j] == _n.org_parent) { _r.parent_idx = _j; break; }
            }
        }
        _r.org_parent_x   = -1;
        _r.org_parent_y   = -1;
        _r.has_org_parent = (_r.parent_idx >= 0);
        array_push(_recs, _r);
    }
    var _out = { format: "C64DM_MAPPING_BOX", version: 1,
                 box: { box_w: _box.box_w, box_h: _box.box_h, box_name: _name, box_col_idx: _box.box_col_idx,
                        is_panel: _box.is_panel, panel_links: _box.panel_links },
                 nodes: _recs };
    var _txt = json_stringify(_out);
    var _buf = buffer_create(string_byte_length(_txt) + 1, buffer_fixed, 1);
    buffer_write(_buf, buffer_text, _txt);
    buffer_save_ext(_buf, _fn, 0, string_byte_length(_txt));
    buffer_delete(_buf);
    scr_show_message("EXPORT MAPPING BOX\n\n'" + _name + "' and " + string(array_length(_recs))
        + " node(s) written to\n" + filename_name(_fn)
        + "\n\nAssets the nodes use (music, sprites, maps...) are not included.");
}

/// IMPORT menu: a .c64box file comes in as a new box, centred in the view.
function scr_import_mapping_box() {
    var _fn = get_open_filename("C64DM Mapping Box|*.c64box|All Files|*.*", "");
    io_clear();
    if (_fn == "") return;
    if (!file_exists(_fn)) {
        scr_show_message("IMPORT MAPPING BOX\n\nFile not found:\n" + _fn);
        return;
    }
    var _fb = buffer_load(_fn);
    var _txt = buffer_read(_fb, buffer_text);
    buffer_delete(_fb);
    var _d = undefined;
    try { _d = json_parse(_txt); } catch (_e) { _d = undefined; }
    if (!is_struct(_d) || _d[$ "format"] != "C64DM_MAPPING_BOX" || !is_struct(_d[$ "box"]) || !is_array(_d[$ "nodes"])) {
        scr_show_message("IMPORT MAPPING BOX\n\n" + filename_name(_fn) + " isn't a mapping box file.");
        return;
    }
    var _bd   = _d.box;
    var _recs = _d.nodes;
    var _wm   = obj_workspace_manager;
    var _bw   = max(40, real(_bd[$ "box_w"] ?? 200));
    var _bh   = max(40, real(_bd[$ "box_h"] ?? 150));
    var _bx   = round((_wm.cam_x + 960 * _wm.cam_zoom - _bw * 0.5) / 20) * 20;
    var _by   = round((_wm.cam_y + 540 * _wm.cam_zoom - _bh * 0.5) / 20) * 20;

    // Pass 1: create every node with a fresh stable_uid / org_uid
    var _n_recs  = array_length(_recs);
    var _made    = array_create(_n_recs, noone);
    var _uid_map = {};
    var _org_map = {};
    for (var _i = 0; _i < _n_recs; _i++) {
        var _r = _recs[_i];
        if (!is_struct(_r) || !is_string(_r[$ "type"]) || !is_array(_r[$ "code"])) continue;
        if (_r.type == "EXECUTE" || _r.type == "INIT") continue;
        if (!variable_struct_exists(_r, "title"))     _r.title     = _r.type;
        if (!variable_struct_exists(_r, "connected")) _r.connected = false;
        var _old_uid = real(_r[$ "stable_uid"] ?? -1);
        _r.stable_uid = -1;   // keep the uid Create just handed out
        _r.x = real(_r[$ "x"] ?? 0) + _bx;
        _r.y = real(_r[$ "y"] ?? 0) + _by;
        var _n = scr_node_from_record(_r, -1);
        _made[_i] = _n;
        if (_old_uid > 0) _uid_map[$ string(_old_uid)] = _n.stable_uid;
        if (_n.node_type == "ORG") {
            _n.org_uid = global.next_org_uid++;
            var _old_org = real(_r[$ "org_uid"] ?? -1);
            if (_old_org > 0) _org_map[$ string(_old_org)] = _n.org_uid;
        }
    }

    // Pass 2: parents by index, wires through the uid map. Anything that was
    // on a spine outside the box comes in floating.
    var _old_uids = variable_struct_get_names(_uid_map);
    for (var _i = 0; _i < _n_recs; _i++) {
        var _n = _made[_i];
        if (_n == noone) continue;
        var _r = _recs[_i];
        // Generated labels carry their node's stable_uid (sng<uid>_play,
        // hud<uid>_...). Point references inside the box at the new uids.
        for (var _a = 0; _a < array_length(_n.instructions); _a++) {
            if (!is_array(_n.instructions[_a])) continue;
            for (var _b = 0; _b < array_length(_n.instructions[_a]); _b++) {
                var _s = _n.instructions[_a][_b];
                if (!is_string(_s)) continue;
                // Via placeholders, so an old uid that equals another's new
                // uid can't be renamed twice.
                for (var _u = 0; _u < array_length(_old_uids); _u++) {
                    var _tok = chr(1) + string(_u) + chr(1);
                    _s = string_replace_all(_s, "sng" + _old_uids[_u] + "_", "sng" + _tok + "_");
                    _s = string_replace_all(_s, "hud" + _old_uids[_u] + "_", "hud" + _tok + "_");
                }
                for (var _u = 0; _u < array_length(_old_uids); _u++) {
                    _s = string_replace_all(_s, chr(1) + string(_u) + chr(1), string(_uid_map[$ _old_uids[_u]]));
                }
                _n.instructions[_a][_b] = _s;
            }
        }
        if (_n.node_type == "ORG") {
            var _wi = _org_map[$ string(_r[$ "wire_in_source"] ?? -1)];
            var _wo = _org_map[$ string(_r[$ "wire_out_target"] ?? -1)];
            _n.wire_in_source  = is_undefined(_wi) ? -1 : _wi;
            _n.wire_out_target = is_undefined(_wo) ? -1 : _wo;
        } else {
            var _p = real(_r[$ "parent_idx"] ?? -1);
            if (_p >= 0 && _p < _n_recs && _made[_p] != noone && _made[_p].node_type == "ORG") {
                _n.org_parent   = _made[_p];
                _n.is_connected = true;
            } else {
                _n.org_parent   = noone;
                _n.is_connected = false;
            }
        }
        if (_n.node_type == "LABEL" && array_length(_n.instructions) > 0 && array_length(_n.instructions[0]) > 1) {
            var _lbl = string(_n.instructions[0][1]);
            if (_lbl != "") _n.instructions[0][1] = scr_make_unique_node_name(_lbl, _n);
        }
        // Variables register the way project load does
        if (_n.node_type == "NAMED_LOC" && array_length(_n.instructions) > 0 && array_length(_n.instructions[0]) > 1) {
            var _vn = string(_n.instructions[0][1]);
            if (_vn != "" && _vn != "< NO NAME >" && string_pos("HW_", _vn) != 1 && scr_nloc_find_meta(_vn) == undefined) {
                var _enc = (array_length(_n.instructions[0]) > 2) ? string(_n.instructions[0][2]) : "byte";
                var _sz  = (_enc == "word" || _enc == "bcd2") ? 2 : ((_enc == "bcd" || _enc == "bcd3") ? 3 : 1);
                array_push(global.named_loc_meta, { name: _vn, type: "UV", addr: _n.pc_address,
                    size: _sz, encoding: _enc, chip: "" });
                global.named_loc_meta_dirty = true;
                ds_map_replace(global.named_loc_map, string_upper(_vn), -1);
            }
        }
        _n.is_dragging = false;
    }

    // Stack each imported ORG's children under it, as load does
    for (var _i = 0; _i < _n_recs; _i++) {
        var _org = _made[_i];
        if (_org == noone || _org.node_type != "ORG") continue;
        var _kids = [];
        with (obj_c64_node) { if (org_parent == _org && is_connected) array_push(_kids, id); }
        array_sort(_kids, function(_a, _b) { return _a.y - _b.y; });
        var _sy = _org.y + _org.height;
        for (var _k = 0; _k < array_length(_kids); _k++) {
            _kids[_k].y = _sy;
            _sy += _kids[_k].height;
        }
    }

    // The box itself, named uniquely the way the box popup's CONFIRM does
    var _name = string(_bd[$ "box_name"] ?? "BOX");
    if (_name == "") _name = "BOX";
    var _dupe = 0;
    with (obj_mapping_box) { if (string_lower(box_name) == string_lower(_name)) _dupe++; }
    if (_dupe > 0) _name += "_" + string(_dupe);
    var _box = instance_create_layer(_bx, _by, "Layer_Boxes", obj_mapping_box);
    _box.box_w       = _bw;
    _box.box_h       = _bh;
    _box.box_name    = _name;
    _box.box_col_idx = clamp(real(_bd[$ "box_col_idx"] ?? 0), 0, 15);
    _box.is_panel    = (_bd[$ "is_panel"] == true);
    _box.panel_links = [];
    if (is_array(_bd[$ "panel_links"])) {
        for (var _i = 0; _i < array_length(_bd.panel_links); _i++) {
            var _nu = _uid_map[$ string(_bd.panel_links[_i])];
            if (!is_undefined(_nu)) array_push(_box.panel_links, _nu);
        }
    }

    var _count = 0;
    for (var _i = 0; _i < _n_recs; _i++) if (_made[_i] != noone) _count++;
    global.addresses_dirty = true;
    scr_c64_do_update_addresses();
    global.relayout_frames = 2;
    with (obj_workspace_manager) { alarm[1] = 6; }
    global.undo_dirty     = true;
    global.autosave_dirty = true;
    scr_show_message("IMPORT MAPPING BOX\n\nAdded '" + _name + "' with " + string(_count) + " node(s).");
}
