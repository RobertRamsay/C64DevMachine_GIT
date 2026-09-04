if obj_workspace_manager.code_editor_open exit;

var _cam_zoom = obj_workspace_manager.cam_zoom;
if (_cam_zoom < 2.0) exit;
if (node_type == "COMMENT" && !global.comments_visible) exit;
if (obj_workspace_manager.is_entering_text) exit;

var _cam_x = obj_workspace_manager.cam_x;
var _cam_y = obj_workspace_manager.cam_y;
var _alpha_comment = clamp((_cam_zoom - 2.5) / 1.5, 0, 1);
var _alpha_header  = clamp((_cam_zoom - 2.0) / 1.0, 0, 1)
                   * clamp(1.0 - (_cam_zoom - 4.5) / 1.0, 0, 1);

var _shelf_edge = obj_workspace_manager.shelf_width + 40;
var _sc_edge    = global.sc_x_start - 40;

draw_set_font(fnt_c64_nano);
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
                       obj_workspace_manager.input_target_node == id);
    var _text = _is_editing
                ? obj_workspace_manager.current_input_string
                : ((array_length(instructions) > 0) ? string(instructions[0][1]) : "");
    if (_text == "" && !_is_editing) exit;
    draw_set_font(fnt_c64_tiny);
    draw_set_valign(fa_middle);
    draw_set_alpha(_alpha_comment * _edge_alpha * 0.6);
    draw_set_color(c_black);
    draw_text_ext(_sx + 1, _sy + 1, comment_display_text, 12, -1);
    draw_set_alpha(_alpha_comment * _edge_alpha);
    draw_set_color(_is_editing ? c_lime : c_yellow);
    draw_text_ext(_sx, _sy, comment_display_text, 12, -1);

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
	draw_set_font(fnt_c64_nano);
    draw_set_alpha(_alpha_header * _edge_alpha * 0.8);
    draw_set_color(c_black);

    // custom_title overrides node_title when set
    var _display_text = (custom_title != "") ? custom_title : node_title;
    if (node_type == "MACRO_CODE" && variable_instance_exists(id, "code_descriptor") && custom_title == "") {
        _display_text = code_descriptor;
    }
    _display_text = _trunc6(_display_text);

    draw_text(_sx + 1, _sy + 7, _display_text);
    draw_set_alpha(_alpha_header * _edge_alpha);
    draw_set_color(c_white);
    draw_text(_sx, _sy+8, _display_text);

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
            draw_set_alpha(_alpha_header * _edge_alpha * 0.6); draw_set_color(c_black); draw_text(_sx+1, _sy+1, _display);
            draw_set_alpha(_alpha_header * _edge_alpha);       draw_set_color(c_lime);  draw_text(_sx, _sy, _display);
        } break;

        case "LABEL": {
            _display = (array_length(instructions) > 0) ? string(instructions[0][1]) : node_title;
            _display = _trunc6(_display);
            draw_set_alpha(_alpha_header * _edge_alpha * 0.6); draw_set_color(c_black);  draw_text(_sx+1, _sy+1, _display);
            draw_set_alpha(_alpha_header * _edge_alpha);       draw_set_color(c_yellow); draw_text(_sx, _sy, _display);
        } break;

        case "ORG":
        case "INIT": {
            var _h = decimal_to_hex(pc_address);
            while (string_length(_h) < 4) _h = "0" + _h;
            _display = "$" + string_upper(_h);
            draw_set_alpha(_alpha_header * _edge_alpha * 0.6); draw_set_color(c_black); draw_text(_sx+1, _sy+1, _display);
            draw_set_alpha(_alpha_header * _edge_alpha);       draw_set_color(c_aqua);  draw_text(_sx, _sy, _display);
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
            draw_set_alpha(_alpha_header * _edge_alpha * 0.6); draw_set_color(c_black);  draw_text(_sx+1, _sy+1, _display);
            draw_set_alpha(_alpha_header * _edge_alpha);       draw_set_color(c_aqua);   draw_text(_sx, _sy, _display);
        } break;

        case "NORMAL":
        default: {
            if (array_length(instructions) > 0) {
                var _mn     = string_upper(string(instructions[0][0]));
                var _raw    = (array_length(instructions[0]) > 1) ? instructions[0][1] : "";
                var _val    = "";
                if (global.use_hex_display && is_real(_raw)) {
                    var _h      = decimal_to_hex(_raw);
                    var _inst_l = string_lower(string(instructions[0][0]));
                    var _is_16bit = (string_pos("_abs", _inst_l) > 0 || string_pos("_abx", _inst_l) > 0 ||
                                     string_pos("_aby", _inst_l) > 0 || string_pos("_ind", _inst_l) > 0);
                    var _pad = _is_16bit ? 4 : 2;
                    while (string_length(_h) < _pad) _h = "0" + _h;
                    _val = "$" + string_upper(_h);
                } else {
                    _val = string(_raw);
                }
                var _mn_str  = _mn + " ";
                var _val_str = _val;
                var _mn_w    = string_width(_mn_str);
                var _total_w = string_width(_mn_str + _val_str);
                draw_set_alpha(_alpha_header * _edge_alpha * 0.6);
                draw_set_color(c_black);
                draw_text(_sx + 1, _sy + 1, _mn_str + _val_str);
                draw_set_alpha(_alpha_header * _edge_alpha);
                draw_set_halign(fa_left);
                draw_set_color(c_ltgray);
                draw_text(_sx - _total_w * 0.5, _sy, _mn_str);
                draw_set_color(c_yellow);
                draw_text(_sx - _total_w * 0.5 + _mn_w, _sy, _val_str);
                draw_set_halign(fa_center);
            } else {
                _display = (custom_title != "") ? custom_title : node_title;
                _display = _trunc6(_display);
                draw_set_alpha(_alpha_header * _edge_alpha * 0.6); draw_set_color(c_black);  draw_text(_sx+1, _sy+1, _display);
                draw_set_alpha(_alpha_header * _edge_alpha);       draw_set_color(c_ltgray); draw_text(_sx, _sy, _display);
            }
        } break;
    }
}


draw_set_alpha(1.0);
draw_set_halign(fa_left);
draw_set_valign(fa_top);