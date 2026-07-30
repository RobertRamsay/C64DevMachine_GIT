/// @desc scr_trigger_latch_fx(x, y, width)
function scr_trigger_latch_fx(_x, _y, _w) {
    if (variable_global_exists("fx_sys") && variable_global_exists("fx_emitter")) {
        
        // Target the seam between nodes
        part_emitter_region(global.fx_sys, global.fx_emitter, _x, _x + _w, _y - 1, _y + 1, ps_shape_rectangle, ps_distr_linear);
        
        // 25-30 particles creates that nice dense spray of dots
        part_emitter_burst(global.fx_sys, global.fx_emitter, global.pt_node_latch, 10);
    }
}