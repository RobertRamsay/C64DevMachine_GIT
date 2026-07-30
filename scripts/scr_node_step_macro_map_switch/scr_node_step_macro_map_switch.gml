/// @desc Step MACRO_MAP_SWITCH node — handles picker button click
/// @param {Id.Instance} _node
function scr_node_step_macro_map_switch(_node) {

    if (!mouse_check_button_pressed(mb_left)) { exit; }
    if (global.ui_click_consumed) { exit; }
    if (global.any_picker_open) { exit; }

    var _pb_y1 = _node.y + 28 + 8 - 2;
    var _pb_y2 = _pb_y1 + 14;
    var _pb_x1 = _node.x + 44;
    var _pb_x2 = _node.x + _node.width - 8;

    if (point_in_rectangle(mouse_x, mouse_y, _pb_x1, _pb_y1, _pb_x2, _pb_y2)) {
        with (obj_asset_manager) {
            map_picker_open  = true;
            map_picker_node  = _node;
            map_picker_hover = -1;
        }
    }
}