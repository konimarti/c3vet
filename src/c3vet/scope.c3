<*
 Per-function scopes and statement reachability.

 PHASE 3 (lane 3A). Declared here in Phase 0 so `Unit` can be frozen.

 `Scopes` will map each function's parameters and locals to their DECLARED
 types -- no inference, no reimplementation of c3c's type system. `Flow` will
 answer reachability. Family A (temp-memory escapes) additionally needs the
 talloc/tmem origin tracking that lane 3A provides here.
*>
module c3vet;

struct Scopes
{
	<* Placeholder: Phase 3 fills this in. *>
	bool built;
}

struct Flow
{
	<* Placeholder: Phase 3 fills this in. *>
	bool built;
}
