function do_windowSizing(){
    windowState++; 
    if (windowState > 1) {
        windowState = 0;
    }
    
    if (windowState == 0) {
        // Windowed mode
        window_set_showborder(true);
        window_set_position(0, 30);
        window_set_size(display_get_width(), display_get_height() * 0.925);
    }
    if (windowState == 1) {
        // Fake fullscreen (borderless windowed) - avoids DirectX swap chain crash
        window_set_showborder(false);
        window_set_position(0, 0);
        window_set_size(display_get_width(), display_get_height());
    }
    
    // Persist window state
    ini_open("c64devmachine.ini");
    ini_write_real("window", "state", windowState);
    ini_close();
}