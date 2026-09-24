/// Native SFX authoring is deliberately separate from imported GoatTracker SFX_DATA.
function scr_sfx_maker_defaults(_a) {
    var _m = _a.meta;
    if (!variable_struct_exists(_m, "instruments")) _m.instruments = [];
    if (!variable_struct_exists(_m, "sel_instr")) _m.sel_instr = 0;
    if (!variable_struct_exists(_m, "patterns")) _m.patterns = [];
    _m.sfx_asset_name = _a.name;
    var _defaults = {instr_list_scroll:0, instr_edit_active:false, instr_edit_buf:"", instr_edit_cursor:0,
        instr_name_edit_active:false, instr_name_edit_buf:"", instr_name_edit_cursor:0,
        instr_last_click_time:-10000, instr_last_click_idx:-1, instr_name_edit_opened_time:-10000,
        instr_edit_opened_time:-10000, instr_text_scroll:0, sfx_chip:0};
    var _keys = variable_struct_get_names(_defaults);
    for (var _i=0; _i<array_length(_keys); _i++) if (!variable_struct_exists(_m,_keys[_i]))
        variable_struct_set(_m,_keys[_i],variable_struct_get(_defaults,_keys[_i]));
    for (var _i=0; _i<array_length(_m.instruments); _i++) {
        var _e=_m.instruments[_i];
        var _d={attack:0,decay:4,sustain:8,release:1,pulse_width:2048,sfx_note:"C-5",sfx_priority:1};
        var _k=variable_struct_get_names(_d);
        for(var _j=0;_j<array_length(_k);_j++) if(!variable_struct_exists(_e,_k[_j]))
            variable_struct_set(_e,_k[_j],variable_struct_get(_d,_k[_j]));
    }
}

function scr_sfx_maker_create(_a) {
    _a.meta={instruments:[
        {name:"LASER",text:"$21,D2,N-12,D2,N-24,D2,---",sfx_note:"C-6",sfx_priority:1},
        {name:"EXPLOSION",text:"$81,D4,N-12,D4,N-24,D6,---",sfx_note:"C-4",sfx_priority:2},
        {name:"PICKUP",text:"$11,D3,N+7,D3,N+12,D4,---",sfx_note:"C-5",sfx_priority:1}
    ],sel_instr:0,sfx_chip:0};
    scr_sfx_maker_defaults(_a);
}

function scr_sfx_maker_button(_x,_y,_w,_text,_mx,_my) {
    var _hot=point_in_rectangle(_mx,_my,_x,_y,_x+_w,_y+26);
    draw_set_color(_hot?make_color_rgb(65,80,100):make_color_rgb(30,38,52));
    draw_rectangle(_x,_y,_x+_w,_y+26,false);
    draw_set_color(c_white);draw_text_l(_x+8,_y+5,_text);
    return _hot && mouse_check_button_pressed(mb_left);
}

function scr_sfx_maker_editor(_a,_x1,_y1,_x2,_y2,_cy,_mx,_my) {
    scr_sfx_maker_defaults(_a);
    var _m=_a.meta;
    draw_set_font_l(fnt_c64_tiny);draw_set_color(c_aqua);
    draw_text_l(_x1+24,_cy,"SFX MAKER - independent sound effects");
    scr_sound_editor_draw_instruments(_m,_x1+24,_cy+48,_mx,_my);
    var _rx=_x1+420, _ry=_cy+48;
    draw_set_font_l(fnt_c64_tiny);
    if (_m.sel_instr>=0 && _m.sel_instr<array_length(_m.instruments)) {
        var _e=_m.instruments[_m.sel_instr];
        // ADD/PASTE may have created this effect during the shared panel draw.
        scr_sfx_maker_defaults(_a);
        if(scr_sfx_maker_button(_rx,_ry,110,"PREVIEW",_mx,_my)) {
            if(_m.instr_edit_active) scr_sound_editor_commit_instrument(_m,_e);
            scr_sound_instrument_preview_play(_e,_e.sfx_note,2,5);
        }
        if(scr_sfx_maker_button(_rx+120,_ry,100,"STOP",_mx,_my)) scr_sound_preview_free_channel(2);
        _ry+=42;
        draw_set_color(c_white);draw_text_l(_rx,_ry,"BASE NOTE: "+_e.sfx_note);
        if(scr_sfx_maker_button(_rx,_ry+24,100,"NOTE -",_mx,_my)) {
            var _n=clamp(scr_sid_song_note_index(_e.sfx_note)-1,0,95);
            var _names=["C-","C#","D-","D#","E-","F-","F#","G-","G#","A-","A#","B-"];
            _e.sfx_note=_names[_n mod 12]+string(_n div 12);global.addresses_dirty=true;global.undo_dirty=true;
        }
        if(scr_sfx_maker_button(_rx+110,_ry+24,100,"NOTE +",_mx,_my)) {
            var _n=clamp(scr_sid_song_note_index(_e.sfx_note)+1,0,95);
            var _names=["C-","C#","D-","D#","E-","F-","F#","G-","G#","A-","A#","B-"];
            _e.sfx_note=_names[_n mod 12]+string(_n div 12);global.addresses_dirty=true;global.undo_dirty=true;
        }
        _ry+=72;
        if(scr_sfx_maker_button(_rx,_ry,250,"PRIORITY: "+string(_e.sfx_priority),_mx,_my)) {
            _e.sfx_priority=(_e.sfx_priority mod 15)+1;global.addresses_dirty=true;global.undo_dirty=true;
        }
        _ry+=42;
        var _frames=scr_sfx_maker_frames(_e);
        draw_set_color(c_white);draw_text_l(_rx,_ry,"LENGTH: "+string(array_length(_frames))+" FRAMES (PAL)");
    }
    _ry=_cy+320;
    if(scr_sfx_maker_button(_rx,_ry,250,"SID CHIP: "+string(_m.sfx_chip+1),_mx,_my)) {
        _m.sfx_chip=(_m.sfx_chip+1) mod 4;global.addresses_dirty=true;global.undo_dirty=true;
    }
    draw_set_color(c_silver);
    draw_text_ext_l(_rx,_ry+46,"Use an SFX macro to choose this asset, effect and voice.\nPLAY triggers it. UPDATE runs once per frame. STOP silences it.\n\nReserve that voice in Music Maker using its VOICES buttons.\nFor example: music 1 + 2, effects 3.\n\nHigher priority interrupts lower priority. Equal priority restarts.\nLower priority is ignored while a stronger effect is active.\n\nEffects finish automatically (maximum 255 frames).\nThe music position is never reset.\n\nSFX DATA remains the separate GoatTracker/Zed import path.\nUse COPY / PASTE to share instruments with Music Maker.",22,700);
    draw_set_color(c_white);
}

/// Pre-expand the existing instrument language into bounded per-frame SID values.
/// No new instrument language, no runtime zero-page allocation, no memory banking.
function scr_sfx_maker_frames(_e) {
    var _b=scr_instrument_parse(_e.text).bytes;
    var _base=variable_struct_exists(_e,"sfx_note")?_e.sfx_note:"C-5";
    var _hz=scr_note_name_to_hz(_base), _wave=0x21, _freq=round(_hz*16777216/985248);
    var _pc=0, _frames=[], _steps=0;
    while(_pc<array_length(_b) && array_length(_frames)<240 && _steps++<4096) {
        var _op=_b[_pc++];
        if(_op==4) break;
        if(_pc>=array_length(_b)) break;
        var _v=_b[_pc++];
        if(_op==0) _wave=_v;
        else if(_op==1) {_v=(_v>127)?_v-256:_v;_freq=clamp(round(_hz*power(2,_v/12)*16777216/985248),0,65535);}
        else if(_op==2) for(var _t=0;_t<_v && array_length(_frames)<240;_t++) array_push(_frames,[_freq&255,(_freq>>8)&255,_wave]);
        else if(_op==3) _pc=_v;
        else break;
    }
    // Release with the last waveform before explicitly silencing the voice.
    var _release=variable_struct_exists(_e,"release")?clamp(_e.release,0,15):1;
    var _release_ms=[6,24,48,72,114,168,204,240,300,750,1500,2400,3000,9000,15000,24000];
    var _tail=min(255-array_length(_frames),max(1,ceil(_release_ms[_release]/20)));
    for(var _t=0;_t<_tail;_t++) array_push(_frames,[_freq&255,(_freq>>8)&255,_wave&254]);
    return _frames;
}

function scr_sfx_maker_compile(_list,_node,_asset,_voice) {
    var _aidx=ds_list_find_index(obj_asset_manager.asset_list,_asset);
    var _key="sfxm"+string(_aidx)+"v"+string(_voice)+"_";
    var _mode=(array_length(_node.instructions[0])>4)?real(_node.instructions[0][4]):0;
    var _index=real(_node.instructions[0][2]);
    if(_mode==0 && (_index<0 || _index>=min(64,array_length(_asset.meta.instruments)))) return _list;
    var _action=_mode==1?"update":(_mode==2?"stop":(_mode==3?"init":"trigger"+string(_index)));
    var _exists=false;
    for(var _i=0;_i<array_length(_list);_i++) if(_list[_i][0]=="label" && _list[_i][1]==_key+"update") {_exists=true;break;}
    if(!_exists) {
        var _chip=variable_struct_exists(_asset.meta,"sfx_chip")?clamp(_asset.meta.sfx_chip,0,3):0;
        var _sid=0xd400+_chip*32+(_voice-1)*7;
        array_push(_list,["jmp_abs",_key+"after",_node]);
        array_push(_list,["label",_key+"active"],["byte",0,_node],["label",_key+"cursor"],["byte",0,_node],["label",_key+"priority"],["byte",0,_node]);
        array_push(_list,["label",_key+"init"],["lda_imm",15,_node],["sta_abs",0xd418+_chip*32,_node]);
        array_push(_list,["label",_key+"stop"],["lda_imm",0,_node],["sta_lab",_key+"active",_node],["sta_lab",_key+"priority",_node],["sta_abs",_sid+4,_node],["rts",0,_node]);
        array_push(_list,["label",_key+"update"],["lda_lab",_key+"active",_node],["bne",_key+"dispatch",_node],["rts",0,_node],["label",_key+"dispatch"]);
        for(var _i=0;_i<min(64,array_length(_asset.meta.instruments));_i++) {
            array_push(_list,["cmp_imm",_i+1,_node],["bne",_key+"next"+string(_i),_node],["jmp_abs",_key+"frame"+string(_i),_node],["label",_key+"next"+string(_i)]);
        }
        array_push(_list,["jmp_abs",_key+"stop",_node]);
        for(var _i=0;_i<min(64,array_length(_asset.meta.instruments));_i++) {
            var _e=_asset.meta.instruments[_i],_frames=scr_sfx_maker_frames(_e),_tag=string(_i);
            var _priority=variable_struct_exists(_e,"sfx_priority")?clamp(_e.sfx_priority,1,15):1;
            array_push(_list,["label",_key+"trigger"+_tag],["lda_lab",_key+"priority",_node],["cmp_imm",_priority+1,_node],["bcc",_key+"accept"+_tag,_node],["rts",0,_node],["label",_key+"accept"+_tag]);
            array_push(_list,["lda_imm",_i+1,_node],["sta_lab",_key+"active",_node],["lda_imm",_priority,_node],["sta_lab",_key+"priority",_node],["lda_imm",0,_node],["sta_lab",_key+"cursor",_node],["sta_abs",_sid+4,_node]);
            var _pw=variable_struct_exists(_e,"pulse_width")?_e.pulse_width:2048;
            var _ad=((variable_struct_exists(_e,"attack")?_e.attack:0)<<4)|(variable_struct_exists(_e,"decay")?_e.decay:4);
            var _sr=((variable_struct_exists(_e,"sustain")?_e.sustain:8)<<4)|(variable_struct_exists(_e,"release")?_e.release:1);
            var _regs=[[_sid+2,_pw&255],[_sid+3,(_pw>>8)&15],[_sid+5,_ad],[_sid+6,_sr]];
            for(var _j=0;_j<4;_j++) array_push(_list,["lda_imm",_regs[_j][1],_node],["sta_abs",_regs[_j][0],_node]);
            array_push(_list,["rts",0,_node],["label",_key+"frame"+_tag],["ldx_lab",_key+"cursor",_node],["cpx_imm",array_length(_frames),_node],["bcc",_key+"write"+_tag,_node],["jmp_abs",_key+"stop",_node],["label",_key+"write"+_tag]);
            for(var _j=0;_j<3;_j++) array_push(_list,["lda_abx",_key+"table"+_tag+"_"+string(_j),_node],["sta_abs",_sid+(_j==2?4:_j),_node]);
            array_push(_list,["inc_lab",_key+"cursor",_node],["rts",0,_node]);
            for(var _j=0;_j<3;_j++) {
                array_push(_list,["label",_key+"table"+_tag+"_"+string(_j)]);
                for(var _f=0;_f<array_length(_frames);_f++) array_push(_list,["byte",_frames[_f][_j],_node]);
            }
        }
        // An empty bank is valid: PLAY is a no-op, UPDATE/STOP remain usable.
        if(array_length(_asset.meta.instruments)==0) array_push(_list,["label",_key+"trigger0"],["rts",0,_node]);
        array_push(_list,["label",_key+"after"]);
    }
    array_push(_list,["php",0,_node],["sei",0,_node],["jsr",_key+_action,_node],["plp",0,_node]);
    return _list;
}

function scr_sfx_maker_node_draw(_dx,_a) {
    var _i=instructions[0];
    var _mode=array_length(_i)>4?clamp(real(_i[4]),0,3):0;
    var _names=["PLAY","UPDATE","STOP","INIT"];
    var _fx=clamp(real(_i[2]),0,max(0,array_length(_a.meta.instruments)-1));
    var _valid=real(_i[2])>=0 && real(_i[2])<array_length(_a.meta.instruments);
    var _values=[_a.name,_valid?_a.meta.instruments[_fx].name:"SELECT EFFECT",string(_i[3]),_names[_mode]];
    var _labels=["ASSET:","EFFECT:","VOICE:","ACTION:"];
    draw_set_font_l(fnt_c64_tiny);draw_set_halign(fa_left);
    for(var _r=0;_r<4;_r++) {
        draw_set_color(c_aqua);scr_node_macro_text_l(_dx+6,y+30+22*_r,_labels[_r]);
        draw_set_color(c_white);scr_node_macro_text_l(_dx+72,y+30+22*_r,_values[_r]);
    }
    draw_set_color(c_silver);scr_node_macro_text_l(_dx+6,y+120,_mode==1?"ONCE PER FRAME":(_mode==3?"ONCE AT START":"SFX MAKER"));
    draw_set_color(c_white);
}
