<*
 The check interface and the tier scheduler.
*>
module c3vet;

import c3::lexer;
import c3::parser;
import std::collections::list;
import std::core::mem::alloc;
import std::io;

<*
 How much analysis a check needs. The engine builds only the layers that
 enabled checks actually require, so a run with only SYNTAX checks never pays
 for scopes or the project table.
*>
enum Tier : char
{
	<* The AST of one file. *>
	SYNTAX,
	<* Per-function scopes with declared types, plus reachability. *>
	LOCAL,
	<* The project-wide declaration table. *>
	PROJECT,
}

<* One source file and whatever analysis layers were built for it. *>
struct Unit
{
	String         path;
	String         src;
	ParseResult    parsed;
	SuppressionSet suppress;
	<* Non-null only when some enabled check needs LOCAL or above. *>
	Scopes*        scopes;
	Flow*          flow;
}

fn TokenList* Unit.toks(&self) @inline => &self.parsed.toks;
fn Ast* Unit.ast(&self) @inline => &self.parsed.ast;
fn NodeId Unit.root(&self) @inline => self.parsed.ast.root;

<* True when the file holds ERROR_* nodes or failed to lex. *>
fn bool Unit.has_errors(&self) @inline => self.parsed.has_errors();

<* What a check is handed besides the unit. *>
struct Ctx
{
	<* Non-null only when some enabled check is PROJECT tier. *>
	DeclTable*      table;
	Config*         config;
	DiagnosticList* out;
	<* Findings dropped by suppression comments, for the run summary. *>
	sz              suppressed;
	<*
	 Paths a diagnostic may be reported for. Empty means "anything".
	 Declarations may be indexed from more files than are reported.
	*>
	List{String}    reported;
}

alias CheckFn = fn void(Ctx* ctx, Unit* unit);
<* A check's own `parser::walk` visitor -- identical shape to `parser::VisitFn`. *>
alias CheckVisitFn = fn bool(Ast* ast, NodeId id, any ctx);
<* Builds a check's per-unit walker state once, before the shared walk runs. *>
alias CheckMakeStateFn = fn any(Ctx* ctx, Unit* unit, Allocator a);

struct Check
{
	<* Stable, kebab-case, user-visible: "self-assign". *>
	String  name;
	<* One line, shown by --list-checks. *>
	String  doc;
	Tier    tier;
	<* Whether the check runs unless disabled; opt-in checks leave this false. *>
	bool    default_on;
	<* Skip files containing ERROR_* nodes. Almost always true. *>
	bool    skip_on_error;
	<*
	 Set for a check that does not fit a single top-down AST visit (`parse`
	 reads `u.parsed.errors` directly; `defer-in-loop` needs a depth counter
	 `parser::walk` has no hook for; `unused-private-decl` only walks the
	 file's top-level declarations, not the whole tree). Mutually exclusive
	 with `visit`/`make_state` -- the engine uses whichever pair is set.
	*>
	CheckFn run;
	<*
	 A check's own `parser::walk` visitor, run as part of the ONE shared
	 walk `run_checks` does across every such check, instead of each check
	 walking the whole tree on its own. Paired with `make_state`.
	*>
	CheckVisitFn visit;
	<* Builds this check's walker struct for one unit, handed back to `visit`. *>
	CheckMakeStateFn make_state;
}

<*
 Report a finding at `node`.

 Every check goes through here, so no check formats its own location, and
 suppression and reported-scope filtering happen in exactly one place.
*>
fn void Ctx.report(&self, Unit* u, NodeId node, String check, String fmt,
	args...) @format(4)
{
	Node* n = u.ast().node(node);
	self.emit(u, n.first_tok, n.last_tok, check,
		string::format(self.out.allocator, fmt, ...args));
}

<*
 Report a finding at a token span rather than a node.

 Needed by the `parse` check, whose findings predate any node. Everything
 still goes through `emit`, so scope filtering and suppression are applied in
 exactly one place.
*>
fn void Ctx.report_at_token(&self, Unit* u, uint first_tok, uint last_tok,
                            String check, String fmt, args...) @format(5)
{
	self.emit(u, first_tok, last_tok, check,
		string::format(self.out.allocator, fmt, ...args));
}

<*
 The single gate every finding passes through.

 Scope filtering and suppression live here and nowhere else, so a check
 cannot leak a dependency-scope diagnostic by forgetting to guard.
*>
fn void Ctx.emit(&self, Unit* u, uint first_tok, uint last_tok, String check,
	String msg)
{
	// `msg` arrives already allocated (Ctx.report/report_at_token format it
	// before calling emit): every path below either keeps it in self.out or
	// frees it here, so a dropped finding never leaks its message.
	if (!self.in_reported_scope(u.path))
	{
		msg.free(self.out.allocator);
		return;
	}

	lexer::Token t = u.toks().tok(first_tok);
	lexer::Token last = u.toks().tok(last_tok);
	if (u.suppress.suppresses(check, t.ln, last.ln))
	{
		self.suppressed++;
		msg.free(self.out.allocator);
		return;
	}
	self.out.push({
		.file      = u.path,
		.ln        = t.ln,
		.col       = t.col,
		.first_tok = first_tok,
		.last_tok  = last_tok,
		.check     = check,
		.msg       = msg,
	});
}

<*
 Whether findings may be emitted for `path`.

 The declaration table indexes dependencies and the standard library so that
 attribute lookups work, but a diagnostic must never be reported for them.
 Keeping the filter here means a check cannot leak a stdlib finding by
 forgetting to guard. This is the direct answer to c3c's stdlib flooding.
*>
fn bool Ctx.in_reported_scope(&self, String path)
{
	if (!self.reported.len()) return true;
	foreach (p : self.reported) if (p == path) return true;
	return false;
}

<* The loosest tier any enabled check needs, so the engine builds no more. *>
fn Tier max_tier(Check[] enabled)
{
	Tier t = Tier.SYNTAX;
	foreach (c : enabled) if (c.tier > t) t = c.tier;
	return t;
}

<* One walk-based check's visitor, paired with the state `make_state` built for it. *>
struct ActiveVisit
{
	CheckVisitFn visit;
	any          state;
}

<* Carries every active walk-based check's visitor through the one shared `parser::walk`. *>
struct SharedWalkState
{
	List{ActiveVisit} active;
}

<*
 Calls every active check's visitor at this node. Descends unless every
 single one of them wants to stop -- a check that returns false here only
 means "nothing further down this subtree matters to ME", which must never
 suppress a sibling check that still needs to see those nodes.
*>
fn bool run_shared_visit(Ast* ast, NodeId id, any context) @local
{
	SharedWalkState* s = (SharedWalkState*)context;
	bool keep_going = false;
	foreach (&a : s.active)
	{
		if (a.visit(ast, id, a.state)) keep_going = true;
	}
	return keep_going;
}

<*
 Run `enabled` over one unit.

 Parse failures are reported first, then checks run on whatever did parse.
 Builds `u.scopes`/`u.flow` once, lazily, the first time some enabled check
 needs `Tier.LOCAL` or above -- a run with only SYNTAX checks never pays for
 either, and a unit already carrying them (e.g. a second `run_checks` call
 against the same `Unit`) is not rebuilt.

 Every check that visits the AST (`visit`/`make_state` set) shares ONE walk
 over the tree instead of each walking it separately -- with N checks
 enabled, the file was otherwise parsed once but walked N times. A check
 that cannot fit that shape (`run` set instead) still gets its own call, as
 before.
*>
fn void run_checks(Ctx* ctx, Unit* u, Check[] enabled)
{
	if (max_tier(enabled) >= Tier.LOCAL && !u.scopes)
	{
		// tmem, not ctx.out.allocator: both are rebuilt fresh per Unit inside
		// vet_file's own @pool(), so nothing about them needs to outlive it.
		u.scopes = alloc::new(tmem, Scopes,
			build_scopes(u.ast(), u.toks(), tmem));
		u.flow = alloc::new(tmem, Flow, build_flow(u.ast(), u.toks(), tmem));
	}

	Allocator a = tmem;
	SharedWalkState walk_state;
	walk_state.active.tinit();

	foreach (c : enabled)
	{
		if (c.skip_on_error && u.has_errors()) continue;
		if (c.visit && c.make_state)
		{
			walk_state.active.push({
				.visit = c.visit,
				.state = c.make_state(ctx, u, a)
			});
		}
		else
		{
			c.run(ctx, u);
		}
	}

	if (walk_state.active.len())
	{
		parser::walk(u.ast(), u.root(), &run_shared_visit, &walk_state);
	}
}
