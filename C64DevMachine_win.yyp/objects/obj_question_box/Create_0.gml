/// @desc Initialise modal Yes/No dialog state
message      = "";
action       = "default";  // identifier for the caller to match on
result       = -1;         // -1 pending, 0 No, 1 Yes

// Suppress the initial mouse click that may have spawned this dialog,
// otherwise the click-through hits a button on frame 1
input_armed  = false;

// Layout (GUI space)
box_w        = 540;
box_h        = 220;
btn_w        = 140;
btn_h        = 48;
btn_gap      = 40;

// Hover tracking
hover_yes    = false;
hover_no     = false;

// Pulse for visual interest, matches your link_pulse style
pulse        = 0;

depth        = -10000; // draw on top of everything