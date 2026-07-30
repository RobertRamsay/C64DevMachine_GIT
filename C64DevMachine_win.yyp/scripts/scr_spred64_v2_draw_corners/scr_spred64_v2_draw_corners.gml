/// @function scr_spred64_v2_draw_corners(_x1, _y1, _x2, _y2, _len, _thick)
/// @desc Draws L-shaped corner brackets at the four corners of the given
///       rectangle. Used for compositor cell highlights — less heavy than
///       a full border, reads as a tracking/selection marker.
///       _len   : length of each L arm in pixels
///       _thick : line thickness in pixels (1 = single line, 2 = doubled)
///       Caller must set draw_set_color first.
function scr_spred64_v2_draw_corners(_x1, _y1, _x2, _y2, _len, _thick) {
    for (var _t = 0; _t < _thick; _t++) {
        var _tx1 = _x1 + _t;
        var _ty1 = _y1 + _t;
        var _tx2 = _x2 - _t;
        var _ty2 = _y2 - _t;
        // Top-left corner: horizontal arm + vertical arm
        draw_line(_tx1, _ty1, _tx1 + _len, _ty1);
        draw_line(_tx1, _ty1, _tx1,        _ty1 + _len);
        // Top-right corner
        draw_line(_tx2, _ty1, _tx2 - _len, _ty1);
        draw_line(_tx2, _ty1, _tx2,        _ty1 + _len);
        // Bottom-left corner
        draw_line(_tx1, _ty2, _tx1 + _len, _ty2);
        draw_line(_tx1, _ty2, _tx1,        _ty2 - _len);
        // Bottom-right corner
        draw_line(_tx2, _ty2, _tx2 - _len, _ty2);
        draw_line(_tx2, _ty2, _tx2,        _ty2 - _len);
    }
}