/// @desc Caption panel buttons (Begin Step, so the click is claimed before
///       nodes and the workspace see it).

if (!panel_vis) {
    exit;
}
if (!mouse_check_button_pressed(mb_left)) {
    exit;
}

var _mx = device_mouse_x_to_gui(0);
var _my = device_mouse_y_to_gui(0);

if (!point_in_rectangle(_mx, _my, panel_x1, panel_y1, panel_x2, panel_y2)) {
    exit;
}

global.ui_click_block_timer = 6;

var _last = array_length(steps) - 1;

if (point_in_rectangle(_mx, _my, btn_exit[0], btn_exit[1], btn_exit[2], btn_exit[3])) {
    scr_tour_end();
    exit;
}

if (point_in_rectangle(_mx, _my, btn_back[0], btn_back[1], btn_back[2], btn_back[3])) {
    if (step_idx > 0) {
        step_idx--;
        hold_auto = true;
        scr_tour_enter_step();
    }
    exit;
}

if (point_in_rectangle(_mx, _my, btn_next[0], btn_next[1], btn_next[2], btn_next[3])) {
    if (step_idx >= _last) {
        scr_tour_end();
        exit;
    }
    step_idx++;
    hold_auto = false;
    scr_tour_enter_step();
    exit;
}
