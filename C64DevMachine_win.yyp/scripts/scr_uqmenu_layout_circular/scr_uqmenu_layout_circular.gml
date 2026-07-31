function scr_uqmenu_layout_circular(_index, _count, _cx, _cy, _label) {
    draw_set_font(fnt_c64_tiny);
    var _btn_h  = 24;
    var _min_w  = 46;
    var _btn_w  = max(_min_w, string_width(_label) + 6); // 3px padding each side

    if (_count <= 4) {
        var _radius = 130;
        var _angle;
        switch (_count) {
            case 1: _angle = 90; break;
            case 2: _angle = (_index == 0) ? 90 : 270; break;
            case 3: _angle = 90 - (_index * 120); break;
            case 4: _angle = 135 - (_index * 90); break;
        }
        var _px = _cx + lengthdir_x(_radius, _angle);
        var _py = _cy + lengthdir_y(_radius, _angle);
        return [_px - (_btn_w / 2), _py - (_btn_h / 2), _px + (_btn_w / 2), _py + (_btn_h / 2)];
    }

    if (_count <= 10) {
        var _radius = 150 + ((_count - 5) * 10);
        var _angle  = 90 - (_index * (360 / _count));
        var _px = _cx + lengthdir_x(_radius, _angle);
        var _py = _cy + lengthdir_y(_radius, _angle);
        return [_px - (_btn_w / 2), _py - (_btn_h / 2), _px + (_btn_w / 2), _py + (_btn_h / 2)];
    }

    var _outer_count = min(ceil(_count * 0.6), 14);
    var _inner_count = _count - _outer_count;

    var _ring_index, _ring_count, _radius;
    if (_index < _outer_count) {
        _ring_index = _index;
        _ring_count = _outer_count;
        _radius     = 190;
    } else {
        _ring_index = _index - _outer_count;
        _ring_count = _inner_count;
        _radius     = 110;
    }

    var _angle = 90 - (_ring_index * (360 / _ring_count));
    var _px = _cx + lengthdir_x(_radius, _angle);
    var _py = _cy + lengthdir_y(_radius, _angle);
    return [_px - (_btn_w / 2), _py - (_btn_h / 2), _px + (_btn_w / 2), _py + (_btn_h / 2)];
}