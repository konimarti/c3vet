module c3vet::fixtures::private_scope;

fn void dead_private() @private {} // want "@private declaration 'dead_private'"
fn void sibling_private() @private {}
fn void referenced_private() @private { referenced_private(); }
fn void dead_local() @local {} // want "@local declaration 'dead_local'"
fn void used_local() @local {}

fn void local_user() { used_local(); }
