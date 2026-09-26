/// @desc Spotlight + caption panel.
/// Draw GUI End: runs after every object's Draw GUI, so the overlay sits on
/// top of the workspace, the asset panel and the editors whatever their depth.

panel_vis = false;

// Earlier GUI drawers (asset editors especially) can leave a scissor rect,
// alpha, blend mode or shader behind. Start from a clean state so the
// overlay is never clipped away or drawn invisible.
shader_reset();
gpu_set_blendmode(bm_normal);
gpu_set_scissor(0, 0, window_get_width(), window_get_height());
draw_set_alpha(1);
draw_set_color(c_white);
draw_set_halign(fa_left);
draw_set_valign(fa_top);

if (!debug_drawn) {
    debug_drawn = true;
    show_debug_message("TOUR: first draw, step " + string(step_idx) + " of " + string(array_length(steps)));
}

if (step_idx < 0 || step_idx >= array_length(steps)) {
    exit;
}
// Stay out of the way of modal dialogs.
if (instance_exists(obj_message_box) || instance_exists(obj_question_box) || instance_exists(obj_integer_box)) {
    if ((global.tour_frame mod 120) == 1) {
        show_debug_message("TOUR: hidden by dialog  msg=" + string(instance_number(obj_message_box))
            + " q=" + string(instance_number(obj_question_box)) + " int=" + string(instance_number(obj_integer_box)));
    }
    exit;
}

var _step  = steps[step_idx];
var _gw    = global.gui_w;
var _gh    = display_get_gui_height();
var _pulse = 0.5 + 0.5 * sin(current_time * 0.006);

// ---------------------------------------------------------------
// HIGHLIGHT
// ---------------------------------------------------------------
var _r = scr_tour_resolve_rect();
if (is_undefined(_r)) {
    hl_have = false;
} else {
    var _pad = 6;
    var _tx1 = _r[0] - _pad;
    var _ty1 = _r[1] - _pad;
    var _tx2 = _r[2] + _pad;
    var _ty2 = _r[3] + _pad;
    if (!hl_have) {
        hl_x1 = _tx1;
        hl_y1 = _ty1;
        hl_x2 = _tx2;
        hl_y2 = _ty2;
        hl_have = true;
    } else {
        hl_x1 = lerp(hl_x1, _tx1, 0.35);
        hl_y1 = lerp(hl_y1, _ty1, 0.35);
        hl_x2 = lerp(hl_x2, _tx2, 0.35);
        hl_y2 = lerp(hl_y2, _ty2, 0.35);
    }
}

if (hl_have) {
    // Dim everything except the target
    draw_set_color(c_black);
    draw_set_alpha(0.35);
    draw_rectangle(0, 0, _gw, hl_y1, false);
    draw_rectangle(0, hl_y2, _gw, _gh, false);
    draw_rectangle(0, hl_y1, hl_x1, hl_y2, false);
    draw_rectangle(hl_x2, hl_y1, _gw, hl_y2, false);

    // Pulsing frame
    var _grow = 2 + (_pulse * 4);
    draw_set_alpha(0.35 + 0.5 * _pulse);
    draw_set_color(c_yellow);
    draw_rectangle(hl_x1 - _grow, hl_y1 - _grow, hl_x2 + _grow, hl_y2 + _grow, true);
    draw_set_alpha(1);
    draw_rectangle(hl_x1, hl_y1, hl_x2, hl_y2, true);
    draw_rectangle(hl_x1 + 1, hl_y1 + 1, hl_x2 - 1, hl_y2 - 1, true);
}

// ---------------------------------------------------------------
// CAPTION PANEL
// ---------------------------------------------------------------
var _pw   = 460;
var _in_w = _pw - 40;

draw_set_font_l(fnt_c64_code);
var _text_h = string_height_ext_l(_step.text, 16, _in_w);
var _ph     = 70 + _text_h + 44;

// Centre it over the workspace, between the palette and the asset panel.
var _left = 0;
if (!obj_workspace_manager.expert_mode) {
    _left = obj_workspace_manager.shelf_width + 40;
}
var _right = _gw;
if (instance_exists(obj_asset_manager)) {
    _right = obj_asset_manager.panel_x - 20;
}
var _px = floor(((_left + _right) * 0.5) - (_pw * 0.5));
var _py = _gh - 70 - _ph;

// Jump to the top if it would cover the target.
if (hl_have) {
    if (hl_x2 > _px && hl_x1 < _px + _pw && hl_y2 > _py && hl_y1 < _py + _ph) {
        _py = 90;
    }
}

// TEMP diagnostics: heartbeat every 2 seconds with where the panel is going.
if ((global.tour_frame mod 120) == 1) {
    show_debug_message("TOUR: alive step " + string(step_idx)
        + " panel " + string(_px) + "," + string(_py) + " size " + string(_pw) + "x" + string(_ph)
        + " gui " + string(_gw) + "x" + string(_gh)
        + " win " + string(window_get_width()) + "x" + string(window_get_height())
        + " surf " + string(surface_get_target()));
}

panel_x1  = _px;
panel_y1  = _py;
panel_x2  = _px + _pw;
panel_y2  = _py + _ph;
panel_vis = true;

// Connector from the panel to the target
if (hl_have) {
    var _cx  = (hl_x1 + hl_x2) * 0.5;
    var _cy  = (hl_y1 + hl_y2) * 0.5;
    var _ax  = clamp(_cx, _px + 20, _px + _pw - 20);
    var _ay  = _py;
    if (_cy > _py + _ph) {
        _ay = _py + _ph;
    }
    var _ex = clamp(_cx, hl_x1, hl_x2);
    var _ey = hl_y2;
    if (_cy > _ay) {
        _ey = hl_y1;
    }
    if (_cy >= hl_y1 && _cy <= hl_y2 && (_ay >= hl_y1 && _ay <= hl_y2)) {
        _ey = _cy;
    }
    draw_set_color(c_yellow);
    draw_set_alpha(0.8);
    draw_line_width(_ax, _ay, _ex, _ey, 2);
    draw_circle(_ex, _ey, 4, false);
    draw_set_alpha(1);
}

draw_sprite_stretched(spr_glassSlice, obj_workspace_manager.niceSliceFrm, _px, _py, _pw, _ph);

// Header
draw_set_halign(fa_left);
draw_set_valign(fa_top);
draw_set_font_l(fnt_C64_Angled);
draw_set_color(make_color_rgb(220, 140, 40));
draw_text_l(_px + 20, _py + 16, tour_title);
draw_set_halign(fa_right);
draw_set_color(make_color_rgb(140, 140, 160));
draw_text(_px + _pw - 20, _py + 16, string(step_idx + 1) + " / " + string(array_length(steps)));
draw_set_halign(fa_left);

// Step title (flashes green when done)
var _title_col = c_yellow;
if (done_timer > 0) {
    _title_col = c_lime;
}
draw_set_color(_title_col);
draw_text_l(_px + 20, _py + 38, _step.title);
if (done_timer > 0) {
    draw_set_halign(fa_right);
    draw_text_l(_px + _pw - 20, _py + 38, "DONE!");
    draw_set_halign(fa_left);
}

// Body
draw_set_font_l(fnt_c64_code);
draw_set_color(c_white);
draw_text_ext_l(_px + 20, _py + 62, _step.text, 16, _in_w);

// Progress dots
var _dots  = array_length(steps);
var _dot_x = _px + 20;
var _dot_y = _py + _ph - 22;
for (var _d = 0; _d < _dots; _d++) {
    var _dc = make_color_rgb(70, 70, 90);
    if (_d < step_idx) {
        _dc = make_color_rgb(80, 160, 90);
    }
    if (_d == step_idx) {
        _dc = c_yellow;
    }
    draw_set_color(_dc);
    draw_circle(_dot_x + (_d * 12), _dot_y, 3, false);
}

// Buttons: EXIT  BACK  NEXT/SKIP/FINISH
var _mx     = device_mouse_x_to_gui(0);
var _my     = device_mouse_y_to_gui(0);
var _bw     = 70;
var _bh     = 20;
var _by     = _py + _ph - 32;
var _last   = (step_idx >= array_length(steps) - 1);
var _nlabel = "NEXT";
if (_step.check != "NONE") {
    _nlabel = "SKIP";
}
if (_last) {
    _nlabel = "FINISH";
}

btn_next = [_px + _pw - 20 - _bw, _by, _px + _pw - 20, _by + _bh];
btn_back = [btn_next[0] - 8 - _bw, _by, btn_next[0] - 8, _by + _bh];
btn_exit = [btn_back[0] - 8 - _bw, _by, btn_back[0] - 8, _by + _bh];

var _btns   = [btn_exit, btn_back, btn_next];
var _labels = ["EXIT", "BACK", _nlabel];
draw_set_font_l(fnt_c64_tiny);
draw_set_halign(fa_center);
for (var _b = 0; _b < 3; _b++) {
    var _br  = _btns[_b];
    var _off = (_b == 1 && step_idx == 0);
    var _hov = (!_off && point_in_rectangle(_mx, _my, _br[0], _br[1], _br[2], _br[3]));
    var _bg  = make_color_rgb(40, 40, 60);
    if (_hov) {
        _bg = make_color_rgb(70, 70, 110);
    }
    if (_b == 2 && _step.check == "NONE") {
        _bg = make_color_rgb(40, 110, 60);
        if (_hov) {
            _bg = make_color_rgb(60, 160, 90);
        }
    }
    draw_set_color(_bg);
    draw_rectangle(_br[0], _br[1], _br[2], _br[3], false);
    draw_set_color(make_color_rgb(110, 110, 150));
    draw_rectangle(_br[0], _br[1], _br[2], _br[3], true);
    var _tc = c_white;
    if (_off) {
        _tc = make_color_rgb(90, 90, 90);
    }
    draw_set_color(_tc);
    draw_text_l((_br[0] + _br[2]) * 0.5, _br[1] + 4, _labels[_b]);
}
draw_set_halign(fa_left);
draw_set_color(c_white);
draw_set_alpha(1);
