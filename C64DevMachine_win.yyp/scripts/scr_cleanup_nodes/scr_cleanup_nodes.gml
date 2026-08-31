// Remove unlinked asset nodes
function scr_cleanup_nodes()
{
    // ----------------------------------------------------------------
    // PASS A: Collect unused NAMED_LOC (UV vars) — warn before destroy
    // A NAMED_LOC is "used" if its name appears in any instruction
    // operand across all nodes.
    // ----------------------------------------------------------------
    var _unused_vars     = [];
    var _unused_var_ids  = [];

    with (obj_c64_node)
    {
        if (node_type != "NAMED_LOC") continue;
        if (org_parent == noone) continue; // orphan — caught later by normal cleanup

        var _var_name  = string_upper(string(instructions[0][1]));
        var _is_used   = false;

        with (obj_c64_node)
        {
            if (node_type == "NAMED_LOC") continue;
            for (var _ii = 0; _ii < array_length(instructions); _ii++)
            {
                for (var _jj = 0; _jj < array_length(instructions[_ii]); _jj++)
                {
                    if (string_upper(string(instructions[_ii][_jj])) == _var_name)
                    {
                        _is_used = true;
                        break;
                    }
                }
                if (_is_used) break;
            }
            if (_is_used) break;
        }

        if (!_is_used)
        {
            array_push(_unused_vars,    _var_name);
            array_push(_unused_var_ids, id);
        }
    }

    if (array_length(_unused_vars) > 0)
    {
        var _warn_msg = "Unused UV variables found:\n";
        for (var _wi = 0; _wi < array_length(_unused_vars); _wi++)
        {
            _warn_msg += "  - " + _unused_vars[_wi] + "\n";
        }
        _warn_msg += "\nDestroy these unused variables?";

        if (show_question(_warn_msg))
        {
            for (var _di = 0; _di < array_length(_unused_var_ids); _di++)
            {
                if (instance_exists(_unused_var_ids[_di]))
                {
                    instance_destroy(_unused_var_ids[_di]);
                }
            }
        }
    }

    // ----------------------------------------------------------------
    // PASS B: Destroy empty VARIABLES ORGs (no NAMED_LOC or NEW_STR children)
    // ----------------------------------------------------------------
    with (obj_c64_node)
    {
        if (node_type != "ORG") continue;
        if (node_title != "VARIABLES") continue;

        var _has_var_children = false;
        var _self_ref = id;
        with (obj_c64_node)
        {
            if (org_parent == _self_ref
                && (node_type == "NAMED_LOC" || node_type == "NEW_STR"))
            {
                _has_var_children = true;
                break;
            }
        }
        if (!_has_var_children)
        {
            instance_destroy();
        }
    }

    // ----------------------------------------------------------------
    // PASS C: Main node cleanup
    // ----------------------------------------------------------------
    with (obj_c64_node)
    {
        // ORG with no children of any kind
        if (node_type == "ORG" && node_title != "VARIABLES")
        {
            var _has_children = false;
            var _self_ref = id;
            with (obj_c64_node)
            {
                if (org_parent == _self_ref)
                {
                    _has_children = true;
                    break;
                }
            }
            if (!_has_children)
            {
                instance_destroy();
            }
        }

        // Opcode nodes not connected to the spine
        if (node_type == "NORMAL" && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "INIT" && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "BRANCH" && !is_connected)
        {
            instance_destroy();
        }

        // Labels not connected
        if (node_type == "LABEL" && !is_connected)
        {
            instance_destroy();
        }

        // Comments with no text
        if (node_type == "COMMENT")
        {
            var _txt = "";
            if (array_length(instructions) > 0)
            {
                _txt = string(instructions[0][1]);
            }
            if (_txt == "" || _txt == "Comment")
            {
                instance_destroy();
            }
        }

        // VAR nodes not connected
        if (node_type == "VAR" && !is_connected)
        {
            instance_destroy();
        }

        // RAW_DATA floating and unparented
        if (node_type == "RAW_DATA" && !is_connected && org_parent == noone)
        {
            instance_destroy();
        }

        // DATA_SID not linked to any MACRO_SID
        if (node_type == "DATA_SID")
        {
            var _linked  = false;
            var _self_ref = id;
            with (obj_c64_node)
            {
                if (node_type == "MACRO_SID" && sid_link == _self_ref)
                {
                    _linked = true;
                    break;
                }
            }
            if (!_linked)
            {
                instance_destroy();
            }
        }

        // SPR64 not linked to any MACRO_SPR
        if (node_type == "SPR64")
        {
            var _linked  = false;
            var _self_ref = id;
            with (obj_c64_node)
            {
                if (node_type == "MACRO_SPR" && spr_link == _self_ref)
                {
                    _linked = true;
                    break;
                }
            }
            if (!_linked)
            {
                instance_destroy();
            }
        }

        // DATA_TEXT not linked to any MACRO_PRINT
        if (node_type == "DATA_TEXT")
        {
            var _linked  = false;
            var _self_ref = id;
            with (obj_c64_node)
            {
                if (node_type == "MACRO_PRINT" && print_link == _self_ref)
                {
                    _linked = true;
                    break;
                }
            }
            if (!_linked)
            {
                instance_destroy();
            }
        }

        // Disconnected macro nodes
        if (node_type == "MACRO_JOY" && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "MACRO_MOUSE" && !is_connected)
        {
            instance_destroy();
        }
        if ((node_type == "MACRO_LETTERS" || node_type == "MACRO_FNNUMBERS"
          || node_type == "MACRO_MISCKEYS") && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "MACRO_PRINT" && !is_connected && !instance_exists(print_link))
        {
            instance_destroy();
        }
        if (node_type == "MACRO_VWAIT" && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "MACRO_WAIT" && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "MACRO_NOP_REPEAT" && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "MACRO_DISPLAY" && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "MACRO_TRACK" && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "MACRO_SID" && !is_connected)
        {
            instance_destroy();
        }
        if (node_type == "MACRO_SPR" && !is_connected)
        {
            instance_destroy();
        }

        // NAMED_LOC orphaned (no ORG parent)
        if (node_type == "NAMED_LOC" && org_parent == noone)
        {
            instance_destroy();
        }

        // Catch-all: any remaining floating unparented unconnected node
        // Excludes ORG (handled above), COMMENT (handled above),
        // LABEL (handled above), NAMED_LOC (handled above)
        if (!is_connected
            && org_parent == noone
            && node_type != "ORG"
            && node_type != "NAMED_LOC"
            && node_type != "COMMENT"
            && node_type != "LABEL")
        {
            instance_destroy();
        }
    }
}