/// @desc Advance the tour when the current step is done.

global.tour_frame++;
step_timer++;

if (step_idx < 0 || step_idx >= array_length(steps)) {
    exit;
}

var _step = steps[step_idx];

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
