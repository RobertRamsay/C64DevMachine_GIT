/// @function scr_spred64_v2_anim_step()
/// @desc Advances compositor.active_frame if a frame-step is due, based on
///       anim_speed (fps) and anim_direction. Handles all four loop modes:
///       "fwd"  — wrap to anim_start when passing anim_end
///       "rev"  — wrap to anim_end   when passing anim_start
///       "png"  — bounce between anim_start and anim_end
///       "once" — stop at anim_end (fwd) / anim_start (rev) and disengage
///       Called once per draw frame from scr_spred64_v2_draw.
function scr_spred64_v2_anim_step() {
    with (obj_asset_manager) {
        if (!spred64_v2.active) exit;
        if (!spred64_v2.anim_playing) exit;
        var _v2   = spred64_v2;
        var _comp = _v2.compositor;
        var _now  = current_time;
        // Step interval in ms
        var _step_ms = 1000 / max(_v2.anim_speed, 1);
        if (_now - _v2.anim_last_step_ms < _step_ms) exit;
        _v2.anim_last_step_ms = _now;
        // Clamp range against current frame count
        var _frame_count = array_length(_comp.frames);
        var _start = clamp(_v2.anim_start, 0, _frame_count - 1);
        var _end   = clamp(_v2.anim_end,   0, _frame_count - 1);
        // Ensure start <= end (swap silently if user inverted them)
        if (_start > _end) {
            var _tmp = _start;
            _start = _end;
            _end = _tmp;
        }
        var _cur = _comp.active_frame;
        // If outside range, snap into it before stepping
        if (_cur < _start || _cur > _end) {
            _cur = _start;
        }
        switch (_v2.anim_direction) {
            case "fwd":
                _cur++;
                if (_cur > _end) {
                    _cur = _start;
                }
                break;
            case "rev":
                _cur--;
                if (_cur < _start) {
                    _cur = _end;
                }
                break;
            case "png":
                _cur += _v2.anim_png_dir;
                if (_cur > _end) {
                    _cur = max(_start, _end - 1);
                    _v2.anim_png_dir = -1;
                } else if (_cur < _start) {
                    _cur = min(_end, _start + 1);
                    _v2.anim_png_dir = 1;
                }
                break;
            case "once":
                _cur++;
                if (_cur > _end) {
                    _cur = _end;
                    _v2.anim_playing = false;
                }
                break;
        }
        _comp.active_frame = _cur;
    }
}