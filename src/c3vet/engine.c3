<*
 The check interface and the tier scheduler.

 FROZEN INTERFACE. See docs/DESIGN.md section 5 and docs/WORKPLAN.md rule 1.
 Checks consume this and never edit it.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;
import std::io;
import std::core::mem::alloc;

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
	 Indexed scope is wider than reported scope; see docs/DESIGN.md 5.
	*>
	List{String}    reported;
}

alias CheckFn = fn void(Ctx* ctx, Unit* unit);

struct Check
{
	<* Stable, kebab-case, user-visible: "self-assign". *>
	String  name;
	<* One line, shown by --list-checks. *>
	String  doc;
	Tier    tier;
	<* Set only after a clean run over the conformance corpus. *>
	bool    default_on;
	<* Skip files containing ERROR_* nodes. Almost always true. *>
	bool    skip_on_error;
	CheckFn run;
}

<*
 Report a finding at `node`.

 Every check goes through here, so no check formats its own location, and
 suppression and reported-scope filtering happen in exactly one place.
*>
fn void Ctx.report(&self, Unit* u, NodeId node, String check, String fmt, args...)
{
	Node* n = u.ast().node(node);
	self.emit(u, n.first_tok, n.last_tok, check, string::format(self.out.allocator, fmt, ...args));
}

<*
 Report a finding at a token span rather than a node.

 Needed by the `parse` check, whose findings predate any node. Everything
 still goes through `emit`, so scope filtering and suppression are applied in
 exactly one place.
*>
fn void Ctx.report_at_token(&self, Unit* u, uint first_tok, uint last_tok,
                            String check, String fmt, args...)
{
	self.emit(u, first_tok, last_tok, check, string::format(self.out.allocator, fmt, ...args));
}

<*
 The single gate every finding passes through.

 Scope filtering and suppression live here and nowhere else, so a check
 cannot leak a dependency-scope diagnostic by forgetting to guard.
*>
fn void Ctx.emit(&self, Unit* u, uint first_tok, uint last_tok, String check, String msg)
{
	if (!self.in_reported_scope(u.path)) return;

	lexer::Token t = u.toks().tok(first_tok);
	lexer::Token last = u.toks().tok(last_tok);
	if (u.suppress.suppresses(check, t.ln, last.ln))
	{
		self.suppressed++;
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

<*
 Run `enabled` over one unit.

 Parse failures are reported first, then checks run on whatever did parse.
 Builds `u.scopes`/`u.flow` once, lazily, the first time some enabled check
 needs `Tier.LOCAL` or above -- a run with only SYNTAX checks never pays for
 either, and a unit already carrying them (e.g. a second `run_checks` call
 against the same `Unit`) is not rebuilt.
*>
fn void run_checks(Ctx* ctx, Unit* u, Check[] enabled)
{
	if (max_tier(enabled) >= Tier.LOCAL && !u.scopes)
	{
		Allocator a = ctx.out.allocator;
		u.scopes = alloc::new(a, Scopes, build_scopes(u.ast(), u.toks(), a));
		u.flow = alloc::new(a, Flow, build_flow(u.ast(), u.toks(), a));
	}
	foreach (c : enabled)
	{
		if (c.skip_on_error && u.has_errors()) continue;
		c.run(ctx, u);
	}
}
