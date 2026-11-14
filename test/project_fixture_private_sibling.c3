module c3vet::fixtures::private_scope;

fn void sibling_private() {}
fn void sibling_use() { sibling_private(); }
