function scr_node_step_macro_load_game(_draw_x) {
    var _header_h = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;

    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _fy, _draw_x + width - 8, _fy + 16)) {
        if (instance_exists(obj_asset_manager)) {
            var _node_id = id;
            with (obj_asset_manager) {
                loader_org_picker_open  = true;
                loader_org_picker_node  = _node_id;
                loader_org_picker_hover = -1;
            }
        }
        exit;
    }
    _fy += _line_h;

    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _fy, _draw_x + width - 8, _fy + 16)) {
        var _org_name = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
        if (_org_name != "" && instance_exists(obj_asset_manager)) {
            var _node_id = id;
            with (obj_asset_manager) {
                loader_file_picker_open  = true;
                loader_file_picker_node  = _node_id;
                loader_file_picker_hover = -1;
            }
        }
        exit;
    }
}