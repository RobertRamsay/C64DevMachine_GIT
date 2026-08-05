/// @desc Handle LMB clicks for MACRO_REU DIRECT/ASSET modes.
function scr_node_step_macro_reu(_draw_x) {
    var _hh=24, _lh=16, _inst=instructions[0], _lx=_draw_x+8, _rx=_draw_x+width-6, _cy=y+_hh+4;
    while (array_length(_inst) < 12) array_push(_inst, (array_length(_inst) >= 10) ? "" : 0);
    var _open_hex = function(_idx,_digits) { with (obj_workspace_manager) { is_entering_text=true; input_target_node=other.id; input_target_index=_idx; var _h=string_upper(decimal_to_hex(real(other.instructions[0][_idx]))); while(string_length(_h)<_digits)_h="0"+_h; current_input_string="$"+_h; keyboard_string=""; cursor_pos=string_length(current_input_string); } };
    var _open_num = function(_idx) { with (obj_workspace_manager) { is_entering_text=true; input_target_node=other.id; input_target_index=_idx; current_input_string=string(real(other.instructions[0][_idx])); keyboard_string=""; cursor_pos=string_length(current_input_string); } };
    var _hit = function(_x1,_x2,_yy) { return point_in_rectangle(mouse_x,mouse_y,_x1,_yy+4,_x2,_yy+10); };

    if (_hit(_lx+44,_rx,_cy)) { instructions[0][9]=(real(_inst[9])==1)?0:1; if(instructions[0][9]==1)instructions[0][1]=1; global.addresses_dirty=true; scr_c64_do_update_addresses(); exit; }
    _cy += _lh;
    if (real(_inst[9]) == 1) {
        if (_hit(_lx+44,_rx,_cy)) {
            var _matches=[]; if(instance_exists(obj_asset_manager)){var _am=obj_asset_manager;for(var _i=0;_i<ds_list_size(_am.asset_list);_i++){var _a=ds_list_find_value(_am.asset_list,_i);if(_a.type=="LOAD_REU")array_push(_matches,_a.name);}}
            if(array_length(_matches)>0){var _at=-1;for(var _i=0;_i<array_length(_matches);_i++)if(_matches[_i]==string(_inst[10])){_at=_i;break;}_at=(_at+1) mod array_length(_matches);instructions[0][10]=_matches[_at];instructions[0][11]="";} exit;
        } _cy += _lh;
        if (_hit(_lx+44,_rx,_cy)) {
            var _matches=[];var _m=scr_reu_find_asset(string(_inst[10]));if(!is_undefined(_m)&&variable_struct_exists(_m,"linked_assets")){for(var _i=0;_i<array_length(_m.linked_assets);_i++)array_push(_matches,_m.linked_assets[_i].asset_name);}
            if(array_length(_matches)>0){var _at=-1;for(var _i=0;_i<array_length(_matches);_i++)if(_matches[_i]==string(_inst[11])){_at=_i;break;}_at=(_at+1) mod array_length(_matches);instructions[0][11]=_matches[_at];} exit;
        } _cy += _lh*4;
    } else {
        if(_hit(_lx+30,_rx,_cy)){instructions[0][1]=(real(_inst[1])+1) mod 4;exit;} _cy+=_lh;
        if(_hit(_lx+44,_rx,_cy)){_open_hex(2,4);exit;} _cy+=_lh;
        if(_hit(_lx+44,_rx,_cy)){_open_hex(3,4);exit;} _cy+=_lh;
        if(_hit(_lx+44,_rx,_cy)){_open_num(4);exit;} _cy+=_lh;
        if(_hit(_lx+44,_rx,_cy)){_open_hex(5,4);exit;} _cy+=_lh;
    }
    if(_hit(_lx,_rx,_cy)){instructions[0][6]=(real(_inst[6])==1)?0:1;exit;} _cy+=_lh;
    if(_hit(_lx,_rx,_cy)){instructions[0][7]=(real(_inst[7])==1)?0:1;exit;} _cy+=_lh;
    if(_hit(_lx,_rx,_cy)){instructions[0][8]=(real(_inst[8])==1)?0:1;exit;}
}
