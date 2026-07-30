/// @desc Pulse animation + input arming + result publishing

pulse += 0.04;
if (pulse > (pi * 2)) pulse -= (pi * 2);

caret_timer += 1;
if (caret_timer >= 60) caret_timer = 0;

// Arm input on the frame after the spawning click releases
if (!input_armed) {
    if (!mouse_check_button(mb_left)) {
        input_armed = true;
    }
}