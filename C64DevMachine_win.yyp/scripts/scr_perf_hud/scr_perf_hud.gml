/// ====================================================================
/// PERF HUD (F11) — where a workspace frame goes.
///
/// Marks are dropped at fixed points of the frame by obj_workspace_manager
/// (Begin Step, End Step, Draw End, Draw GUI, Draw GUI End). Per-type cost
/// is measured by gap: each instrumented Step / Draw event stamps the clock
/// on entry and the time since the previous stamp is credited to whoever
/// stamped before it, so early exits need no matching "end" call.
/// Everything is averaged over one second. With the HUD off every call
/// returns on its first test.
/// ====================================================================

function scr_perf_reset_acc(_p) {
    _p.frames     = 0;
    _p.acc_step   = 0;
    _p.acc_draw   = 0;
    _p.acc_gui    = 0;
    _p.acc_addr   = 0;
    _p.acc_addr_n = 0;
    _p.acc_idle   = 0;
    _p.step_acc   = {};
    _p.step_cnt   = {};
    _p.draw_acc   = {};
    _p.draw_cnt   = {};
    _p.gui_acc    = {};
    _p.gui_cnt    = {};
    _p.nd_acc     = {};
    _p.nd_cnt     = {};
}

function scr_perf_init() {
    if (variable_global_exists("perf") && is_struct(global.perf)) return;
    global.perf = { sec_t0: get_timer(), t_bs: 0, t_dr: 0, t_gui: 0,
                    step_last: "", step_lt: 0, draw_last: "", draw_lt: 0, gui_last: "", gui_lt: 0, nd_last: "", nd_lt: 0,
                    mx: 0, my: 0, show: undefined };
    scr_perf_reset_acc(global.perf);
}

/// F11 toggles. Called first thing in the manager's Begin Step.
function scr_perf_toggle_check() {
    if (!variable_global_exists("perf_on")) global.perf_on = false;
    if (keyboard_check_pressed(vk_f11)) {
        global.perf_on = !global.perf_on;
        global.perf = undefined;
        if (global.perf_on) scr_perf_init();
    }
}

/// Credit the time since the last stamp of this kind ("step" / "draw") to
/// whoever made it, then stamp for _who.
function scr_perf_node(_kind, _who) {
    if (!global.perf_on) return;
    var _t = get_timer();
    var _p = global.perf;
    var _last = _p[$ _kind + "_last"];
    if (_last != "") {
        var _acc = _p[$ _kind + "_acc"];
        var _cnt = _p[$ _kind + "_cnt"];
        _acc[$ _last] = (_acc[$ _last] ?? 0) + (_t - _p[$ _kind + "_lt"]);
        _cnt[$ _last] = (_cnt[$ _last] ?? 0) + 1;
    }
    _p[$ _kind + "_last"] = _who;
    _p[$ _kind + "_lt"]   = _t;
}

function scr_perf_mark(_phase) {
    if (!global.perf_on) return;
    var _t = get_timer();
    var _p = global.perf;
    switch (_phase) {
        case "begin_step":
            // A new frame: roll the one-second window when it is full
            _p.frames++;
            if (global.gui_mouse_x == _p.mx && global.gui_mouse_y == _p.my) _p.acc_idle++;
            _p.mx = global.gui_mouse_x;
            _p.my = global.gui_mouse_y;
            if (_t - _p.sec_t0 >= 1000000) {
                var _f = max(1, _p.frames);
                _p.show = { fps: _p.frames * 1000000 / (_t - _p.sec_t0),
                            step: _p.acc_step / _f / 1000, draw: _p.acc_draw / _f / 1000,
                            gui: _p.acc_gui / _f / 1000, addr_n: _p.acc_addr_n,
                            addr_ms: _p.acc_addr / 1000, still: _p.acc_idle / _f,
                            step_rows: scr_perf_rows(_p.step_acc, _p.step_cnt, _f),
                            draw_rows: scr_perf_rows(_p.draw_acc, _p.draw_cnt, _f),
                            gui_rows: scr_perf_rows(_p.gui_acc, _p.gui_cnt, _f),
                            nd_rows: scr_perf_rows(_p.nd_acc, _p.nd_cnt, _f) };
                scr_perf_reset_acc(_p);
                _p.sec_t0 = _t;
            }
            _p.t_bs = _t;
            break;
        case "end_step":
            scr_perf_node("step", "");
            _p.acc_step += _t - _p.t_bs;
            break;
        case "end_step_done":
            _p.t_dr = _t;
            _p.draw_last = "";
            _p.nd_last   = "";
            break;
        case "draw_end":
            scr_perf_node("draw", "");
            scr_perf_node("nd", "");
            _p.acc_draw += _t - _p.t_dr;
            // GUI phase from here: remaining Draw End events, Draw GUI Begin
            // (every node), Draw GUI, Draw GUI End
            _p.t_gui    = _t;
            _p.gui_last = "(draw end: cards, fx)";
            _p.gui_lt   = _t;
            break;
        case "gui":
            scr_perf_node("gui", "(workspace gui)");
            break;
        case "gui_end":
            scr_perf_node("gui", "");
            _p.acc_gui += _t - _p.t_gui;
            break;
    }
}

/// One full address update (layout + sizing compile) took _us microseconds.
function scr_perf_addr(_t0) {
    if (!global.perf_on) return;
    global.perf.acc_addr   += get_timer() - _t0;
    global.perf.acc_addr_n += 1;
}

/// Per-type rows, most expensive first: {name, ms per frame, calls per frame}.
function scr_perf_rows(_acc, _cnt, _frames) {
    var _rows = [];
    var _names = variable_struct_get_names(_acc);
    for (var _i = 0; _i < array_length(_names); _i++) {
        var _n = _names[_i];
        array_push(_rows, { name: _n, ms: _acc[$ _n] / _frames / 1000, n: (_cnt[$ _n] ?? 0) / _frames });
    }
    array_sort(_rows, function(_a, _b) { return (_b.ms > _a.ms) ? 1 : ((_b.ms < _a.ms) ? -1 : 0); });
    return _rows;
}

function scr_perf_draw() {
    if (!global.perf_on || !is_struct(global.perf)) return;
    var _s = global.perf.show;
    var _lines = ["PERF HUD (F11)  measuring..."];
    if (is_struct(_s)) {
        _lines = [
            "PERF HUD (F11)   FPS " + string_format(_s.fps, 1, 1)
                + "   mouse still " + string(round(_s.still * 100)) + "% of frames",
            "STEP " + string_format(_s.step, 1, 2) + " ms   DRAW " + string_format(_s.draw, 1, 2)
                + " ms   GUI " + string_format(_s.gui, 1, 2) + " ms   (per frame)",
            "ADDRESS UPDATES " + string(_s.addr_n) + " /s   " + string_format(_s.addr_ms, 1, 1) + " ms /s",
            "", "STEP by type      ms/frame  calls"
        ];
        for (var _i = 0; _i < min(6, array_length(_s.step_rows)); _i++) {
            var _r = _s.step_rows[_i];
            array_push(_lines, "  " + string_copy(_r.name + "                    ", 1, 18)
                + string_format(_r.ms, 3, 2) + "   " + string(round(_r.n)));
        }
        array_push(_lines, "", "DRAW by type      ms/frame  calls");
        for (var _i = 0; _i < min(6, array_length(_s.draw_rows)); _i++) {
            var _r = _s.draw_rows[_i];
            array_push(_lines, "  " + string_copy(_r.name + "                    ", 1, 18)
                + string_format(_r.ms, 3, 2) + "   " + string(round(_r.n)));
        }
        array_push(_lines, "", "NODE DRAW by section  ms/frame  calls");
        for (var _i = 0; _i < min(12, array_length(_s.nd_rows)); _i++) {
            var _r = _s.nd_rows[_i];
            array_push(_lines, "  " + string_copy(_r.name + "                          ", 1, 24)
                + string_format(_r.ms, 3, 2) + "   " + string(round(_r.n)));
        }
        array_push(_lines, "", "GUI by section    ms/frame  calls");
        for (var _i = 0; _i < min(12, array_length(_s.gui_rows)); _i++) {
            var _r = _s.gui_rows[_i];
            array_push(_lines, "  " + string_copy(_r.name + "                          ", 1, 24)
                + string_format(_r.ms, 3, 2) + "   " + string(round(_r.n)));
        }
    }
    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    var _lh = 14;
    var _w  = 0;
    for (var _i = 0; _i < array_length(_lines); _i++) _w = max(_w, string_width(_lines[_i]));
    var _x = display_get_gui_width() - _w - 24;
    var _y = 60;
    draw_set_alpha(0.85);
    draw_set_color(c_black);
    draw_rectangle(_x - 8, _y - 6, _x + _w + 8, _y + array_length(_lines) * _lh + 4, false);
    draw_set_alpha(1);
    for (var _i = 0; _i < array_length(_lines); _i++) {
        draw_set_color(_i == 0 ? c_yellow : c_white);
        draw_text(_x, _y + _i * _lh, _lines[_i]);
    }
}
