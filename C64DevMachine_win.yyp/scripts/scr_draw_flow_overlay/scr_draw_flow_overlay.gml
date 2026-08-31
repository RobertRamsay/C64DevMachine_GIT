/// @desc scr_draw_flow_overlay(_edges, _mode, _style)
/// _style: 0 = Direct (straight lines), 1 = Angled (45-degree chamfered
/// routing, default). Set via the OPTIONS menu "FLOW TYPE" toggle.
/// Draws the F-key flow overlay: colour-coded lines between every pair of
/// nodes each JMP/JSR/BRANCH/IRQ-vector/sequential-flow edge connects,
/// each with a small circle travelling along it to show direction.
/// Deliberately plain straight lines rather than the ORG-box bezier wire
/// system — this overlay is built to show a lot of connections at once
/// for debugging, not to look like a single polished wire.
/// Called from Draw_64.gml (GUI space) — must run in the same event so it
/// always sits over the nodes regardless of camera zoom/pan or instance
/// draw order, the same reason the box-select overlay lives there too.
function scr_draw_flow_overlay(_edges, _mode, _style = 1) {
    // World -> GUI transform, same as the box-select overlay above.
    var _vx = camera_get_view_x(view_camera[0]);
    var _vy = camera_get_view_y(view_camera[0]);
    var _vw = camera_get_view_width(view_camera[0]);
    var _vh = camera_get_view_height(view_camera[0]);
    var _sx = global.gui_w / _vw;
    var _sy = display_get_gui_height() / _vh;

    // Shared pulse phase — one sweep every ~1.2s, synchronised across all
    // edges rather than tracked per-edge (simpler, and still reads fine).
    var _pulse_phase = (current_time mod 1200) / 1200;

    // Circuit-board-style path: pure vertical/horizontal runs with a single
    // exact 45° diagonal absorbing the difference between the two axes —
    // V-D-V for vertical-dominant edges, H-D-H for horizontal-dominant
    // ones. Collapses to a single straight or single diagonal segment in
    // the degenerate cases (one axis ~0, or |dx| == |dy| already).
    var _chamfer_points = function(_x1, _y1, _x2, _y2) {
        var _dx = _x2 - _x1, _dy = _y2 - _y1;
        var _adx = abs(_dx), _ady = abs(_dy);
        if (_adx < 0.5 || _ady < 0.5 || abs(_adx - _ady) < 0.5) {
            // Already axis-aligned or already exactly 45° — no chamfer needed.
            return [[_x1, _y1], [_x2, _y2]];
        }
        var _sgnx = sign(_dx), _sgny = sign(_dy);
        var _d    = min(_adx, _ady);       // diagonal run (exact 45°)
        var _half = (max(_adx, _ady) - _d) * 0.5;
        if (_ady >= _adx) {
            // Vertical-dominant: V - D - V
            var _ay = _y1 + _sgny * _half;
            var _by = _ay + _sgny * _d;
            var _bx = _x1 + _dx; // all of dx happens during the diagonal leg
            return [[_x1, _y1], [_x1, _ay], [_bx, _by], [_x2, _y2]];
        } else {
            // Horizontal-dominant: H - D - H
            var _ax = _x1 + _sgnx * _half;
            var _bx = _ax + _sgnx * _d;
            var _by = _y1 + _dy; // all of dy happens during the diagonal leg
            return [[_x1, _y1], [_ax, _y1], [_bx, _by], [_x2, _y2]];
        }
    };

    // Position along a poly-line at 0..1 phase, moving at constant visual
    // speed across however many segments _chamfer_points produced.
    var _poly_pulse_point = function(_pts, _phase) {
        var _n = array_length(_pts);
        var _lens  = array_create(_n - 1);
        var _total = 0;
        for (var _i = 0; _i < _n - 1; _i++) {
            _lens[_i] = point_distance(_pts[_i][0], _pts[_i][1], _pts[_i+1][0], _pts[_i+1][1]);
            _total += _lens[_i];
        }
        _total = max(1, _total);
        var _dist = _phase * _total;
        var _acc  = 0;
        for (var _i = 0; _i < _n - 1; _i++) {
            if (_dist <= _acc + _lens[_i] || _i == _n - 2) {
                var _t = (_lens[_i] > 0) ? clamp((_dist - _acc) / _lens[_i], 0, 1) : 0;
                return [lerp(_pts[_i][0], _pts[_i+1][0], _t), lerp(_pts[_i][1], _pts[_i+1][1], _t)];
            }
            _acc += _lens[_i];
        }
        return [_pts[_n-1][0], _pts[_n-1][1]];
    };

    var _hovered_node = noone;
    
    // Mode 1: Local Hover Mode - find hovered node and abort if empty
    if (_mode == 1) {
        with (obj_c64_node) {
            // scr_node_mouse_over is the same rectangle test with the fold
            // check in front of it — a folded node must not answer the hover.
            if (scr_node_mouse_over(id)) {
                _hovered_node = id;
                break;
            }
        }
        if (_hovered_node == noone) return;
    }

    // Pre-pass: which edges actually get drawn (same filters as the loop
    // below) — needed up front so the hue spread below can be spaced
    // evenly across however many lines are really on screen, rather than
    // across the raw _edges array which also holds skipped flow/branch
    // entries and off-screen mode-1 lines.
    var _visible = [];
    for (var _vi = 0; _vi < array_length(_edges); _vi++) {
        var _ve = _edges[_vi];
        if (!instance_exists(_ve.src) || !instance_exists(_ve.tgt)) continue;
        // An edge with either end inside a folded block drew a line off into
        // empty canvas, since the node it pointed at is not rendered. Drop the
        // whole edge rather than half of it. The flow GRAPH is untouched — a
        // fold is visual only, and unfolding brings the line straight back.
        if (scr_node_is_hidden(_ve.src) || scr_node_is_hidden(_ve.tgt)) continue;
        if (_ve.kind == "flow") continue;
        if (_mode == 1 && _ve.src != _hovered_node && _ve.tgt != _hovered_node) continue;
        array_push(_visible, _ve);
    }
    var _visible_count = array_length(_visible);

    // Branches use their own fixed colour and therefore must not alter the
    // rainbow slots assigned to JMP/JSR/RTS/IRQ lines. This keeps every call
    // route visually stable when an IF BYTE/IF WORD node is added or removed.
    var _call_visible_count = 0;
    for (var _vci = 0; _vci < _visible_count; _vci++) {
        if (_visible[_vci].kind != "branch") _call_visible_count++;
    }
    var _call_colour_i = 0;

    for (var i = 0; i < _visible_count; i++) {
        var _e = _visible[i];

        var _sw = variable_instance_exists(_e.src, "width") ? _e.src.width : 80;
        var _tw = variable_instance_exists(_e.tgt, "width") ? _e.tgt.width : 80;

        // obj_c64_node.x is the raw, pre-indent position outside its own
        // Draw event (which temporarily adds x_indent, draws, then
        // subtracts it back off) — so a line anchored straight off .x
        // lands to the left of where an indented node actually renders.
        // Add each node's own x_indent back in so the anchor matches what
        // the eye actually sees on screen.
        var _sxi = variable_instance_exists(_e.src, "x_indent") ? _e.src.x_indent : 0;
        var _txi = variable_instance_exists(_e.tgt, "x_indent") ? _e.tgt.x_indent : 0;

        // Regular (non-org-jump) flow lines anchor 10px in from the left
        // edge instead of the centre — keeps them off to one side instead
        // of cutting through node content, and out of the way of the
        // colour-coded jmp/jsr/branch/irq lines which stay centre-anchored.
        var _left_justify = (_e.kind == "flow") && !_e.org_jump;

        var _sh = variable_instance_exists(_e.src, "height") ? _e.src.height : 40;
        var _th = variable_instance_exists(_e.tgt, "height") ? _e.tgt.height : 40;

        var _wx1 = _left_justify ? (_e.src.x + _sxi + 10) : (_e.src.x + _sxi + _sw * 0.5);
        // jsr_ret originates from the base (bottom) of the RTS node, not the header
        var _wy1 = (_e.kind == "jsr_ret") ? (_e.src.y + _sh) : (_e.src.y + 12);

        var _wx2 = _left_justify ? (_e.tgt.x + _txi + 10) : (_e.tgt.x + _txi + _tw * 0.5);
        // jsr_ret's target is the original JSR caller — anchor at its base
        // (bottom) rather than its header, so the return line doesn't
        // crowd the exact same point the outbound JSR line already uses.
        var _wy2 = (_e.kind == "jsr_ret") ? (_e.tgt.y + _th) : (_e.tgt.y + 12);

        // Two-lane offset: a line flowing down shifts left, one flowing up
        // shifts right, so a JSR-out and its jsr_ret return trip run in
        // parallel lanes instead of sitting exactly on top of each other.
        var _lane = (_wy2 > _wy1) ? -4 : 4;
        _wx1 += _lane;
        _wx2 += _lane;

        var _sx1 = (_wx1 - _vx) * _sx;
        var _sy1 = (_wy1 - _vy) * _sy;
        var _sx2 = (_wx2 - _vx) * _sx;
        var _sy2 = (_wy2 - _vy) * _sy;

        // Full-spectrum hue spread: each visible line gets its own slice
        // of the colour wheel based purely on its position in the visible
        // list, rather than being grouped by kind — makes it far easier
        // to trace one specific line through a dense tangle of others.
        // Width/alpha still vary by kind so the important stuff (jmp/jsr/
        // irq) reads heavier than a faint jsr_ret return trip.
        var _hue = (_call_visible_count > 1)
            ? (_call_colour_i / _call_visible_count) * 255 : 0;
        var _col = (_e.kind == "branch")
            ? make_color_rgb(255, 150, 40)
            : make_color_hsv(_hue, 200, 255);
        if (_e.kind != "branch") _call_colour_i++;
        var _wid  = 2;
        var _alph = 0.25;
        switch (_e.kind) {
            case "jmp":     _wid = 3; _alph = 0.85; break;
            case "jsr":     _wid = 3; _alph = 0.85; break;
            case "jsr_ret": _wid = 3; _alph = 0.4;  break;
            case "branch":  _wid = 2; _alph = 0.75; break;
            case "irq":     _wid = 4; _alph = 0.9;  break;
        }

        draw_set_color(_col);
        draw_set_alpha(_alph);

        // ORG-caused address discontinuities route as a right-angled "S"
        // elbow instead of a straight diagonal — see scr_build_flow_graph
        // for why this is keyed off an actual gap in the compiled address
        // sequence rather than which node types sit on either end.
        var _is_org_chain = (_e.kind == "flow") && _e.org_jump;

        if (_is_org_chain) {
            var _ymid = (_sy1 + _sy2) * 0.5;
            var _p1x = _sx1, _p1y = _ymid;
            var _p2x = _sx2, _p2y = _ymid;
            draw_line_width(_sx1, _sy1, _p1x, _p1y, _wid);
            draw_line_width(_p1x, _p1y, _p2x, _p2y, _wid);
            draw_line_width(_p2x, _p2y, _sx2, _sy2, _wid);

            var _ang = point_direction(_p2x, _p2y, _sx2, _sy2);
            var _ahx = _sx2 - lengthdir_x(14, _ang);
            var _ahy = _sy2 - lengthdir_y(14, _ang);
            draw_line_width(_ahx + lengthdir_x(6, _ang + 150), _ahy + lengthdir_y(6, _ang + 150), _sx2, _sy2, _wid);
            draw_line_width(_ahx + lengthdir_x(6, _ang - 150), _ahy + lengthdir_y(6, _ang - 150), _sx2, _sy2, _wid);

            // Pulse travels proportionally across all 3 segments by length,
            // so it moves at a constant visual speed along the whole path.
            var _len1 = point_distance(_sx1, _sy1, _p1x, _p1y);
            var _len2 = point_distance(_p1x, _p1y, _p2x, _p2y);
            var _len3 = point_distance(_p2x, _p2y, _sx2, _sy2);
            var _total = max(1, _len1 + _len2 + _len3);
            var _dist  = _pulse_phase * _total;
            var _px, _py;
            if (_dist < _len1) {
                var _t0 = _dist / max(1, _len1);
                _px = lerp(_sx1, _p1x, _t0);
                _py = lerp(_sy1, _p1y, _t0);
            } else if (_dist < _len1 + _len2) {
                var _t1 = (_dist - _len1) / max(1, _len2);
                _px = lerp(_p1x, _p2x, _t1);
                _py = lerp(_p1y, _p2y, _t1);
            } else {
                var _t2 = (_dist - _len1 - _len2) / max(1, _len3);
                _px = lerp(_p2x, _sx2, _t2);
                _py = lerp(_p2y, _sy2, _t2);
            }
            draw_set_alpha(min(1, _alph + 0.15));
            draw_circle(_px, _py, _wid + 2, false);
        } else {
            var _pts = (_style == 0)
                ? [[_sx1, _sy1], [_sx2, _sy2]]
                : _chamfer_points(_sx1, _sy1, _sx2, _sy2);
            var _n_pts = array_length(_pts);
            for (var _pi = 0; _pi < _n_pts - 1; _pi++) {
                draw_line_width(_pts[_pi][0], _pts[_pi][1], _pts[_pi+1][0], _pts[_pi+1][1], _wid);
            }

            // Small arrowhead near the target so direction is readable
            // once lines start overlapping — expected at any real size.
            // Angled off the final segment so it matches whatever the last
            // leg of the chamfered path actually is (V, H, or 45°).
            if (_e.kind != "flow") {
                var _last = _pts[_n_pts - 1];
                var _prev = _pts[_n_pts - 2];
                var _ang2 = point_direction(_prev[0], _prev[1], _last[0], _last[1]);
                var _ahx2 = _last[0] - lengthdir_x(14, _ang2);
                var _ahy2 = _last[1] - lengthdir_y(14, _ang2);
                draw_line_width(_ahx2 + lengthdir_x(6, _ang2 + 150), _ahy2 + lengthdir_y(6, _ang2 + 150), _last[0], _last[1], _wid);
                draw_line_width(_ahx2 + lengthdir_x(6, _ang2 - 150), _ahy2 + lengthdir_y(6, _ang2 - 150), _last[0], _last[1], _wid);
            }

            // Travelling pulse — a small circle sliding along the chamfered
            // path from source to target at constant visual speed across
            // all of its V/D/H segments, so direction reads at a glance.
            var _pulse_pos = _poly_pulse_point(_pts, _pulse_phase);
            draw_set_alpha(min(1, _alph + 0.15));
            draw_circle(_pulse_pos[0], _pulse_pos[1], _wid + 2, false);
        }
    }
    draw_set_alpha(1.0);
}
