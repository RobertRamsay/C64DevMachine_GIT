/// @desc Put back anything the tour changed.

show_debug_message("TOUR: cleanup (instance destroyed)");

global.tour_active = false;
global.tour_keys   = [];
global.tour_rects  = [];
global.tour_stamps = [];

if (restore_expert && instance_exists(obj_workspace_manager)) {
    obj_workspace_manager.expert_mode = true;
}
