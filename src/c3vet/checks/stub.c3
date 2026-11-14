<*
 PHASE 0 SCAFFOLD. Delete this file when lane 2C lands `empty-body`.

 Exists only so the Phase 0 gate can be demonstrated: one real finding
 travelling the whole path from source bytes through the lexer, the parser,
 `walk`, `Ctx.report`, suppression and the CLI's exit code. It is registered
 default_on so `c3vet` on a file with an empty block prints something.
*>
module c3vet;

import c3::parser;

const Check STUB_EMPTY_BLOCK = {
	.name          = "stub-empty-block",
	.doc           = "Phase 0 scaffold: an empty { } block. Replaced by empty-body in lane 2C.",
	.tier          = Tier.SYNTAX,
	.default_on    = true,
	.skip_on_error = true,
	.run           = &run_stub_empty_block,
};

fn void run_stub_empty_block(Ctx* ctx, Unit* u)
{
	Walker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_stub, &w);
}

<* Carries the engine's two pointers through `walk`'s `any` context. *>
struct Walker
{
	Ctx*  ctx;
	Unit* unit;
}

fn bool visit_stub(Ast* ast, NodeId id, any ctx) @local
{
	Walker* w = (Walker*)ctx;
	Node* n = ast.node(id);
	// The unit's own top-level node is a BLOCK too; only report nested ones.
	if (n.kind == NodeKind.BLOCK && id != w.unit.root() && !ast.children(id).len)
	{
		w.ctx.report(w.unit, id, "stub-empty-block", "empty block");
	}
	return true;
}
