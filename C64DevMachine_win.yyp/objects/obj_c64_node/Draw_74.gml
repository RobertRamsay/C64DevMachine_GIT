scr_perf_node("gui", node_type);
// DRAW GUI BEGIN - event 74. (Draw_72 is Draw BEGIN, room space: the 8 Sep
// move landed there by mistake, so this overlay drew in the wrong space and
// was effectively invisible.) Was Draw GUI. This object sits at a nearer depth than
// obj_workspace_manager, so as a plain Draw GUI event its overlay was painted
// AFTER the menus, menu bar and code panel - on top of them. Draw GUI Begin
// runs for every instance before any Draw GUI event, so the manager's GUI
// (and the asset panel / message boxes) now always paints over this.
if obj_workspace_manager.code_editor_open exit;
// Match room-space drawing: folded children have no GUI overlay either.
if (scr_node_is_hidden(id)) exit;
// Any asset editor (the viewer hosts them all: bitmap, builder, byte data,
// sprites...) and SPRED64 take the whole screen - the zoomed-out node
// overlay must not draw over them. Draw_0 already exits on viewer_open.
if (instance_exists(obj_asset_manager)) {
    if (obj_asset_manager.viewer_open || obj_asset_manager.spred64_open) exit;
}

var _cam_zoom = obj_workspace_manager.cam_zoom;
if (_cam_zoom < 2.0) exit;
if (node_type == "COMMENT" && !global.comments_visible) exit;
// Comment text is only drawn up to zoom 2.5 (Draw_0). No tiny overlay copy
// zoomed out - it was unreadable and just cluttered the map view.
if (node_type == "COMMENT") exit;
if (obj_workspace_manager.is_entering_text) exit;

var _cam_x = obj_workspace_manager.cam_x;
var _cam_y = obj_workspace_manager.cam_y;
var _alpha_comment = clamp((_cam_zoom - 2.5) / 1.5, 0, 1);
// Fades in between zoom 2 and 2.5 (as the room-space boxes fade out) and then
// stays: the camera goes out to 6.0 and the old fade-out past 4.5 left the far
// view with no labels at all.
var _alpha_header  = clamp((_cam_zoom - 2.0) / 0.5, 0, 1);

var _shelf_edge = obj_workspace_manager.shelf_width + 40;
var _sc_edge    = global.sc_x_start - 40;

draw_set_font_l(fnt_c64_nano);
draw_set_halign(fa_center);

// Truncate word-style headers to 8 chars + ".."
function _trunc6(_s) {
    return (string_length(_s) > 12) ? (string_copy(_s, 1, 12) + "..") : _s;
}

if (node_type == "COMMENT") {
    var _wx = x + x_indent + width * 0.5;
    var _wy = y + height * 0.5;
    var _sx = (_wx - _cam_x) / _cam_zoom;
    var _sy = (_wy - _cam_y) / _cam_zoom;
    if (_sx < 0 || _sx > 1920 || _sy < 0 || _sy > 1080) exit;
    if (_sx < _shelf_edge || _sx > _sc_edge) exit;
    var _edge_alpha = clamp((_sx - _shelf_edge) / 30.0, 0, 1)
                    * clamp((_sc_edge - _sx)    / 30.0, 0, 1);
    var _is_editing = (obj_workspace_manager.is_entering_text &&
                       obj_workspace_manager.input_target_node == id &&
                       obj_workspace_manager.input_target_index == 0);
    var _text = _is_editing
                ? obj_workspace_manager.current_input_string
                : ((array_length(instructions) > 0) ? string(instructions[0][1]) : "");
    if (_text == "" && !_is_editing) exit;
    draw_set_font_l(fnt_c64_tiny);
    draw_set_valign(fa_middle);
    draw_set_alpha(_alpha_comment * _edge_alpha * 0.6);
    draw_set_color(c_black);
    draw_text_ext_l(_sx + 1, _sy + 1, comment_display_text, 12, -1);
    draw_set_alpha(_alpha_comment * _edge_alpha);
    draw_set_color(_is_editing ? c_lime : c_yellow);
    draw_text_ext_l(_sx, _sy, comment_display_text, 12, -1);

} else if (string_pos("MACRO", node_type) > 0) {
    var _wx = x + x_indent + width * 0.5;
    var _wy = y + 6;
    var _sx = (_wx - _cam_x) / _cam_zoom;
    var _sy = (_wy - _cam_y) / _cam_zoom;
    if (_sx < 0 || _sx > 1920 || _sy < 0 || _sy > 1080) exit;
    if (_sx < _shelf_edge || _sx > _sc_edge) exit;
    var _edge_alpha = clamp((_sx - _shelf_edge) / 30.0, 0, 1)
                    * clamp((_sc_edge - _sx)    / 30.0, 0, 1);
    draw_set_valign(fa_top);
	draw_set_font_l(fnt_c64_nano);
    draw_set_alpha(_alpha_header * _edge_alpha * 0.8);
    draw_set_color(c_black);

    // custom_title overrides node_title when set
    var _display_text = (custom_title != "") ? custom_title : node_title;
    if (node_type == "MACRO_CODE" && variable_instance_exists(id, "code_descriptor") && custom_title == "") {
        _display_text = code_descriptor;
    }
    _display_text = _trunc6(_display_text);

    draw_text_l(_sx + 1, _sy + 7, _display_text);
    draw_set_alpha(_alpha_header * _edge_alpha);
    draw_set_color(c_white);
    draw_text_l(_sx, _sy+8, _display_text);

} else if (node_type == "ORG" || node_type == "INIT") {
    // Start address on the block itself, end address of the whole chain
    // under its bottom-most node. Nothing else from the chain is shown.
    var _wx = x + x_indent + width * 0.5;
    var _sx = (_wx - _cam_x) / _cam_zoom;
    if (_sx < _shelf_edge || _sx > _sc_edge) exit;
    var _edge_alpha = clamp((_sx - _shelf_edge) / 30.0, 0, 1)
                    * clamp((_sc_edge - _sx)    / 30.0, 0, 1);
    draw_set_valign(fa_middle);

    var _org_ref  = id;
    var _is_init  = (node_type == "INIT");
    var _is_vars  = (node_title == "VARIABLES");
    var _end_addr = pc_address + (_is_vars ? 0 : total_node_size);
    var _bottom   = y + height;
    with (obj_c64_node) {
        if (id == _org_ref || scr_node_is_hidden(id)) continue;
        // INIT spine: connected nodes with no ORG parent, packed under INIT
        // (same rule scr_c64_do_update_addresses uses). ORG chain: its children.
        if (_is_init) {
            if (org_parent != noone || node_type == "ORG" || x != _org_ref.x) continue;
        } else if (org_parent != _org_ref) continue;
        if (_is_vars) {
            if (node_type != "NAMED_LOC") continue;
            var _m = scr_nloc_find_meta(string(instructions[0][1]));
            if (_m != undefined) _end_addr += _m.size;
        } else {
            if (!is_connected || node_type == "NAMED_LOC" || node_type == "NEW_STR") continue;
            _end_addr = max(_end_addr, pc_address + total_node_size);
        }
        _bottom = max(_bottom, y + height);
    }

    var _sy_start = (y + height * 0.5 - _cam_y) / _cam_zoom;
    var _sy_end   = (_bottom - _cam_y) / _cam_zoom + 8;
    var _labels   = [[_sy_start, pc_address, ""], [_sy_end, _end_addr, ">"]];
    // HW REGISTERS is just a list of fixed addresses - no chain end to show.
    var _count    = (node_title == "HW REGISTERS") ? 1 : 2;
    for (var _i = 0; _i < _count; _i++) {
        var _ly = _labels[_i][0];
        if (_ly < 0 || _ly > 1080) continue;
        var _h = decimal_to_hex(_labels[_i][1]);
        while (string_length(_h) < 4) _h = "0" + _h;
        var _display = _labels[_i][2] + "$" + string_upper(_h);
        draw_set_alpha(_alpha_header * _edge_alpha * 0.6); draw_set_color(c_black); draw_text_l(_sx+1, _ly+1, _display);
        draw_set_alpha(_alpha_header * _edge_alpha);       draw_set_color(c_aqua);  draw_text_l(_sx, _ly, _display);
    }

} else {
    var _wx = x + x_indent + width * 0.5;
    var _wy = y + height * 0.5;
    var _sx = (_wx - _cam_x) / _cam_zoom;
    var _sy = (_wy - _cam_y) / _cam_zoom;
    if (_sx < 0 || _sx > 1920 || _sy < 0 || _sy > 1080) exit;
    if (_sx < _shelf_edge || _sx > _sc_edge) exit;
    var _edge_alpha = clamp((_sx - _shelf_edge) / 30.0, 0, 1)
                    * clamp((_sc_edge - _sx)    / 30.0, 0, 1);
    draw_set_valign(fa_middle);

    var _display = "";
    switch (node_type) {
        case "NAMED_LOC": {
            _display = (array_length(instructions) > 0) ? string(instructions[0][1]) : "";
            if (_display == "") break;
            _display = _trunc6(_display);
            draw_set_alpha(_alpha_header * _edge_alpha * 0.6); draw_set_color(c_black); draw_text_l(_sx+1, _sy+1, _display);
            draw_set_alpha(_alpha_header * _edge_alpha);       draw_set_color(c_lime);  draw_text_l(_sx, _sy, _display);
        } break;

        case "LABEL": {
            _display = (array_length(instructions) > 0) ? string(instructions[0][1]) : node_title;
            _display = _trunc6(_display);
            draw_set_alpha(_alpha_header * _edge_alpha * 0.6); draw_set_color(c_black);  draw_text_l(_sx+1, _sy+1, _display);
            draw_set_alpha(_alpha_header * _edge_alpha);       draw_set_color(c_yellow); draw_text_l(_sx, _sy, _display);
        } break;

        case "GET_VAR":
        case "SET_VAR":
        case "INC_VAR":
        case "DEC_VAR":
        case "COPY_VAR": {
            // var_op nodes — show the variable name (slot 1), not the "var_op" mnemonic
            _display = (array_length(instructions) > 0 && array_length(instructions[0]) > 1)
                       ? string(instructions[0][1]) : node_type;
            if (string_pos("UV_", _display) == 1) _display = string_delete(_display, 1, 3);
            _display = _trunc6(_display);
            draw_set_alpha(_alpha_header * _edge_alpha * 0.6); draw_set_color(c_black);  draw_text_l(_sx+1, _sy+1, _display);
            draw_set_alpha(_alpha_header * _edge_alpha);       draw_set_color(c_aqua);   draw_text_l(_sx, _sy, _display);
        } break;

        case "NORMAL":
        default: {
            // Zoomed out the map is kept as plain as possible: of the ordinary
            // instructions only a JSR / JMP to a label is shown - those are the
            // jumps between the labels you can see. No operand values.
            if (array_length(instructions) == 0 || array_length(instructions[0]) < 2) break;
            var _inst_l = string_lower(string(instructions[0][0]));
            var _raw    = instructions[0][1];
            var _is_jump = (string_pos("jsr", _inst_l) == 1 || string_pos("jmp", _inst_l) == 1);
            if (!_is_jump || is_real(_raw) || string(_raw) == "") break;
            var _mn_str  = string_upper(string_copy(_inst_l, 1, 3)) + " ";
            var _val_str = _trunc6(string(_raw));
            var _mn_w    = string_width_l(_mn_str);
            var _total_w = string_width_l(_mn_str + _val_str);
            draw_set_alpha(_alpha_header * _edge_alpha * 0.6);
            draw_set_color(c_black);
            draw_text_l(_sx + 1, _sy + 1, _mn_str + _val_str);
            draw_set_alpha(_alpha_header * _edge_alpha);
            draw_set_halign(fa_left);
            draw_set_color(c_ltgray);
            draw_text_l(_sx - _total_w * 0.5, _sy, _mn_str);
            draw_set_color(c_yellow);
            draw_text_l(_sx - _total_w * 0.5 + _mn_w, _sy, _val_str);
            draw_set_halign(fa_center);
        } break;
    }
}


draw_set_alpha(1.0);
draw_set_halign(fa_left);
draw_set_valign(fa_top);