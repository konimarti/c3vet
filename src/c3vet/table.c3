<*
 Project-wide declaration table.

 PHASE 4 (lane 4A). Declared here in Phase 0 so that `Ctx` can be frozen with
 its final shape and PROJECT-tier checks compile against it from the start.

 When implemented it indexes the WIDER scope -- project sources plus
 lib/*.c3l dependencies plus the standard library, declarations only, function
 bodies skipped -- and answers questions about declarations: "does io::printfn
 carry @format?", "what does std::math export?". Diagnostics stay restricted
 to the narrower reported scope, which `Ctx.report` enforces.
 See docs/DESIGN.md section 5.
*>
module c3vet;

struct DeclTable
{
	<* Placeholder: Phase 4 fills this in. *>
	bool built;
}
