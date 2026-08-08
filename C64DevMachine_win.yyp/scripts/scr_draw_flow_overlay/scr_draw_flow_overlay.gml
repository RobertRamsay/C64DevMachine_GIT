/// @desc scr_draw_flow_overlay(_edges)
/// Draws the F-key flow overlay: colour-coded lines between every pair of
/// nodes each JMP/JSR/BRANCH/IRQ-vector/sequential-flow edge connects,
/// each with a small circle travelling along it to show direction.
/// Deliberately plain straight lines rather than the ORG-box bezier wire
/// system — this overlay is built to show a lot of connections at once
/// for debugging, not to look like a single polished wire.
/// Called from Draw_64.gml (GUI space) — must run in the same event so it
/// always sits over the nodes regardless of camera zoom/pan or instance
/// draw order, the same reason the box-select overlay lives there too.
function scr_draw_flow_overlay(_edges) {
    var _col_flow   = make_color_rgb(255, 255, 255);
    var _col_jmp    = make_color_rgb(255, 220, 40);
    var _col_jsr    = make_color_rgb(40, 220, 220);
    var _col_branch = make_color_rgb(255, 140, 0);
    var _col_irq    = make_color_rgb(60, 220, 60);

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

    for (var i = 0; i < array_length(_edges); i++) {
        var _e = _edges[i];
        if (!instance_exists(_e.src) || !instance_exists(_e.tgt)) continue;

        var _sw = variable_instance_exists(_e.src, "width") ? _e.src.width : 80;
        var _tw = variable_instance_exists(_e.tgt, "width") ? _e.tgt.width : 80;
        var _wx1 = _e.src.x + _sw * 0.5;
        var _wy1 = _e.src.y + 12; // header anchor

        var _wx2 = _e.tgt.x + _tw * 0.5;
        // jsr_ret's target is the original JSR caller — anchor at its base
        // (bottom) rather than its header, so the return line doesn't
        // crowd the exact same point the outbound JSR line already uses.
        var _th  = variable_instance_exists(_e.tgt, "height") ? _e.tgt.height : 40;
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

        var _col  = _col_flow;
        var _wid  = 2;
        var _alph = 0.25;
        switch (_e.kind) {
            case "jmp":     _col = _col_jmp;    _wid = 3; _alph = 0.85; break;
            case "jsr":     _col = _col_jsr;    _wid = 3; _alph = 0.85; break;
            case "jsr_ret": _col = _col_jsr;    _wid = 3; _alph = 0.4;  break;
            case "branch":  _col = _col_branch; _wid = 3; _alph = 0.85; break;
            case "irq":     _col = _col_irq;    _wid = 4; _alph = 0.9;  break;
            case "flow":    _col = _col_flow;   _wid = 3; _alph = 0.2;  break;
        }

        draw_set_color(_col);
        draw_set_alpha(_alph);

        // ORG/INIT chain transitions route as a right-angled "S" elbow
        // instead of a straight diagonal — ORG blocks jump to specific
        // addresses and are often placed far from their visual neighbour
        // on the canvas, so a stepped connector reads as "a distinct hop
        // between contexts" rather than blending in with normal in-place
        // sequential flow between ordinary macro nodes.
        var _is_org_chain = (_e.kind == "flow")
            && (_e.src.node_type == "ORG" || _e.tgt.node_type == "ORG"
             || _e.src.node_type == "INIT" || _e.tgt.node_type == "INIT");

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
            draw_line_width(_sx1, _sy1, _sx2, _sy2, _wid);

            // Small arrowhead near the target so direction is readable
            // once lines start overlapping — expected at any real size.
            if (_e.kind != "flow") {
                var _ang2 = point_direction(_sx1, _sy1, _sx2, _sy2);
                var _ahx2 = _sx2 - lengthdir_x(14, _ang2);
                var _ahy2 = _sy2 - lengthdir_y(14, _ang2);
                draw_line_width(_ahx2 + lengthdir_x(6, _ang2 + 150), _ahy2 + lengthdir_y(6, _ang2 + 150), _sx2, _sy2, _wid);
                draw_line_width(_ahx2 + lengthdir_x(6, _ang2 - 150), _ahy2 + lengthdir_y(6, _ang2 - 150), _sx2, _sy2, _wid);
            }

            // Travelling pulse — a small circle sliding from source to
            // target so the direction of flow reads at a glance.
            var _px3 = lerp(_sx1, _sx2, _pulse_phase);
            var _py3 = lerp(_sy1, _sy2, _pulse_phase);
            draw_set_alpha(min(1, _alph + 0.15));
            draw_circle(_px3, _py3, _wid + 2, false);
        }
    }
    draw_set_alpha(1.0);
}
