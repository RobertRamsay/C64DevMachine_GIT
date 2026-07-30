/// @desc Pulse animation + input arming + result publishing

pulse += 0.04;
if (pulse > (pi * 2)) pulse -= (pi * 2);

// Arm input on frame 2 to swallow any click that spawned us
if (!input_armed) {
    if (!mouse_check_button(mb_left)) {
        input_armed = true;
    }
}

// Once user has clicked, publish result and self-destruct
if (result != -1) {
    global.question_result = action + ((result == 1) ? "_yes" : "_no");
    instance_destroy();
}