function scr_c64u_reu_step() {
    if (global.c64u_reu_state == "idle") return;
    if (current_time < global.c64u_reu_deadline) return;
    if (global.c64u_reu_state == "settle") {
        scr_c64u_reu_continue();
    } else {
        scr_c64u_reu_fail("DMA service timed out");
    }
}