module c3vet::fixtures::attrs;

attrmacro @Hot = @inline;

// Without a second export the import is never judged at all.
fn void other()
{}
