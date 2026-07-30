/// @description windoe toggler

			do_windowSizing();	
				//if windowState==3   {window_set_fullscreen(true);window_set_showborder(true); window_set_size(1920, 1080)}

/*
var _is_maximized = (window_get_width() == display_get_width() && window_get_height() == display_get_height());

if _is_maximized {
    window_set_showborder(true);
    window_set_size(1920, 1080);
    window_center();
} else {
    window_set_size(display_get_width(), display_get_height());
    window_set_position(0, 0);
    window_set_showborder(false);
}