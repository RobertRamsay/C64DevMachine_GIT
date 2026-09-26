/// @desc Guided tour overlay. Started by scr_tour_start().

tour_id        = -1;
tour_title     = "";
steps          = [];
step_idx       = 0;
step_timer     = 0;
done_timer     = 0;      // counts down after a step's check passes
hold_auto      = false;  // true after BACK so the step does not re-skip itself
restore_expert = false;

// Check baselines (set by scr_tour_enter_step)
base_bmp_count = 0;
base_undo_top  = undefined;
base_undo_name = "";
base_build     = 0;

// Smoothed highlight rect
hl_have = false;
hl_x1   = 0;
hl_y1   = 0;
hl_x2   = 0;
hl_y2   = 0;

// Caption panel + buttons, written by Draw GUI, read by Begin Step
panel_x1  = 0;
panel_y1  = 0;
panel_x2  = 0;
panel_y2  = 0;
btn_back  = [0, 0, 0, 0];
btn_next  = [0, 0, 0, 0];
btn_exit  = [0, 0, 0, 0];
panel_vis = false;
