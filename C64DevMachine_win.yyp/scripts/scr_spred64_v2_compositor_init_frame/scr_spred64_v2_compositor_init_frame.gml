/// @function scr_spred64_v2_compositor_init_frame()
/// @desc Returns a fresh empty compositor frame struct. Used by open/resync
///       and any future "add frame" action in phase 3.
function scr_spred64_v2_compositor_init_frame() {
    return { cells : [] };
}