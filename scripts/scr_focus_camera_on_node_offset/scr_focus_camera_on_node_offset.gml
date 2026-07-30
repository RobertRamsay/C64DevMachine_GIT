function scr_focus_camera_on_node_offset(_node, _vertical_fraction) {
    if (!instance_exists(_node)) return;
    var _wm = obj_workspace_manager;
    if (!instance_exists(_wm)) return;
    var _target_zoom = 1.0;
    var _view_w      = 1920 * _target_zoom;
    var _view_h      = 1080 * _target_zoom;
    var _shelf_w     = variable_instance_exists(_wm, "shelf_width") ? _wm.shelf_width : 0;

    var _ncx = _node.x + (_node.width  * 0.5) +100 ;
    var _ncy = _node.y + (_node.height * 0.5) -200;

    var _usable_cx = (_shelf_w + (_view_w - _shelf_w) * 0.5);
    var _usable_cy = _view_h * _vertical_fraction;

    _wm.cam_zoom        = _target_zoom;
    _wm.cam_zoom_target = _target_zoom;
    _wm.cam_x           = _ncx - _usable_cx;
    _wm.cam_y           = _ncy - _usable_cy;

    // Apply the view size immediately — the normal Step-event zoom code
    // (camera_set_view_size) doesn't run while a modal has already exited
    // Step early, so without this the view stays at the pre-focus zoom
    // and every offset/position calc above is measured against the wrong
    // view dimensions.
    if (variable_instance_exists(_wm, "cam_view")) {
        camera_set_view_size(_wm.cam_view, 1920 * _wm.cam_zoom, 1080 * _wm.cam_zoom);
    }
}