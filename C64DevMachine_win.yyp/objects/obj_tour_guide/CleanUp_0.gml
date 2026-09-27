/// @desc Put back anything the tour changed.

global.tour_active = false;
global.tour_keys   = [];
global.tour_rects  = [];
global.tour_stamps = [];

if (restore_expert && instance_exists(obj_workspace_manager)) {
    obj_workspace_manager.expert_mode = true;
}
if (restore_showcode && instance_exists(obj_workspace_manager)) {
    obj_workspace_manager.showcode_enabled = true;
}
