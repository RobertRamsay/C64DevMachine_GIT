/// @desc Pan camera to centre on a node, reset zoom to 1.0.
function scr_focus_camera_on_node(_node) {
    if (!instance_exists(_node)) return;
    var _wm = obj_workspace_manager;
    if (!instance_exists(_wm)) return;

    var _target_zoom = 1.0;
    var _view_w      = 1920 * _target_zoom;
    var _view_h      = 1080 * _target_zoom;
    var _shelf_w     = variable_instance_exists(_wm, "shelf_width") ? _wm.shelf_width : 0;

    // Manual focus offsets — tweak these to taste
    var _varXoffset = 130;
    var _varYoffset = 0;

    // Node centre in world space
    var _ncx = _node.x + (_node.width  * 0.5) + _varXoffset;
    var _ncy = _node.y + (_node.height * 0.5) + _varYoffset;

    // Position camera so node centre sits at the centre of the usable area
    // (subtract half the shelf width from the visible centre offset)
    var _usable_cx = (_shelf_w + (_view_w - _shelf_w) * 0.5);
    var _usable_cy = _view_h * 0.5;

    _wm.cam_zoom        = _target_zoom;
    _wm.cam_zoom_target = _target_zoom;
    _wm.cam_x           = _ncx - _usable_cx;
    _wm.cam_y           = _ncy - _usable_cy;
}