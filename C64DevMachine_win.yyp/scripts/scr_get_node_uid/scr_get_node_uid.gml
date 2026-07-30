/// @desc Returns the workspace-scoped stable UID for a node.
/// All nodes are assigned a stable_uid in their Create event.
/// Safety net: backfills the UID for legacy instances missing it.
function scr_get_node_uid(_node) {
    if (!instance_exists(_node)) return -1;
    if (_node.stable_uid != -1) return _node.stable_uid;
    // Backfill for legacy / corrupted saves
    if (!variable_global_exists("next_stable_uid")) global.next_stable_uid = 100000;
    _node.stable_uid = global.next_stable_uid;
    global.next_stable_uid += 1;
    return _node.stable_uid;
}