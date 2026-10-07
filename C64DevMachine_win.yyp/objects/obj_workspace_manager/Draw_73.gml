scr_perf_mark("draw_end");
/// @desc Draw End - CREATOR param cards, over every node.
if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) exit;
scr_label_jump_fx_draw();
scr_creator_draw_cards();
