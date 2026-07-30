/// @desc Draw backdrop - fills viewport exactly
var _wm    = obj_workspace_manager;
var _cam_x = _wm.cam_x;
var _cam_y = _wm.cam_y;
var _cam_w = 1920 * _wm.cam_zoom;
var _cam_h = 1080 * _wm.cam_zoom;

var _spr_w = sprite_get_width(spr_bkg);
var _spr_h = sprite_get_height(spr_bkg);

var _xscale = _cam_w / _spr_w;
var _yscale = _cam_h / _spr_h;

draw_clear(c_black);
var _col = c_white
var _frm = obj_workspace_manager.bkgImg
if _frm==3 _col = c_blue
if global.lite==1 _col = c_red



draw_sprite_ext(spr_bkg, _frm, _cam_x, _cam_y, _xscale, _yscale, 0, _col, 1);



