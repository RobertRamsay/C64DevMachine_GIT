/// @desc scr_draw_flow_overlay(_edges)
/// Draws the F-key flow overlay: colour-coded lines between every pair of
/// nodes each JMP/JSR/BRANCH/IRQ-vector/sequential-flow edge connects.
/// Deliberately plain straight lines rather than the ORG-box bezier wire
/// system — this overlay is built to show a lot of connections at once
/// for debugging, not to look like a single polished wire.
function scr_draw_flow_overlay(_edges) {
    var _col_flow   = make_color_rgb(255, 255, 255);
    var _col_jmp    = make_color_rgb(255, 220, 40);
    var _col_jsr    = make_color_rgb(40, 220, 220);
    var _col_branch = make_color_rgb(255, 140, 0);
    var _col_irq    = make_color_rgb(60, 220, 60);

    for (var i = 0; i < array_length(_edges); i++) {
        var _e = _edges[i];
        if (!instance_exists(_e.src) || !instance_exists(_e.tgt)) continue;

        var _sw = variable_instance_exists(_e.src, "width") ? _e.src.width : 80;
        var _tw = variable_instance_exists(_e.tgt, "width") ? _e.tgt.width : 80;
        var _sx = _e.src.x + _sw * 0.5;
        var _sy = _e.src.y + 12;
        var _tx = _e.tgt.x + _tw * 0.5;
        var _ty = _e.tgt.y + 12;

        var _col  = _col_flow;
        var _wid  = 1;
        var _alph = 0.25;
        switch (_e.kind) {
            case "jmp":     _col = _col_jmp;    _wid = 2; _alph = 0.85; break;
            case "jsr":     _col = _col_jsr;    _wid = 2; _alph = 0.85; break;
            case "jsr_ret": _col = _col_jsr;    _wid = 1; _alph = 0.35; break;
            case "branch":  _col = _col_branch; _wid = 2; _alph = 0.85; break;
            case "irq":     _col = _col_irq;    _wid = 3; _alph = 0.9;  break;
            case "flow":    _col = _col_flow;   _wid = 1; _alph = 0.25; break;
        }

        draw_set_color(_col);
        draw_set_alpha(_alph);
        draw_line_width(_sx, _sy, _tx, _ty, _wid);

        // Small arrowhead near the target so direction is readable once
        // lines start overlapping — expected at any real project size.
        if (_e.kind != "flow") {
            var _ang = point_direction(_sx, _sy, _tx, _ty);
            var _ahx = _tx - lengthdir_x(14, _ang);
            var _ahy = _ty - lengthdir_y(14, _ang);
            draw_line_width(_ahx + lengthdir_x(6, _ang + 150), _ahy + lengthdir_y(6, _ang + 150), _tx, _ty, _wid);
            draw_line_width(_ahx + lengthdir_x(6, _ang - 150), _ahy + lengthdir_y(6, _ang - 150), _tx, _ty, _wid);
        }
    }
    draw_set_alpha(1.0);
}
