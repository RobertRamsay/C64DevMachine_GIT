/// @function scr_c64u_send_d64_and_run(d64_path, boot_prg_path)
/// @description Mounts a D64 on the Ultimate, then (on mount success) DMA-runs
///              the supplied boot PRG so the program starts while the disk
///              stays mounted for runtime loads. Chains via the async handler.
/// @param {String} d64_path       Path to the .d64 image
/// @param {String} boot_prg_path  Path to the boot .prg to run after mount
function scr_c64u_send_d64_and_run(d64_path, boot_prg_path)
{
    global.c64u_run_after_mount = boot_prg_path;
    return scr_c64u_send_d64(d64_path);
}