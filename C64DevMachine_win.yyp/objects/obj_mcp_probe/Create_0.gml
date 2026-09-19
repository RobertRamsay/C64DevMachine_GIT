/// Optional MCP proof of concept. No socket exists until the user opts in.
/// Ctrl+Shift+F12 reads a pairing key from the clipboard, or disconnects.
probe_socket = -1;
probe_state = "off";
probe_token = "";
probe_rx = -1;
probe_rx_len = 0;
probe_queue = [];
probe_last_rx = 0;
probe_last_id = 0;
probe_last_wire = "";
probe_last_reply = "";
probe_status = "OFF - Ctrl+Shift+F12 to pair";
probe_notice_until = current_time + 6000;
probe_max_line = 32768;

// --- MCP-CON one-click setup (Pro only) ------------------------------------
// The button runs tools/cdm-mcp/setup-mcp.bat (setup-mcp.command on macOS),
// which checks for Node.js, registers the bridge with any installed assistant
// CLI, and leaves a pairing key for this editor to collect. The helper is
// launched hidden and detached, so the editor never blocks; progress is read
// back from a two-line status file.
setup_state       = "idle";   // idle | running | done | failed
setup_status      = "";       // status token from the helper
setup_detail      = "";       // one line of UI-safe detail from the helper
setup_poll_at     = 0;
setup_deadline    = 0;
setup_hover       = false;
setup_btn_x1      = 0;
setup_btn_y1      = 0;
setup_btn_x2      = 0;
setup_btn_y2      = 0;
setup_status_path = game_save_id + "mcp-setup-status.txt";
setup_pair_path   = game_save_id + "mcp-pair.txt";
// When set, probe_start uses this instead of touching the clipboard.
probe_pair_key    = "";

probe_stop = function(_reason) {
    if (probe_socket >= 0) network_destroy(probe_socket);
    probe_socket = -1;
    if (probe_rx >= 0 && buffer_exists(probe_rx)) buffer_delete(probe_rx);
    probe_rx = -1;
    probe_rx_len = 0;
    probe_queue = [];
    probe_token = "";
    probe_state = "off";
    probe_last_wire = "";
    probe_last_reply = "";
    probe_status = _reason;
    probe_notice_until = current_time + 10000;
    probe_retry_at = current_time + 5000;
};

// Defensive guard if this object is ever instantiated outside Pro startup.
if (!variable_global_exists("lite") || global.lite != 0) {
    instance_destroy();
    exit;
}

probe_send = function(_text) {
    if (probe_socket < 0) return false;
    // buffer_tell counts UTF-8 bytes, not characters. No trailing NUL is sent.
    var _buf = buffer_create(1024, buffer_grow, 1);
    buffer_write(_buf, buffer_text, _text + "\n");
    var _size = buffer_tell(_buf);
    if (_size > 65536) {
        buffer_delete(_buf);
        probe_stop("OFF - reply exceeded limit");
        return false;
    }
    var _sent = network_send_raw(probe_socket, _buf, _size);
    buffer_delete(_buf);
    // Fail closed on partial sends. Never resend a mutation automatically.
    if (_sent != _size) {
        probe_stop("OFF - send failed; check the project before retrying");
        return false;
    }
    return true;
};

// MCP v0.2 project operations. All mutations execute on the editor main thread.
probe_node_types = ["NORMAL","LABEL","COMMENT","ORG","MACRO_DISPLAY","MACRO_WAIT","MACRO_NOP_REPEAT","MACRO_VWAIT","MACRO_PRINT","MACRO_PRINT_EXT","MACRO_SPR","MACRO_METAMAP","MACRO_SID","MACRO_TRACK","MACRO_SCROLL","MACRO_METASCROLL","MACRO_VSCROLL","MACRO_TEXT_SCROLL","MACRO_MOUSE","MACRO_LETTERS","MACRO_FNNUMBERS","MACRO_MISCKEYS","MACRO_JOY","MACRO_BMP","DATA_SID","SPR64","BITMAP_KLA","MACRO_VIC","RAW_DATA","NAMED_LOC","GET_VAR","SET_VAR","INC_VAR","DEC_VAR","COPY_VAR","MACRO_PRIORITY","MACRO_SPR_ENABLE","MACRO_SPR_EXPAND","MACRO_FLIP_X","BANK_SWITCH","MACRO_REU","COND_IF","COND_IF_WORD","MACRO_CODE","MACRO_SEEK","MACRO_MOVE_BMP_BLOCK","MACRO_PLACE_CHAR","MACRO_CLR_SCREEN","MACRO_MATH","MACRO_GET_CHAR","MACRO_SID_SOUND","MACRO_HUD","MACRO_SID_SONG","MACRO_SID_PAUSE","MACRO_VOI64_MASTER","MACRO_VOI64_SAY","MACRO_RANDOM","MACRO_MOVE","MACRO_MAP","MACRO_MAP_SWITCH","MACRO_CHR","MACRO_LOADER","MACRO_SAVE_GAME","MACRO_LOAD_GAME","MACRO_IRQ","MACRO_IRQ_HANDLER","MACRO_COLLISION","MACRO_COLL_ADV","MACRO_COLL_LINE","MACRO_ANIM","MACRO_SFX","MACRO_MOVE_MEM","MACRO_VECTOR_PAGE","MACRO_VECTOR_BMP","MACRO_CLEAR_BMP_RECT"];
probe_restart_pending = false;
probe_build = {id:0, state:"idle", run:false, output:"", message:""};

probe_repair_uids = function() {
    // Legacy startup reset the allocator after creating INIT, producing duplicates.
    var _seen = {};
    var _next = variable_global_exists("next_stable_uid") ? global.next_stable_uid : 100000;
    with (obj_c64_node) _next = max(_next, stable_uid + 1);
    with (obj_c64_node) {
        var _key = string(stable_uid);
        if (stable_uid < 0 || variable_struct_exists(_seen, _key)) {
            stable_uid = _next++; _key = string(stable_uid);
        }
        _seen[$ _key] = true;
    }
    global.next_stable_uid = _next;
};

probe_workspace_key = function() {
    probe_repair_uids();
    // Includes manual edits, wiring, reorder, undo/load and instruction changes.
    var _state = [];
    with (obj_c64_node) array_push(_state, [string(id), stable_uid, node_type,
        node_title, custom_title, x, y, is_connected, string(org_parent),
        pc_address, instructions, wire_out_target, wire_in_source]);
    if(instance_exists(obj_asset_manager)) {
        var _list=obj_asset_manager.asset_list;
        for(var _i=0;_i<ds_list_size(_list);_i++) {
            var _a=_list[| _i];
            array_push(_state,[_a.name,_a.type,_a.address,
                buffer_exists(_a.buffer)?buffer_get_size(_a.buffer):0,
                variable_struct_exists(_a.meta,"byte_string")?_a.meta.byte_string:"",
                variable_struct_exists(_a.meta,"text")?_a.meta.text:""]);
        }
    }
    return md5_string_utf8(json_stringify(_state));
};

probe_find = function(_uid) {
    if (!is_real(_uid) || _uid < 0 || _uid != floor(_uid)) throw "Invalid node UID.";
    var _found = noone;
    with (obj_c64_node) if (stable_uid == _uid) { _found = id; break; }
    if (!instance_exists(_found)) throw "Node not found; inspect the project again.";
    return _found;
};

probe_refresh = function(_node) {
    if (instance_exists(_node)) {
        _node.height_dirty = true;
        if (_node.node_type == "COMMENT") scr_comment_sync_layout(_node);
        if (_node.node_type == "MACRO_CODE") {
            var _code = string(_node.instructions[0][1]);
            var _stats = scr_parse_asm_byte_count(_code);
            _node.code_cached_bytes = _stats[0];
            _node.code_cached_cycles = _stats[1];
            _node.code_cached_lines = array_length(string_split(_code,"\n"));
            _node.code_cache_dirty = true;
        }
    }
    global.addresses_dirty = true;
    global.relayout_frames = 2;
    obj_workspace_manager.flow_overlay_dirty = true;
    obj_workspace_manager.alarm[1] = 6;
};

probe_before_edit = function() {
    if (global.undo_states < 2) throw "Enable at least two undo states before editing via MCP.";
    scr_undo_snapshot();
};
probe_after_edit = function() {
    global.manual_saved = false;
    global.autosave_dirty = true;
    global.undo_dirty = false;
    scr_undo_snapshot();
    if (global.autosave_mode != 3) obj_workspace_manager.alarm[4] = max(obj_workspace_manager.alarm[4],game_get_speed(gamespeed_fps)*5);
};

probe_validate_fields = function(_node, _args) {
    var _type = _node.node_type;
    if (variable_struct_exists(_args,"text")) {
        if (!is_string(_args.text) || string_byte_length(_args.text) > 24000) throw "Text too large.";
        if (_type != "COMMENT" && _type != "MACRO_CODE" && _type != "LABEL" && _type != "RAW_DATA") throw "Use instructions to configure this node type.";
        if (variable_struct_exists(_args,"instructions")) throw "Supply text or instructions, not both.";
        if (_type == "LABEL" && (string_length(_args.text) == 0 || string_pos("\n",_args.text)>0)) throw "Label must be one non-empty line.";
    }
    if (variable_struct_exists(_args,"address")) {
        if (_type != "ORG" || !is_real(_args.address) || _args.address < 0 || _args.address > 65535 || _args.address != floor(_args.address)) throw "Address requires an ORG and a 16-bit integer.";
    }
    if (variable_struct_exists(_args,"title") && (!is_string(_args.title) || string_length(_args.title)>100)) throw "Invalid title.";
    if (variable_struct_exists(_args,"x") && (!is_real(_args.x) || is_nan(_args.x) || _args.x < 200 || _args.x > 1000000)) throw "Invalid X coordinate.";
    if (variable_struct_exists(_args,"y") && (!is_real(_args.y) || is_nan(_args.y) || abs(_args.y)>1000000)) throw "Invalid Y coordinate.";
    if (variable_struct_exists(_args,"instructions")) {
        var _rows = _args.instructions;
        if (!is_array(_rows) || array_length(_rows)<1 || array_length(_rows)>256) throw "Instructions require 1..256 rows.";
        var _normal = _type == "NORMAL" || _type == "INIT";
        if (!_normal && array_length(_rows) != array_length(_node.instructions)) throw "Preserve the native macro row count; inspect read_node first.";
        for (var _i=0; _i<array_length(_rows); _i++) {
            var _row = _rows[_i];
            if (!is_array(_row) || array_length(_row)<2 || array_length(_row)>64) throw "Invalid instruction row.";
            if (_normal) {
                if (array_length(_row)!=2 || !is_string(_row[0]) || obj_opCodeManager.get_size(string_lower(_row[0]))<=0) throw "Unknown opcode; use MACRO_CODE text for assembler labels and directives.";
            } else {
                if (array_length(_row)!=array_length(_node.instructions[_i])) throw "Preserve the native macro cell count.";
                if (_row[0] != _node.instructions[_i][0]) throw "Preserve native instruction row tags.";
            }
            for (var _j=0; _j<array_length(_row); _j++) {
                var _v=_row[_j];
                if (!is_string(_v) && !is_real(_v)) throw "Instruction values must be text or numbers.";
                if (is_real(_v) && (is_nan(_v) || abs(_v)>16777216)) throw "Invalid instruction number.";
                if (is_string(_v) && string_byte_length(_v)>24000) throw "Instruction text too large.";
                if (!_normal && is_string(_v)!=is_string(_node.instructions[_i][_j])) throw "Preserve native macro value types.";
            }
        }
    }
};

probe_set_fields = function(_node,_args) {
    if (variable_struct_exists(_args,"title")) {
        _node.node_title = _args.title;
        _node.custom_title = _args.title;
        if (_node.node_type == "MACRO_CODE") _node.code_descriptor = _args.title;
    }
    if (variable_struct_exists(_args,"text")) _node.instructions[0][1] = _args.text;
    if (variable_struct_exists(_args,"instructions")) _node.instructions = variable_clone(_args.instructions);
    if (variable_struct_exists(_args,"x")) _node.x = _args.x;
    if (variable_struct_exists(_args,"y")) _node.y = _args.y;
    if (variable_struct_exists(_args,"address")) {
        _node.pc_address = _args.address;
        _node.proxy_address = _args.address;
        _node.proxy = false;
        _node.instructions = [["org",_args.address]];
    }
    probe_refresh(_node);
};

probe_check_connection = function(_node,_after) {
    if (_node == _after) throw "Cannot connect a node to itself.";
    if (_node.node_type == "INIT" || _node.node_type == "ORG" || _node.macro_owner != noone) throw "Connect code/data nodes; INIT and ORG are anchors.";
    if (_after.macro_owner != noone) throw "Cannot attach to an internal macro child.";
    if (_after.node_type != "INIT" && _after.node_type != "ORG" && !_after.is_connected) throw "Target is not attached to a spine.";
    if (_node.node_type == "NAMED_LOC" || _node.node_type == "NEW_STR") {
        var _owner = _after.node_type == "ORG" ? _after : _after.org_parent;
        if (!instance_exists(_owner) || _owner.node_title != "VARIABLES") throw "Variables must attach inside VARIABLES.";
    }
};

probe_connect = function(_node,_after) {
    var _owner = _after.node_type == "ORG" ? _after : _after.org_parent;
    var _nodes = [];
    with (obj_c64_node) {
        if (id != _node && is_connected && org_parent == _owner && macro_owner == noone && node_type != "ORG") array_push(_nodes,id);
    }
    array_sort(_nodes,function(_a,_b){return _a.y-_b.y;});
    var _yy = _after.y + max(20,_after.height);
    var _delta = max(20,_node.height);
    for (var _i=0; _i<array_length(_nodes); _i++) {
        var _n = _nodes[_i];
        if (_n != _after && _n.y > _after.y) { _n.y = max(_n.y,_yy) + _delta; }
    }
    _node.x = _after.x;
    _node.y = _yy;
    _node.org_parent = _owner;
    _node.is_connected = true;
    _node.is_free_node = false;
    _node.has_ever_connected = true;
    probe_refresh(_node);
};

probe_project_path = function(_path) {
    if (!is_string(_path) || string_length(_path)<6 || string_length(_path)>1024 || string_lower(filename_ext(_path)) != ".json") throw "Use an absolute .json project path.";
    if (string_char_at(_path,1)!="/" && !(string_length(_path)>3 && string_char_at(_path,2)==":")) throw "Use an absolute project path.";
    if (!directory_exists(filename_dir(_path))) throw "Project folder does not exist.";
    return _path;
};

probe_recovery_copy = function() {
    var _wm = instance_find(obj_workspace_manager,0);
    var _old_path = global.workspace_path;
    var _old_name = global.current_filename;
    var _saved = global.manual_saved;
    var _dirty = global.autosave_dirty;
    var _path = working_directory + "temp/mcp-recovery-" + string(get_timer()) + ".json";
    if (!directory_exists(working_directory+"temp/")) directory_create(working_directory+"temp/");
    with (_wm) scr_save_workspace_as_path(_path);
    global.workspace_path=_old_path; global.current_filename=_old_name;
    global.manual_saved=_saved; global.autosave_dirty=_dirty;
    window_set_caption(game_project_name + " - " + _old_name);
    if (!file_exists(_path)) throw "Recovery save failed; current project retained.";
    return _path;
};

probe_project_command = function(_method,_args) {
    var _wm = instance_find(obj_workspace_manager,0);
    if (_method == "assets") {
        var _items=[];
        var _list=obj_asset_manager.asset_list;
        var _offset=variable_struct_exists(_args,"offset") ? _args.offset : 0;
        var _limit=variable_struct_exists(_args,"limit") ? _args.limit : 50;
        for(var _i=_offset;_i<min(ds_list_size(_list),_offset+_limit);_i++) {
            var _a=_list[| _i];
            array_push(_items,{name:_a.name,type:_a.type,address:_a.address,size:buffer_exists(_a.buffer)?buffer_get_size(_a.buffer):0});
        }
        return {assets:_items,next_offset:_offset+array_length(_items),has_more:_offset+array_length(_items)<ds_list_size(_list),workspace_key:probe_workspace_key()};
    }
    if (_method == "put_data_asset") {
        if (_args.type!="BYTE_DATA" && _args.type!="TEXT_DATA") throw "Use BYTE_DATA or TEXT_DATA.";
        if (!is_string(_args.name) || string_length(_args.name)<1 || string_length(_args.name)>64) throw "Invalid asset name.";
        if (!is_real(_args.address) || _args.address<0 || _args.address>65535 || floor(_args.address)!=_args.address) throw "Invalid asset address.";
        var _bytes=variable_struct_exists(_args,"bytes") ? _args.bytes : [];
        var _text=variable_struct_exists(_args,"text") ? _args.text : "";
        if (_args.type=="BYTE_DATA") {
            if (variable_struct_exists(_args,"text") || !is_array(_bytes) || array_length(_bytes)<1 || array_length(_bytes)>4096) throw "BYTE_DATA requires 1..4096 bytes.";
            for(var _i=0;_i<array_length(_bytes);_i++) if(!is_real(_bytes[_i]) || _bytes[_i]!=floor(_bytes[_i]) || _bytes[_i]<0 || _bytes[_i]>255) throw "Invalid byte.";
            if(_args.address+array_length(_bytes)>65536) throw "Asset extends beyond C64 memory.";
        } else {
            if (variable_struct_exists(_args,"bytes") || !is_string(_text) || string_length(_text)>4096) throw "TEXT_DATA requires text of at most 4096 characters.";
            if(_args.address+string_length(_text)+1>65536) throw "Asset extends beyond C64 memory.";
        }
        var _list=obj_asset_manager.asset_list;
        var _asset=undefined;
        for(var _i=0;_i<ds_list_size(_list);_i++) {
            var _a=_list[| _i];
            if(string_upper(_a.name)==string_upper(_args.name)) { _asset=_a;break; }
        }
        if(!is_undefined(_asset)) {
            if(!variable_struct_exists(_args,"replace") || _args.replace!=true) throw "Asset exists; set replace=true to replace it.";
            if(_asset.type!=_args.type) throw "Cannot change an existing asset's type.";
        }
        probe_before_edit();
        var _created=is_undefined(_asset);
        if(_created) _asset={name:_args.name,type:_args.type,file:"",address:_args.address,buffer:-1,load_later:false,d64_filename:"",reu_filename:"",reu_size:0,reu_used:0,linked_assets:[],meta:{}};
        _asset.address=_args.address;
        _asset.meta.inline_edit_open=false;
        _asset.meta.inline_edit_cursor=0;
        _asset.meta.inline_edit_scroll_y=0;
        _asset.meta.inline_edit_sel_start=-1;
        _asset.meta.inline_edit_sel_end=-1;
        _asset.meta.inline_edit_blink=0;
        _asset.meta.inline_edit_key_timer=0;
        if(_args.type=="BYTE_DATA") {
            var _parts=[];
            for(var _i=0;_i<array_length(_bytes);_i++) array_push(_parts,"$"+decimal_to_hex(_bytes[_i]));
            _asset.meta.byte_string=string_join_ext(", ",_parts);
            _asset.meta.inline_edit_text=_asset.meta.byte_string;
            _asset.meta.is_save_file=false;
            _asset.meta.save_file_size=256;
            scr_asset_byte_data_flush(_asset);
        } else {
            _asset.meta.text=_text;
            _asset.meta.inline_edit_text=_text;
            scr_asset_text_flush(_asset);
        }
        if(_created) ds_list_add(_list,_asset);
        probe_refresh(noone);probe_after_edit();
        return {name:_asset.name,type:_asset.type,size:buffer_get_size(_asset.buffer),workspace_key:probe_workspace_key()};
    }

    if (_method == "read_node") {
        var _node = probe_find(_args.uid);
        var _info = probe_node_info(_node);
        _info.instructions = _node.instructions;
        _info.custom_title = _node.custom_title;
        _info.workspace_key = probe_workspace_key();
        if (string_byte_length(json_stringify(_info))>28000) throw "Node too large for one reply.";
        return _info;
    }
    if (_method == "build") {
        if (!variable_struct_exists(_args,"run") || !is_bool(_args.run)) throw "run must be boolean.";
        if (_wm.trigger_build || _wm.vice_launch_pending || global.asset_reload_in_progress) throw "Another build, launch or asset reload is active.";
        if(global.lite==1) {
            var _premium=false;
            with(obj_c64_node) if(is_connected && (node_type=="MACRO_CODE" || node_type=="MACRO_IRQ" || node_type=="MACRO_MOVE_MEM")) _premium=true;
            if(_premium) throw "The native LITE edition cannot build premium nodes.";
        }
        if (_args.run && scr_resolve_vice_path()=="") throw "VICE executable not found. Configure the native VICE path first.";
        probe_build = {id:probe_build.id+1,state:"queued",run:_args.run,output:"",message:"Queued native F5 build. Poll build_status."};
        _wm.silent_build = !_args.run;
        _wm.trigger_c64u = false;
        _wm.pending_dump = false;
        _wm.trigger_build = true;
        return probe_build;
    }
    if (_method == "save_project") {
        var _path = probe_project_path(_args.path);
        if (file_exists(_path) && (!variable_struct_exists(_args,"overwrite") || _args.overwrite!=true)) throw "File exists; use overwrite=true only when intended.";
        with (_wm) scr_save_workspace_as_path(_path);
        if (!file_exists(_path)) throw "Project save failed.";
        return {saved:true,path:_path,workspace_key:probe_workspace_key()};
    }
    if (_method == "load_project" || _method == "new_project") {
        if (!global.manual_saved && (!variable_struct_exists(_args,"discard_unsaved") || _args.discard_unsaved!=true)) throw "Current project has unsaved changes; save first or explicitly set discard_unsaved=true.";
        if (_method == "load_project") {
            var _path = probe_project_path(_args.path);
            if (!file_exists(_path)) throw "Project file does not exist.";
            var _buf = buffer_load(_path);
            if (_buf<0) throw "Cannot read project.";
            var _json = buffer_read(_buf,buffer_text); buffer_delete(_buf);
            var _root = json_parse(_json);
            if (!is_struct(_root) || !variable_struct_exists(_root,"nodes") || !is_array(_root.nodes)) throw "Expected a native project object with nodes.";
            var _init_count=0;
            for (var _i=0;_i<array_length(_root.nodes);_i++) {
                var _n=_root.nodes[_i];
                if (!is_struct(_n)) throw "Invalid project node.";
                var _keys=["type","title","x","y","height","connected","pc_address","code"];
                for(var _j=0;_j<array_length(_keys);_j++) if(!variable_struct_exists(_n,_keys[_j])) throw "Incomplete project node.";
                if (!is_array(_n.code) || !is_string(_n.type) || !is_string(_n.title) || !is_real(_n.x) || !is_real(_n.y)) throw "Invalid project node values.";
                if (_n.type=="INIT") _init_count++;
            }
            if (_init_count!=1) throw "Project must contain exactly one INIT.";
        }
        var _backup = probe_recovery_copy();
        if (_method == "new_project") {
            probe_restart_pending=true;
            return {state:"restart_queued",recovery_path:_backup,note:"Editor restarts next frame and reconnects using saved pairing. Inspect before editing."};
        }
        try { with (_wm) scr_load_workspace_from_path(_path, true); }
        catch (_error) {
            // Preserve the on-disk recovery file even if a malformed asset defeats native loading.
            throw "Native load failed. Recovery copy: " + _backup + ". Inspect before continuing.";
        }
        probe_repair_uids();
        return {loaded:true,path:_path,recovery_path:_backup,workspace_key:probe_workspace_key()};
    }
    if (_method == "history") {
        if (_args.direction!="undo" && _args.direction!="redo") throw "Invalid history direction.";
        var _before=probe_workspace_key();
        with (_wm) scr_undo_step(_args.direction=="undo" ? -1 : 1);
        var _after=probe_workspace_key();
        return {changed:_before!=_after,workspace_key:_after};
    }
    if (_method == "create_node") {
        if (!is_string(_args.type) || !array_contains(probe_node_types,_args.type)) throw "Unknown node type.";
        var _xx=variable_struct_exists(_args,"x") ? _args.x : max(200,_wm.cam_x+1000*_wm.cam_zoom);
        var _yy=variable_struct_exists(_args,"y") ? _args.y : _wm.cam_y+400*_wm.cam_zoom;
        var _after=variable_struct_exists(_args,"after_uid") ? probe_find(_args.after_uid) : noone;
        probe_before_edit();
        var _node = scr_node_spawn(_args.type,_xx,_yy);
        try {
            probe_validate_fields(_node,_args);
            if (instance_exists(_after)) probe_check_connection(_node,_after);
            probe_set_fields(_node,_args);
            if (instance_exists(_after)) probe_connect(_node,_after);
        } catch(_error) { instance_destroy(_node); throw _error; }
        probe_after_edit();
        scr_focus_camera_on_node(_node);
        return {created:probe_node_info(_node),workspace_key:probe_workspace_key()};
    }
    var _node=probe_find(_args.uid);
    if (_method=="update_node") {
        if (_node.macro_owner!=noone) throw "Edit the owning macro, not its internal child.";
        probe_validate_fields(_node,_args);
        probe_before_edit(); probe_set_fields(_node,_args); probe_after_edit();
    } else if (_method=="connect_node") {
        var _after=probe_find(_args.after_uid);
        probe_check_connection(_node,_after);
        probe_before_edit(); probe_connect(_node,_after); probe_after_edit();
    } else if (_method=="disconnect_node" || _method=="delete_node") {
        if (_node.node_type=="INIT" || _node.node_type=="ORG" || _node.macro_owner!=noone) throw "Cannot detach/delete an anchor or internal macro child.";
        probe_before_edit();
        if (_method=="delete_node") instance_destroy(_node);
        else { _node.is_connected=false; _node.org_parent=noone; _node.x+=400; }
        probe_refresh(noone); probe_after_edit();
    } else throw "Unknown project command.";
    return {changed:true,workspace_key:probe_workspace_key()};
};

probe_busy = function() {
    if (variable_global_exists("text_prompt") && is_struct(global.text_prompt)) return true;
    if (!instance_exists(obj_workspace_manager)) return true;
    if (instance_exists(obj_question_box) || instance_exists(obj_message_box)) return true;
    if (variable_global_exists("any_picker_open") && global.any_picker_open) return true;
    if (variable_global_exists("asset_reload_in_progress") && global.asset_reload_in_progress) return true;
    if (probe_build.state == "queued" || probe_build.state == "building" || probe_build.state == "launch_pending") return true;
    if (mouse_check_button(mb_any)) return true;
    if (variable_global_exists("is_any_text_active") && global.is_any_text_active) return true;
    if (variable_global_exists("canEditNode") && !global.canEditNode) return true;
    var _wm = instance_find(obj_workspace_manager, 0);
    var _flags = ["welcome_open", "is_entering_text", "code_editor_open",
                  "box_popup_open", "is_panning", "editor_release_pending",
                  "editor_layout_refresh_requested", "flow_overlay_build_pending"];
    for (var _i = 0; _i < array_length(_flags); _i++) {
        if (variable_instance_exists(_wm, _flags[_i])
            && variable_instance_get(_wm, _flags[_i])) return true;
    }
    var _dragging = false;
    with (obj_c64_node) {
        if (is_dragging) { _dragging = true; break; }
    }
    return _dragging;
};

probe_node_info = function(_node) {
    var _result = {
        uid: scr_get_node_uid(_node),
        type: _node.node_type,
        title: string_copy(string(_node.node_title), 1, 100),
        x: _node.x, y: _node.y,
        connected: _node.is_connected,
        owner_uid: instance_exists(_node.org_parent) ? scr_get_node_uid(_node.org_parent) : -1,
        height: _node.height, address: _node.pc_address
    };
    if (_node.node_type == "COMMENT") {
        _result.text = string_copy(string(_node.instructions[0][1]), 1, 256);
    }
    return _result;
};

probe_dispatch = function(_method, _args) {
    if (global.lite != 0) throw "MCP requires the Pro edition.";
    if (_method == "ping") {
        return {pong: true, application: "C64 Dev Machine", prototype: "0.2.0",
                workspace_key: probe_workspace_key(), busy: probe_busy()};
    }
    if (_method == "capabilities") return {version:"0.2.0", node_types:probe_node_types, max_command_bytes:28000, build_async:true, pairing_remembered:true};
    if (_method == "build_status") return probe_build;
    if (probe_busy()) throw "Editor busy: close dialogs/editors and release the mouse, then retry.";
    if (_method == "project_summary") {
        var _offset = variable_struct_exists(_args, "offset") ? _args.offset : 0;
        var _limit = variable_struct_exists(_args, "limit") ? _args.limit : 50;
        if (!is_real(_offset) || _offset < 0 || _offset != floor(_offset)
            || _offset > 1000000 || !is_real(_limit) || _limit != floor(_limit)
            || _limit < 1 || _limit > 100) throw "Invalid page; limit must be 1..100.";
        var _count = instance_number(obj_c64_node);
        var _nodes = [];
        var _bytes = 0;
        for (var _i = _offset; _i < min(_count, _offset + _limit); _i++) {
            var _node = instance_find(obj_c64_node, _i);
            if (instance_exists(_node)) {
                var _info = probe_node_info(_node);
                var _cost = string_byte_length(json_stringify(_info)) + 1;
                // Leave room for JSON-RPC text wrapping in the MCP bridge.
                if (_bytes + _cost > 24000) break;
                _bytes += _cost;
                array_push(_nodes, _info);
            }
        }
        var _name = "Untitled";
        if (variable_global_exists("workspace_path") && global.workspace_path != "") {
            _name = string_copy(filename_name(global.workspace_path), 1, 100);
        }
        return {project: _name, workspace_key: probe_workspace_key(), node_count: _count,
                offset: _offset, limit: _limit, next_offset: _offset + array_length(_nodes),
                has_more: _offset + array_length(_nodes) < _count,
                nodes: _nodes};
    }
    if (!variable_struct_exists(_args, "expected_workspace")
        || !is_string(_args.expected_workspace)
        || _args.expected_workspace != probe_workspace_key()) {
        throw "Workspace changed. Read project_summary again before acting.";
    }
    if (_method == "focus_node") {
        if (!variable_struct_exists(_args, "uid") || !is_real(_args.uid)
            || _args.uid < 0 || _args.uid != floor(_args.uid)) throw "Invalid node UID.";
        var _found = noone;
        var _uid = _args.uid;
        with (obj_c64_node) {
            if (stable_uid == _uid) { _found = id; break; }
        }
        if (!instance_exists(_found)) throw "Node not found. Read project_summary again.";
        scr_focus_camera_on_node(_found);
        return {focused_uid: _uid};
    }
    if (_method != "add_comment") return probe_project_command(_method, _args);
    if (!variable_struct_exists(_args, "text") || !is_string(_args.text)) throw "Text is required.";
    var _text = _args.text;
    if (string_length(_text) < 1 || string_length(_text) > 256) throw "Text must be 1..256 characters.";
    // Deliberately narrow first test: one line of printable ASCII, no markup.
    for (var _i = 1; _i <= string_length(_text); _i++) {
        var _ch = ord(string_char_at(_text, _i));
        if (_ch < 32 || _ch > 126) throw "Prototype comments accept printable ASCII only.";
    }
    // Bound the demo's disk-backed snapshot cost; use a small scratch workspace.
    if (instance_number(obj_c64_node) > 200) throw "Use a scratch project with at most 200 nodes for this test.";
    var _wm = instance_find(obj_workspace_manager, 0);
    var _xx = _wm.cam_x + 1000 * _wm.cam_zoom;
    var _yy = _wm.cam_y + 400 * _wm.cam_zoom;
    if (variable_struct_exists(_args, "x")) _xx = _args.x;
    if (variable_struct_exists(_args, "y")) _yy = _args.y;
    if (!is_real(_xx) || !is_real(_yy) || is_nan(_xx) || is_nan(_yy)
        || abs(_xx) > 1000000 || abs(_yy) > 1000000) throw "Invalid comment coordinates.";
    if (!variable_global_exists("undo_states") || global.undo_states < 2) {
        throw "Enable at least two undo states before running the comment test.";
    }
    var _new = noone;
    // Capture a pre-edit state even if a previous keyboard edit was unsnapped.
    scr_undo_snapshot();
    try {
        _new = scr_spawn_comment_node(_xx, _yy);
        _new.instructions = [["Comment", _text]];
        scr_comment_sync_layout(_new);
        _new.height_dirty = true;
        scr_undo_snapshot();
    } catch (_error) {
        if (instance_exists(_new)) instance_destroy(_new);
        throw _error;
    }
    global.undo_dirty = false;
    global.manual_saved = false;
    global.autosave_dirty = true;
    if (global.autosave_mode != 3) {
        _wm.alarm[4] = max(_wm.alarm[4], game_get_speed(gamespeed_fps) * 5);
    }
    scr_focus_camera_on_node(_new);
    probe_status = "CONNECTED - comment added; Ctrl+Z to undo";
    return {created: probe_node_info(_new), workspace_key: probe_workspace_key(),
            undo: "Use the normal Ctrl+Z in Dev Machine.", saved: false};
};

/// @param {Bool} _fresh Replace the remembered key from the clipboard.
probe_start = function(_fresh) {
    if (global.lite != 0) { probe_stop("OFF - Pro edition required"); return; }
    // Explicit shortcut opt-in is the ONLY clipboard access in this object.
    var _key = probe_saved_key;
    if (probe_pair_key != "") {
        // Collected from the MCP-CON helper; no clipboard access at all.
        _key = probe_pair_key;
        probe_pair_key = "";
    }
    else if (_fresh || _key == "") {
        _key = string_trim(clipboard_get_text());
    }
    var _parts = string_split(_key, ":");
    if (array_length(_parts) != 3 || _parts[0] != "cdm1") {
        probe_stop("OFF - copy the pairing key first (see tools/cdm-mcp/README.md)");
        return;
    }
    var _port_text = _parts[1];
    var _token = string_lower(_parts[2]);
    if (string_length(_port_text) < 1 || string_length(_port_text) > 5
        || string_digits(_port_text) != _port_text || string_length(_token) != 64) {
        probe_stop("OFF - invalid pairing key"); return;
    }
    for (var _i = 1; _i <= 64; _i++) {
        if (string_pos(string_char_at(_token, _i), "0123456789abcdef") == 0) {
            probe_stop("OFF - invalid pairing key"); return;
        }
    }
    var _port = real(_port_text);
    if (_port < 1024 || _port > 65535) { probe_stop("OFF - invalid port"); return; }
    probe_saved_key = _key;
    probe_auto_pair = true;
    probe_token = _token;
    probe_rx = buffer_create(probe_max_line + 1, buffer_fixed, 1);
    probe_rx_len = 0;
    probe_queue = [];
    probe_last_id = 0;
    probe_last_wire = "";
    probe_last_reply = "";
    probe_last_rx = current_time;
    probe_state = "connecting";
    probe_status = "CONNECTING - Ctrl+Shift+F12 to disconnect";
    probe_socket = network_create_socket(network_socket_tcp);
    if (probe_socket < 0
        || network_connect_raw_async(probe_socket, "127.0.0.1", _port) < 0) {
        probe_stop("OFF - connection failed; start the local bridge first");
    }
};

/// Locate the platform setup helper that the MCP-CON button runs. Returns ""
/// when the optional tools/cdm-mcp folder was not shipped alongside the editor.
setup_script_path = function() {
    var _candidates = [
        working_directory + "tools\\cdm-mcp\\setup-mcp.bat",
        working_directory + "tools/cdm-mcp/setup-mcp.bat",
        program_directory + "tools\\cdm-mcp\\setup-mcp.bat",
        program_directory + "tools/cdm-mcp/setup-mcp.bat"
    ];
    if (os_type != os_windows) {
        _candidates = [
            working_directory + "tools/cdm-mcp/setup-mcp.command",
            program_directory + "tools/cdm-mcp/setup-mcp.command"
        ];
    }
    for (var _i = 0; _i < array_length(_candidates); _i++) {
        if (file_exists(_candidates[_i])) return _candidates[_i];
    }
    return "";
};

/// Start the one-click setup. ShellExecute returns immediately, so this never
/// stalls a frame even when Node.js has to be downloaded and installed.
setup_run = function() {
    if (setup_state == "running") return;
    var _script = setup_script_path();
    if (_script == "") {
        setup_state  = "failed";
        setup_status = "MISSING";
        setup_detail = "setup helper not found in tools/cdm-mcp";
        probe_notice_until = current_time + 10000;
        return;
    }
    if (file_exists(setup_status_path)) file_delete(setup_status_path);
    if (file_exists(setup_pair_path)) file_delete(setup_pair_path);
    setup_state    = "running";
    setup_status   = "CHECKING";
    setup_detail   = "Starting setup";
    setup_poll_at  = current_time + 400;
    setup_deadline = current_time + 600000;
    // The helper writes its status files into the folder passed as argument 1,
    // so both sides agree on one location whatever the edition is called.
    execute_shell_simple(_script, "\"" + game_save_id + "\"", "open", 0,
                         filename_dir(_script));
};

/// Take the pairing key the helper left, then delete it straight away.
setup_adopt_key = function() {
    if (!file_exists(setup_pair_path)) {
        setup_state  = "failed";
        setup_status = "TOKEN_FAILED";
        setup_detail = "setup finished but wrote no pairing key";
        return;
    }
    var _key = "";
    var _file = file_text_open_read(setup_pair_path);
    if (_file >= 0) {
        _key = string_trim(file_text_read_string(_file));
        file_text_close(_file);
    }
    file_delete(setup_pair_path);
    if (_key == "") {
        setup_state  = "failed";
        setup_status = "TOKEN_FAILED";
        setup_detail = "pairing key file was empty";
        return;
    }
    probe_pair_key  = _key;
    probe_auto_pair = true;
    probe_start(false);
};

/// Read the two-line status file the helper rewrites as it progresses.
setup_poll = function() {
    if (!file_exists(setup_status_path)) return;
    var _file = file_text_open_read(setup_status_path);
    if (_file < 0) return;
    var _token  = "";
    var _detail = "";
    if (!file_text_eof(_file)) {
        _token = string_trim(file_text_read_string(_file));
        file_text_readln(_file);
    }
    if (!file_text_eof(_file)) {
        _detail = string_trim(file_text_read_string(_file));
    }
    file_text_close(_file);
    if (_token == "") return;
    setup_status = _token;
    setup_detail = string_copy(_detail, 1, 90);
    if (_token == "DONE") {
        setup_state = "done";
        setup_adopt_key();
        return;
    }
    if (_token == "CHECKING" || _token == "REGISTERING"
        || _token == "NODE_MISSING" || _token == "NODE_INSTALLING") {
        setup_state = "running";
        return;
    }
    // Anything else is terminal: NO_HOST, NO_WINGET, NODE_TOO_OLD, and so on.
    setup_state = "failed";
    probe_notice_until = current_time + 12000;
};

// Pair once, then reconnect without reading or altering the clipboard. Shift+Alt+Ctrl+F12 replaces the stored key.
ini_open("cdm-mcp-pairing.ini");
probe_saved_key = ini_read_string("pairing", "key", "");
probe_auto_pair = ini_read_real("pairing", "enabled", 0) == 1;
ini_close();
probe_retry_at = current_time + 1500;
