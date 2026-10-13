/// scr_panel_help - HELP GUIDE button in every asset editor's header.
///
/// The guide needs no per-editor step lists. While it runs, the skin helpers
/// (scr_editor_control, recessed scr_editor_panel, scr_editor_label) report
/// every rect they draw. The guide then parks a virtual pointer on each
/// control in turn for one frame: the editor draws it hovered and its own
/// scr_ui_info() call fills global.ui_info with what that control does. Those
/// INFO texts become the steps, in draw order, one per distinct text
/// (a palette of 16 swatches sharing one text is one step).
///
/// Two tours per panel, from two title-bar buttons:
///   WORKFLOW   - hand-written steps (scr_panel_help_workflow) on how the panel
///              is used, start to finish. Each step names the controls it is
///              about by their on-screen label; the guide finds them in what
///              the editor drew.
///   HELP GUIDE - every control, in draw order, explained by its INFO text.
///
/// Phases: "arm"     (clicked mid-frame: wait for one whole frame)
///         "collect" (one frame, pointer parked off screen, rects recorded)
///         "scan"    (complete tour: one candidate per frame, texts recorded)
///         "show"    (the user steps through with NEXT / BACK)
///
/// While active, obj_asset_manager Step reads the real mouse and keys for
/// the guide, then clears input so the editor underneath never acts on it.

global.ph_active  = false;
global.ph_capture = false;
global.ph_phase   = "";
global.ph_rects   = [];
global.ph_labels  = [];
global.ph_cands   = [];
global.ph_texts   = [];
global.ph_steps   = [];
global.ph_step    = 0;
global.ph_scan_i  = 0;
global.ph_vm_idx  = -1;
global.ph_vmx     = -10000;
global.ph_vmy     = -10000;
global.ph_real_mx = 0;
global.ph_real_my = 0;
global.ph_click   = false;
global.ph_key     = "";
global.ph_kbstr   = "";
global.ph_asset   = undefined;
global.ph_view    = [0, 0, 0, 0];
global.ph_skip    = [0, 0, 0, 0];
global.ph_surf    = -1;
global.ph_snap_rects  = [];
global.ph_snap_labels = [];
global.ph_kind    = "";

/// @desc Start the guide for the asset open in the viewer. _view is the
///       viewer rect; _skip is the HELP button rect (left out of the steps).
function scr_panel_help_start(_asset, _view, _skip, _kind = "COMPLETE") {
    global.ph_active = true;
    // The click arrives part-way through a frame, after the editor has
    // already drawn (and not reported) its controls: start capturing on the
    // next whole frame, or the guide would be built from nothing.
    global.ph_phase  = "arm";
    global.ph_kind   = _kind;
    global.ph_asset  = _asset;
    global.ph_view   = _view;
    global.ph_skip   = _skip;
    global.ph_cands  = [];
    global.ph_texts  = [];
    global.ph_steps  = [];
    global.ph_step   = 0;
    global.ph_scan_i = 0;
    global.ph_vm_idx = -1;
    global.ph_vmx    = -10000;
    global.ph_vmy    = -10000;
    global.ph_kbstr  = keyboard_string;
}

function scr_panel_help_end() {
    global.ph_active  = false;
    global.ph_capture = false;
    global.ph_phase   = "";
    global.ph_asset   = undefined;
    global.ph_cands   = [];
    global.ph_steps   = [];
    if (surface_exists(global.ph_surf)) surface_free(global.ph_surf);
    global.ph_surf = -1;
}

/// @desc obj_asset_manager Step, first thing: take the real input for the
///       guide, hand the editor the virtual pointer, then clear input.
function scr_panel_help_step_input() {
    if (!global.ph_active) return;
    global.ph_real_mx = global.gui_mouse_x;
    global.ph_real_my = global.gui_mouse_y;
    global.ph_click   = mouse_check_button_pressed(mb_left);
    global.ph_key     = "";
    if (keyboard_check_pressed(vk_escape)) global.ph_key = "ESC";
    else if (keyboard_check_pressed(vk_right) || keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_space)) global.ph_key = "NEXT";
    else if (keyboard_check_pressed(vk_left) || keyboard_check_pressed(vk_backspace)) global.ph_key = "BACK";
    io_clear();
    keyboard_string = global.ph_kbstr;
    global.gui_mouse_x = global.ph_vmx;
    global.gui_mouse_y = global.ph_vmy;
}

/// @desc obj_asset_manager Draw GUI, as the viewer starts drawing.
function scr_panel_help_frame_begin() {
    global.ph_capture = global.ph_active;
    if (global.ph_active && global.ph_phase == "arm") global.ph_phase = "collect";
    if (global.ph_capture) {
        global.ph_rects  = [];
        global.ph_labels = [];
    }
}

/// @desc Skin helpers report each rect they draw while the guide runs.
function scr_panel_help_capture(_x1, _y1, _x2, _y2, _kind = "") {
    array_push(global.ph_rects, [_x1, _y1, _x2, _y2, _kind]);
}

/// @desc The rects a candidate stands for: a colour palette (run of touching
///       swatches) is one candidate holding every swatch in it.
function scr_panel_help_cand_rects(_c) {
    if (array_length(_c) > 5 && is_array(_c[5])) return _c[5];
    return [_c];
}

function scr_panel_help_capture_label(_x1, _y1, _x2, _y2, _text) {
    array_push(global.ph_labels, [_x1, _y1, _x2, _y2, string(_text)]);
}

/// @desc Candidate controls from this frame's rects: inside the viewer, not
///       the HELP button, not tiny, no duplicates, and no container whose
///       centre already falls on a control inside it. Title-bar controls go
///       last so the guide ends on SAVE / CLOSE.
function scr_panel_help_collect() {
    var _v = global.ph_view;
    var _s = global.ph_skip;
    var _all = [];
    for (var _i = 0; _i < array_length(global.ph_rects); _i++) {
        var _r = global.ph_rects[_i];
        if (_r[2] - _r[0] < 6 || _r[3] - _r[1] < 6) continue;
        if (_r[0] < _v[0] || _r[1] < _v[1] || _r[2] > _v[2] || _r[3] > _v[3]) continue;
        if (_r[0] >= _s[0] && _r[1] >= _s[1] && _r[2] <= _s[2] && _r[3] <= _s[3]) continue;
        // The editor's own outer panel and full-width bands are backdrops.
        if (_r[2] - _r[0] >= (_v[2] - _v[0]) - 4 && _r[3] - _r[1] >= 60) continue;
        var _dup = false;
        for (var _j = 0; _j < array_length(_all); _j++) {
            var _a = _all[_j];
            if (_a[0] == _r[0] && _a[1] == _r[1] && _a[2] == _r[2] && _a[3] == _r[3]) { _dup = true; break; }
        }
        if (!_dup) array_push(_all, _r);
    }
    var _body = [];
    var _head = [];
    for (var _i = 0; _i < array_length(_all); _i++) {
        var _r = _all[_i];
        var _cx = (_r[0] + _r[2]) * 0.5;
        var _cy = (_r[1] + _r[3]) * 0.5;
        var _container = false;
        for (var _j = 0; _j < array_length(_all); _j++) {
            if (_j == _i) continue;
            var _o = _all[_j];
            if (_o[0] >= _r[0] && _o[1] >= _r[1] && _o[2] <= _r[2] && _o[3] <= _r[3]
            && _cx >= _o[0] && _cx <= _o[2] && _cy >= _o[1] && _cy <= _o[3]) { _container = true; break; }
        }
        if (_container) continue;
        if (_r[3] <= _v[1] + 30) array_push(_head, _r); else array_push(_body, _r);
    }
    for (var _i = 0; _i < array_length(_head); _i++) array_push(_body, _head[_i]);
    // A guide over a few hundred grid cells would take seconds to prepare;
    // the first cells of a grid already describe it.
    // Runs of touching swatches (a palette) become one candidate, so the
    // tour explains choosing a colour once instead of once per colour.
    var _grouped = [];
    for (var _i = 0; _i < array_length(_body); _i++) {
        var _r = _body[_i];
        var _is_sw = (array_length(_r) > 4 && _r[4] == "swatch");
        var _ng = array_length(_grouped);
        if (_is_sw && _ng > 0) {
            var _g = _grouped[_ng - 1];
            if (array_length(_g) > 5 && is_array(_g[5])) {
                var _last = _g[5][array_length(_g[5]) - 1];
                var _near_x = (_r[0] <= _last[2] + 8 && _r[2] >= _last[0] - 8);
                var _near_y = (_r[1] <= _last[3] + 8 && _r[3] >= _last[1] - 8);
                if (_near_x && _near_y) { array_push(_g[5], _r); continue; }
            }
        }
        if (_is_sw) array_push(_grouped, [_r[0], _r[1], _r[2], _r[3], "swatch", [_r]]);
        else array_push(_grouped, _r);
    }
    _body = _grouped;
    if (array_length(_body) > 240) array_resize(_body, 240);
    global.ph_cands = _body;
    global.ph_texts = array_create(array_length(_body), "");
}

/// @desc Label drawn inside rect _r, if any (the control's caption).
function scr_panel_help_label_for(_r) {
    for (var _i = 0; _i < array_length(global.ph_labels); _i++) {
        var _l = global.ph_labels[_i];
        var _lx = (_l[0] + _l[2]) * 0.5;
        var _ly = (_l[1] + _l[3]) * 0.5;
        if (_l[0] == _l[2]) _lx = _l[0];
        if (_lx >= _r[0] && _lx <= _r[2] && _ly >= _r[1] && _ly <= _r[3] && string_trim(_l[4]) != "") return string_trim(_l[4]);
    }
    return "";
}

/// @desc Rects for a workflow step's targets, from the collect frame.
///       "IMPORT"   a control whose label reads exactly that (any case)
///       "CLEAN*"   a control whose label starts with that
///       "@LARGEST" the biggest thing drawn (the canvas / main work area)
///       "@PALETTE" the biggest run of touching colour swatches
///       Several targets may be given; every match is highlighted.
function scr_panel_help_resolve(_targets) {
    var _out = [];
    var _v = global.ph_view;
    for (var _ti = 0; _ti < array_length(_targets); _ti++) {
        var _t = string_upper(string_trim(_targets[_ti]));
        if (_t == "") continue;
        if (_t == "@LARGEST") {
            var _best = undefined, _ba = 0;
            for (var _ri = 0; _ri < array_length(global.ph_snap_rects); _ri++) {
                var _r = global.ph_snap_rects[_ri];
                if (_r[0] < _v[0] || _r[1] < _v[1] || _r[2] > _v[2] || _r[3] > _v[3]) continue;
                if (_r[2] - _r[0] >= (_v[2] - _v[0]) - 4) continue;   // the panel itself
                var _a = (_r[2] - _r[0]) * (_r[3] - _r[1]);
                if (_a > _ba) { _ba = _a; _best = _r; }
            }
            if (!is_undefined(_best)) array_push(_out, _best);
            continue;
        }
        if (_t == "@PALETTE") {
            // The biggest run of touching colour swatches (the main palette)
            var _best_g = [], _cur_g = [];
            for (var _ri = 0; _ri <= array_length(global.ph_snap_rects); _ri++) {
                var _r = (_ri < array_length(global.ph_snap_rects)) ? global.ph_snap_rects[_ri] : undefined;
                var _sw = !is_undefined(_r) && array_length(_r) > 4 && _r[4] == "swatch";
                if (_sw && array_length(_cur_g) > 0) {
                    var _lr = _cur_g[array_length(_cur_g) - 1];
                    if (!(_r[0] <= _lr[2] + 8 && _r[2] >= _lr[0] - 8 && _r[1] <= _lr[3] + 8 && _r[3] >= _lr[1] - 8)) {
                        if (array_length(_cur_g) > array_length(_best_g)) _best_g = _cur_g;
                        _cur_g = [];
                    }
                }
                if (_sw) { array_push(_cur_g, _r); continue; }
                if (array_length(_cur_g) > array_length(_best_g)) _best_g = _cur_g;
                _cur_g = [];
            }
            for (var _bi = 0; _bi < array_length(_best_g); _bi++) array_push(_out, _best_g[_bi]);
            continue;
        }
        var _pre = (string_char_at(_t, string_length(_t)) == "*");
        if (_pre) _t = string_copy(_t, 1, string_length(_t) - 1);
        for (var _li = 0; _li < array_length(global.ph_snap_labels); _li++) {
            var _l  = global.ph_snap_labels[_li];
            var _lt = string_upper(string_trim(_l[4]));
            var _hit = _pre ? (string_pos(_t, _lt) == 1) : (_lt == _t);
            if (!_hit) continue;
            // The control the label sits in (smallest rect holding its centre)
            var _lx = (_l[0] == _l[2]) ? _l[0] + 2 : (_l[0] + _l[2]) * 0.5;
            var _ly = (_l[1] + _l[3]) * 0.5;
            var _own = undefined, _oa = 1000000000;
            for (var _ri = 0; _ri < array_length(global.ph_snap_rects); _ri++) {
                var _r = global.ph_snap_rects[_ri];
                if (_lx < _r[0] || _lx > _r[2] || _ly < _r[1] || _ly > _r[3]) continue;
                var _a = (_r[2] - _r[0]) * (_r[3] - _r[1]);
                if (_a < _oa) { _oa = _a; _own = _r; }
            }
            if (is_undefined(_own) || _oa > 200000) {
                // A caption with no control round it: highlight the text itself
                var _w = string_width_l(_l[4]);
                var _x1 = (_l[0] == _l[2]) ? _l[0] : _l[0];
                _own = [_x1 - 2, _l[1], max(_l[2], _x1 + _w) + 2, _l[3]];
            }
            var _dup = false;
            for (var _oi = 0; _oi < array_length(_out); _oi++) {
                var _o = _out[_oi];
                if (_o[0] == _own[0] && _o[1] == _own[1] && _o[2] == _own[2] && _o[3] == _own[3]) { _dup = true; break; }
            }
            if (!_dup) array_push(_out, _own);
        }
    }
    return _out;
}

/// @desc WORKFLOW tour: the panel's hand-written steps (scr_panel_help_workflow).
function scr_panel_help_build_workflow(_type, _wf) {
    var _steps = [];
    for (var _i = 0; _i < array_length(_wf); _i++) {
        var _w = _wf[_i];
        var _tg = variable_struct_exists(_w, "targets") ? _w.targets : [];
        array_push(_steps, { title: _w.title, text: _w.text, rects: scr_panel_help_resolve(_tg) });
    }
    array_push(_steps, {
        title : "THAT'S THE WORKFLOW",
        text  : "This panel saves as you work - there is nothing to turn on.\n\nFor every single control, use HELP GUIDE beside WORKFLOW in the title bar. Hovering any control also shows what it does in the INFO strip.",
        rects : []
    });
    global.ph_steps = _steps;
    global.ph_step  = 0;
}

/// @desc One step per distinct INFO text, in the order first met.
function scr_panel_help_build(_type) {
    var _steps = [];
    array_push(_steps, {
        title : string(_type) + " EDITOR",
        text  : "THIS GUIDE WALKS THROUGH EACH PART OF THIS PANEL IN TURN.\n\nNEXT / BACK (OR THE ARROW KEYS) TO MOVE, ESC TO LEAVE THE GUIDE. NOTHING IN THE EDITOR IS CHANGED WHILE IT RUNS.",
        rects : []
    });
    var _seen = {};
    for (var _i = 0; _i < array_length(global.ph_cands); _i++) {
        var _t = global.ph_texts[_i];
        if (_t == "") continue;
        var _cr = scr_panel_help_cand_rects(global.ph_cands[_i]);
        var _is_pal = (array_length(_cr) > 1);
        if (_is_pal) {
            // A whole palette: one step about choosing a colour from it
            _t = "COLOUR CHOICES: CLICK ANY COLOUR HERE TO PICK IT. FOR EXAMPLE, THIS ONE - " + _t;
        }
        if (variable_struct_exists(_seen, _t)) {
            for (var _k = 0; _k < array_length(_cr); _k++) array_push(_steps[_seen[$ _t]].rects, _cr[_k]);
            continue;
        }
        _seen[$ _t] = array_length(_steps);
        array_push(_steps, { title: _is_pal ? "COLOURS" : "", text: _t, rects: _cr });
    }
    for (var _i = 1; _i < array_length(_steps); _i++) {
        var _st = _steps[_i];
        if (array_length(_st.rects) == 1) _st.title = scr_panel_help_label_for(_st.rects[0]);
        if (_st.title == "") _st.title = array_length(_st.rects) > 1 ? "THESE CONTROLS" : "THIS CONTROL";
    }
    array_push(_steps, {
        title : "THAT'S EVERYTHING",
        text  : "EVERY EDITOR SAVES AUTOMATICALLY AS YOU WORK, SO THERE IS NOTHING TO TURN ON.\n\nHOVER ANY CONTROL LATER AND THE INFO STRIP SHOWS WHAT IT DOES. HELP GUIDE RUNS THIS AGAIN.",
        rects : []
    });
    global.ph_steps = _steps;
    global.ph_step  = 0;
}

/// @desc Park the virtual pointer on the current step's first control, so
///       it draws hovered under the spotlight.
function scr_panel_help_park() {
    var _st = global.ph_steps[global.ph_step];
    if (array_length(_st.rects) > 0) {
        var _r = _st.rects[0];
        global.ph_vmx = floor((_r[0] + _r[2]) * 0.5);
        global.ph_vmy = floor((_r[1] + _r[3]) * 0.5);
    } else {
        global.ph_vmx = -10000;
        global.ph_vmy = -10000;
    }
}

/// @desc obj_asset_manager Draw GUI, last thing: advance the phase from what
///       this frame drew, then draw the spotlight and the callout on top.
function scr_panel_help_draw(_asset, _gui_w, _gui_h) {
    global.ph_capture = false;
    if (!global.ph_active) return;
    if (_asset != global.ph_asset) { scr_panel_help_end(); return; }

    if (global.ph_phase == "collect") {
        global.ph_snap_rects  = global.ph_rects;
        global.ph_snap_labels = global.ph_labels;
        scr_panel_help_collect();
        var _wf = scr_panel_help_workflow(_asset.type);
        if (global.ph_kind == "WORKFLOW" && is_array(_wf) && array_length(_wf) > 0) {
            scr_panel_help_build_workflow(_asset.type, _wf);
            global.ph_phase = "show";
            scr_panel_help_park();
        } else {
            global.ph_kind   = "COMPLETE";
            global.ph_phase  = "scan";
            global.ph_scan_i = 0;
            global.ph_vm_idx = -1;
        }
    } else if (global.ph_phase == "scan" && global.ph_vm_idx >= 0) {
        // This frame was drawn with the pointer on candidate ph_vm_idx.
        global.ph_texts[global.ph_vm_idx] = string(global.ui_info);
        global.ph_scan_i = global.ph_vm_idx + 1;
    }
    if (global.ph_phase == "scan") {
        if (global.ph_scan_i < array_length(global.ph_cands)) {
            var _r = global.ph_cands[global.ph_scan_i];
            global.ph_vm_idx = global.ph_scan_i;
            global.ph_vmx = floor((_r[0] + _r[2]) * 0.5);
            global.ph_vmy = floor((_r[1] + _r[3]) * 0.5);
        } else {
            scr_panel_help_build(_asset.type);
            global.ph_phase = "show";
            scr_panel_help_park();
        }
    }

    // ---- spotlight ----
    var _rects = (global.ph_phase == "show") ? global.ph_steps[global.ph_step].rects : [];
    if (!surface_exists(global.ph_surf)
    || surface_get_width(global.ph_surf) != _gui_w || surface_get_height(global.ph_surf) != _gui_h) {
        if (surface_exists(global.ph_surf)) surface_free(global.ph_surf);
        global.ph_surf = surface_create(_gui_w, _gui_h);
    }
    surface_set_target(global.ph_surf);
    draw_clear_alpha(c_black, 0.62);
    gpu_set_blendmode(bm_subtract);
    draw_set_color(c_white);
    draw_set_alpha(1);
    for (var _i = 0; _i < array_length(_rects); _i++) {
        var _r = _rects[_i];
        draw_rectangle(_r[0] - 3, _r[1] - 3, _r[2] + 3, _r[3] + 3, false);
    }
    gpu_set_blendmode(bm_normal);
    surface_reset_target();
    draw_surface(global.ph_surf, 0, 0);

    var _pulse = 0.6 + 0.4 * abs(sin(current_time / 300));
    draw_set_alpha(_pulse);
    draw_set_color(make_color_rgb(255, 196, 80));
    var _bx1 = 100000, _by1 = 100000, _bx2 = -100000, _by2 = -100000;
    for (var _i = 0; _i < array_length(_rects); _i++) {
        var _r = _rects[_i];
        draw_roundrect_ext(_r[0] - 3, _r[1] - 3, _r[2] + 3, _r[3] + 3, 6, 6, true);
        _bx1 = min(_bx1, _r[0] - 3); _by1 = min(_by1, _r[1] - 3);
        _bx2 = max(_bx2, _r[2] + 3); _by2 = max(_by2, _r[3] + 3);
    }
    draw_set_alpha(1);

    // ---- callout ----
    var _cw = 480;
    var _pad = 12;
    draw_set_font_l(fnt_c64_tiny);
    var _title = "";
    var _body  = "";
    var _n     = 0;
    if (global.ph_phase == "show") {
        var _st = global.ph_steps[global.ph_step];
        _n     = array_length(global.ph_steps);
        _title = _st.title;
        _body  = _st.text;
    } else if (global.ph_phase == "arm" || global.ph_phase == "collect") {
        _title = "PREPARING GUIDE";
        _body  = "LOOKING OVER THIS PANEL...";
    } else {
        _title = "PREPARING GUIDE";
        _body  = "LOOKING OVER THIS PANEL... " + string(global.ph_scan_i) + " / " + string(array_length(global.ph_cands));
    }
    var _body_h = string_height_ext_l(_body, 16, _cw - _pad * 2);
    var _ch = _pad + 18 + 8 + _body_h + 12 + 22 + _pad;
    var _v  = global.ph_view;
    var _cx1, _cy1;
    if (array_length(_rects) == 0) {
        _cx1 = floor((_v[0] + _v[2] - _cw) * 0.5);
        _cy1 = floor((_v[1] + _v[3] - _ch) * 0.5);
    } else {
        _cx1 = floor((_bx1 + _bx2 - _cw) * 0.5);
        if (_by2 + 12 + _ch <= _gui_h - 8) _cy1 = _by2 + 12;
        else if (_by1 - 12 - _ch >= 8)    _cy1 = _by1 - 12 - _ch;
        else {
            // No room above or below: beside it, on the wider side.
            _cy1 = floor((_by1 + _by2 - _ch) * 0.5);
            _cx1 = (_bx1 > _gui_w - _bx2) ? _bx1 - 12 - _cw : _bx2 + 12;
        }
    }
    _cx1 = clamp(_cx1, 8, _gui_w - _cw - 8);
    _cy1 = clamp(_cy1, 8, _gui_h - _ch - 8);
    var _cx2 = _cx1 + _cw;
    var _cy2 = _cy1 + _ch;
    scr_editor_panel(_cx1 - 2, _cy1 - 2, _cx2 + 2, _cy2 + 2, true);
    scr_editor_panel(_cx1, _cy1, _cx2, _cy2, false);

    draw_set_color(make_color_rgb(255, 196, 80));
    scr_editor_label(_cx1 + _pad, _cy1 + _pad, _cx2 - _pad, _cy1 + _pad + 18, _title, fa_left, 0);
    if (_n > 0) {
        draw_set_color(make_color_rgb(151, 170, 192));
        scr_editor_label(_cx1 + _pad, _cy1 + _pad, _cx2 - _pad, _cy1 + _pad + 18,
            string(global.ph_step + 1) + " / " + string(_n), fa_right, 0);
    }
    draw_set_color(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_text_ext_l(_cx1 + _pad, _cy1 + _pad + 26, _body, 16, _cw - _pad * 2);

    // ---- buttons ----
    var _mx = global.ph_real_mx;
    var _my = global.ph_real_my;
    var _b_y1 = _cy2 - _pad - 22;
    var _b_y2 = _cy2 - _pad;
    var _act = global.ph_key;

    var _ex_x1 = _cx1 + _pad;
    var _ex_x2 = _ex_x1 + 100;
    var _ex_hov = point_in_rectangle(_mx, _my, _ex_x1, _b_y1, _ex_x2, _b_y2);
    scr_editor_control(_ex_x1, _b_y1, _ex_x2, _b_y2, _ex_hov);
    draw_set_color(c_white);
    scr_editor_label(_ex_x1, _b_y1, _ex_x2, _b_y2, "EXIT GUIDE");
    if (_ex_hov && global.ph_click) _act = "ESC";


    if (global.ph_phase == "show") {
        var _last = (global.ph_step >= _n - 1);
        var _nx_x2 = _cx2 - _pad;
        var _nx_x1 = _nx_x2 - 90;
        var _nx_hov = point_in_rectangle(_mx, _my, _nx_x1, _b_y1, _nx_x2, _b_y2);
        scr_editor_control(_nx_x1, _b_y1, _nx_x2, _b_y2, _nx_hov, true);
        draw_set_color(c_white);
        scr_editor_label(_nx_x1, _b_y1, _nx_x2, _b_y2, _last ? "DONE" : "NEXT >");
        if (_nx_hov && global.ph_click) _act = "NEXT";

        var _bk_x2 = _nx_x1 - 8;
        var _bk_x1 = _bk_x2 - 90;
        var _bk_on = global.ph_step > 0;
        var _bk_hov = _bk_on && point_in_rectangle(_mx, _my, _bk_x1, _b_y1, _bk_x2, _b_y2);
        scr_editor_control(_bk_x1, _b_y1, _bk_x2, _b_y2, _bk_hov, false, _bk_on);
        draw_set_color(_bk_on ? c_white : make_color_rgb(151, 170, 192));
        scr_editor_label(_bk_x1, _b_y1, _bk_x2, _b_y2, "< BACK");
        if (_bk_hov && global.ph_click) _act = "BACK";

        if (_act == "NEXT") {
            if (_last) { scr_panel_help_end(); }
            else { global.ph_step++; scr_panel_help_park(); }
        } else if (_act == "BACK" && _bk_on) {
            global.ph_step--;
            scr_panel_help_park();
        }
    }
    if (_act == "ESC") scr_panel_help_end();
    global.ph_click = false;
    global.ph_key   = "";
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1);
}
