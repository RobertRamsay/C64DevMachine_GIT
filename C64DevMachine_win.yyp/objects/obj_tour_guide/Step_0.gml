/// @desc Advance the tour when the current step is done.

global.tour_frame++;
step_timer++;

if (step_idx < 0 || step_idx >= array_length(steps)) {
    exit;
}

var _step = steps[step_idx];

// DO IT FOR ME clicked EDIT on a bitmap being edited: close the viewer once
// edit mode has ended (or after half a second, whatever happened)
if (close_pending > 0) {
    close_pending--;
    var _cpb = scr_tour_viewer_bitmap();
    if (is_undefined(_cpb) || !(_cpb.meta[$ "is_editing"] ?? false) || close_pending == 0) {
        close_pending = 0;
        if (obj_asset_manager.viewer_open) {
            scr_tour_close_viewer();
        }
    }
}

scr_tour_glide_step();

// DO IT ALL: each step is done the way DO IT FOR ME does it, reading steps
// just move on, and message boxes are OK'd. A question waits for the user;
// a step that can't be done (or won't finish) stops it and says so.
if (auto_all) {
    with (obj_message_box) {
        dismissed = true;
    }
    if (step_idx >= array_length(steps) - 1) {
        auto_all = false;
    } else if (!instance_exists(obj_question_box)) {
        if (done_timer > 6) {
            done_timer = 6;
        }
        if (done_timer == 0) {
            auto_wait++;
            auto_stall++;
            if (_step.check == "NONE") {
                if (auto_wait >= 20) {
                    step_idx++;
                    hold_auto  = false;
                    auto_wait  = 0;
                    auto_stall = 0;
                    scr_tour_enter_step();
                }
                exit;
            }
            if (auto_wait >= 30 && !scr_tour_check(_step.check)) {
                auto_wait = 0;
                if (scr_tour_can_do(_step)) {
                    scr_tour_do_it();
                }
            }
            if (auto_stall > 600) {
                auto_all = false;
                did_text = "DO IT ALL stopped here: this step needs you. Do it, then press DO IT ALL again.";
                did_step = step_idx;
            }
        } else {
            auto_stall = 0;
        }
    }
}

// Short "done" flash, then move on.
if (done_timer > 0) {
    done_timer--;
    if (done_timer == 0) {
        if (step_idx < array_length(steps) - 1) {
            step_idx++;
            scr_tour_enter_step();
        }
    }
    exit;
}

// After BACK, wait until the step is genuinely undone before auto-advancing
// again, otherwise it would skip straight forward.
if (hold_auto) {
    if (!scr_tour_check(_step.check)) {
        hold_auto = false;
    }
    exit;
}

if (scr_tour_check(_step.check)) {
    done_timer = 40;
}
