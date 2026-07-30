/// @desc Pulse animation + input arming + self-destruct

pulse += 0.04;
if (pulse > (pi * 2)) pulse -= (pi * 2);

// Arm input on the first frame the mouse is NOT held - swallows any
// click that may have spawned us
if (!input_armed) {
    if (!mouse_check_button(mb_left)) {
        input_armed = true;
    }
}

if (dismissed) {
    instance_destroy();
}