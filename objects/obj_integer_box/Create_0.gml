/// @desc Initialise modal W x H integer dialog state
action       = "default";  // identifier for the caller to match on

// Field values (kept as strings for digit entry)
field_w      = "40";
field_h      = "25";
active_field = 0;          // 0 = W, 1 = H

// Suppress the initial mouse click that spawned this dialog
input_armed  = false;

// Layout (GUI space)
box_w        = 540;
box_h        = 240;
fld_w        = 120;
fld_h        = 44;
fld_gap      = 60;
btn_w        = 140;
btn_h        = 48;
btn_gap      = 40;

// Hover tracking
hover_slice  = false;
hover_cancel = false;
hover_fld_w  = false;
hover_fld_h  = false;

// Pulse for visual interest
pulse        = 0;

// Caret blink
caret_timer  = 0;

depth        = -10000; // draw on top of everything

global.integer_box_open = true;