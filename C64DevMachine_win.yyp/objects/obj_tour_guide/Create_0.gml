/// @desc Guided tour overlay. Started by scr_tour_start().

tour_id        = -1;
tour_title     = "";
steps          = [];
step_idx       = 0;
step_timer     = 0;
done_timer     = 0;      // counts down after a step's check passes
hold_auto      = false;  // true after BACK so the step does not re-skip itself
restore_expert = false;
restore_showcode = false; // SHOW CODE panel hidden for the tour, put back after

// Check baselines (set by scr_tour_enter_step)
base_bmp_count = 0;
base_spr_count   = 0;

// Gentle camera glide to a drag step's DROP HERE spot.
glide_active = false;   // camera is easing towards glide_tx / glide_ty
glide_wait   = 0;       // frames left to wait for the drop node to exist
glide_tx     = 0;
glide_ty     = 0;
glide_target = false;  // gliding to a field or node rather than a DROP HERE spot
base_label_count = 0;
base_undo_top  = undefined;
base_undo_name = "";
base_build     = 0;

// Smoothed highlight rect
hl_have = false;
hl_x1   = 0;
hl_y1   = 0;
hl_x2   = 0;
hl_y2   = 0;
hl_cam_x = 0;          // view the box was last placed for; a change snaps it
hl_cam_y = 0;
hl_cam_w = 0;

// Caption panel + buttons, written by Draw GUI, read by Begin Step
panel_x1  = 0;
panel_y1  = 0;
panel_x2  = 0;
panel_y2  = 0;
btn_back  = [0, 0, 0, 0];
btn_next  = [0, 0, 0, 0];
btn_exit  = [0, 0, 0, 0];
btn_doit  = [0, 0, 0, 0];
doit_vis  = false;     // DO IT FOR ME shown (and clickable) this frame

// What DO IT FOR ME last did, shown on that step and the one after
did_text  = "";
did_step  = -1;
panel_vis = false;
