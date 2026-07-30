var p = c64_new_program();
p.sei(); 

//  1. FULL SCREEN VOID WIPE 
p.ldx_imm(0); // initialization
/////////////////////////////////////
p.label("wipe_loop");
    p.lda_imm(32); // Space character
    p.sta_abs_x(0x0400); p.sta_abs_x(0x0500); p.sta_abs_x(0x0600); p.sta_abs_x(0x06E8); 
    p.lda_imm(0);  // Black color
    p.sta_abs_x(0xD800); p.sta_abs_x(0xD900); p.sta_abs_x(0xDA00); p.sta_abs_x(0xDB00); 
    p.inx(); p.bne("wipe_loop");
	// 0 - 255 is #$00 to #$FF
// 1b : Set screen/border to black
p.lda_imm(0);
p.sta_abs(0xD020);
p.sta_abs(0xD021);

game_end()

//  SAVE AND PREP ALARM 
var export_dir = "C:\\C64Temp\\"; 
var file_name = "program.prg";
full_save_path = export_dir + file_name; 
p.save(full_save_path);

