function scr_c64_pepto_colour(_idx) {
    switch (_idx) {
        case  0: return make_color_rgb(0,   0,   0);   // Black
        case  1: return make_color_rgb(255, 255, 255);  // White
        case  2: return make_color_rgb(104, 55,  43);   // Red
        case  3: return make_color_rgb(112, 164, 178);  // Cyan
        case  4: return make_color_rgb(111, 61,  134);  // Purple
        case  5: return make_color_rgb(88,  141, 67);   // Green
        case  6: return make_color_rgb(53,  40,  121);  // Blue
        case  7: return make_color_rgb(184, 199, 111);  // Yellow
        case  8: return make_color_rgb(111, 79,  37);   // Orange
        case  9: return make_color_rgb(67,  57,  0);    // Brown
        case 10: return make_color_rgb(154, 103, 89);   // Light Red
        case 11: return make_color_rgb(68,  68,  68);   // Dark Grey
        case 12: return make_color_rgb(108, 108, 108);  // Mid Grey
        case 13: return make_color_rgb(154, 210, 132);  // Light Green
        case 14: return make_color_rgb(108, 94,  181);  // Light Blue
        case 15: return make_color_rgb(149, 149, 149);  // Light Grey
        default: return make_color_rgb(0,   0,   0);
    }
}