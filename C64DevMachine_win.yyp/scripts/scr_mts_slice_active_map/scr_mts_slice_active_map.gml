/// @desc Re-slice the active map of a META_TILESET into rooms of _room_w x
///       _room_h char cells, replacing all maps. char 0 / out-of-range cells
///       become empty (-1). All resulting maps share the room size.
/// @param {struct} _m       the tileset meta
/// @param {real}   _room_w  room width  in char cells
/// @param {real}   _room_h  room height in char cells
function scr_mts_slice_active_map(_m, _room_w, _room_h)
{
    if (array_length(_m.maps) == 0)
    {
        return;
    }
    if (_m.active_map < 0 || _m.active_map >= array_length(_m.maps))
    {
        return;
    }

    // Source is the currently active (BIGMAP) room and its char dimensions.
    var _src_grid = _m.maps[_m.active_map];
    // Grids are stored in METATILE cells; strides are char dims / stamp size.
    var _src_cols = floor(_m.map_w[_m.active_map] / _m.stamp_w);
    var _src_rows = floor(_m.map_h[_m.active_map] / _m.stamp_h);
    // Snap requested room char dims DOWN to whole metatiles.
    var _room_cols = clamp(floor(_room_w / _m.stamp_w), 1, _src_cols);
    var _room_rows = clamp(floor(_room_h / _m.stamp_h), 1, _src_rows);
    var _room_w_ch = _room_cols * _m.stamp_w;
    var _room_h_ch = _room_rows * _m.stamp_h;
    var _cols_r = ceil(_src_cols / _room_cols);
    var _rows_r = ceil(_src_rows / _room_rows);

    var _new_maps  = [];
    var _new_bytes = [];
    var _new_w     = [];
    var _new_h     = [];

    var _rr = 0;
    for (_rr = 0; _rr < _rows_r; _rr++)
    {
        var _rc = 0;
        for (_rc = 0; _rc < _cols_r; _rc++)
        {
            var _room_cells = _room_cols * _room_rows;
            var _room = array_create(_room_cells, -1);
            var _ry = 0;
            for (_ry = 0; _ry < _room_rows; _ry++)
            {
                var _src_y = (_rr * _room_rows) + _ry;
                if (_src_y >= _src_rows)
                {
                    continue;
                }
                var _rx = 0;
                for (_rx = 0; _rx < _room_cols; _rx++)
                {
                    var _src_x = (_rc * _room_cols) + _rx;
                    if (_src_x >= _src_cols)
                    {
                        continue;
                    }
                    var _src_idx = (_src_y * _src_cols) + _src_x;
                    if (_src_idx < array_length(_src_grid))
                    {
                        _room[(_ry * _room_cols) + _rx] = _src_grid[_src_idx];
                    }
                }
            }
            array_push(_new_maps, _room);
            array_push(_new_bytes, 0);
            array_push(_new_w, _room_w_ch);
            array_push(_new_h, _room_h_ch);
        }
    }

    _m.maps      = _new_maps;
    _m.map_bytes = _new_bytes;
    _m.map_w     = _new_w;
    _m.map_h     = _new_h;
    _m.map_count = array_length(_new_maps);
    _m.active_map = 0;
    _m.is_dirty  = true;
}