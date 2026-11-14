<*
 Suppression comments.

 c3c has no suppression mechanism at all, so this is a core part of what
 c3vet adds. Forms recognised:

   a = a;                        // c3vet:ignore
   a = a;                        // c3vet:ignore[self-assign]
   // c3vet:ignore[self-assign]     applies to the next code line too
   // c3vet:ignore-file[float-equal]

 A bare `ignore` suppresses every check. Read from the trivia tokens the
 parser held back, so it costs nothing extra.
*>
module c3vet;

import c3::parser;
import c3::lexer;
import std::collections::list;

const String MARK      = "c3vet:ignore";
const String MARK_FILE = "c3vet:ignore-file";

<* One parsed suppression comment. *>
struct Suppression
{
	<* Line the comment sits on; 0 for a file-level suppression. *>
	sz     ln;
	<* Empty means "every check". *>
	String checks;
	bool   whole_file;
}

struct SuppressionSet
{
	List{Suppression} items;
}

fn void SuppressionSet.init(&self, Allocator a) => self.items.init(a);
fn void SuppressionSet.free(&self) => self.items.free();

<* Collect every suppression comment in a lexed file. *>
fn void SuppressionSet.collect(&self, TokenList* toks)
{
	foreach (t : toks.all)
	{
		if (t.type != LINE_COMMENT && t.type != BLOCK_COMMENT) continue;
		sz at = t.text.index_of(MARK) ?? -1;
		if (at < 0) continue;
		bool whole = @ok(t.text.index_of(MARK_FILE));
		String rest = t.text[(usz)at + (whole ? MARK_FILE.len : MARK.len)..];
		self.items.push({
			.ln         = whole ? 0 : t.ln,
			.checks     = bracket_list(rest),
			.whole_file = whole,
		});
	}
}

<*
 The comma-separated names inside a trailing `[...]`, or the empty string when
 there is no bracket, which means "every check".
*>
fn String bracket_list(String rest) @local
{
	sz open = rest.index_of_char('[') ?? -1;
	if (open < 0) return "";
	sz close = rest.index_of_char(']') ?? -1;
	if (close <= open) return "";
	return rest[(usz)open + 1 .. (usz)close - 1];
}

<* True when `check` is named in a suppression's list, or the list is empty. *>
fn bool Suppression.covers(&self, String check)
{
	if (!self.checks.len) return true;
	// Match whole names only, so "self-assign" is not matched by "assign".
	usz from = 0;
	String s = self.checks;
	while (from <= s.len)
	{
		usz end = from;
		while (end < s.len && s[end] != ',') end++;
		String name = s[from..end > from ? end - 1 : from];
		if (name.trim() == check) return true;
		if (end >= s.len) break;
		from = end + 1;
	}
	return false;
}

<*
 True when a finding for `check` spanning lines `first_ln` to `last_ln` is
 suppressed.

 A comment counts when it sits anywhere inside the reported construct, or on
 the line just before it. The span matters rather than only the first line: a
 finding is anchored where the construct opens, but a reader writing a
 trailing comment puts it where the construct ends --

     {
     }  // c3vet:ignore

 -- and that has to work, or the feature is a trap.
*>
fn bool SuppressionSet.suppresses(&self, String check, sz first_ln, sz last_ln)
{
	foreach (s : self.items)
	{
		if (!s.covers(check)) continue;
		if (s.whole_file) return true;
		if (s.ln >= first_ln - 1 && s.ln <= last_ln) return true;
	}
	return false;
}

<* How many suppressions the file declared, for the run summary. *>
fn sz SuppressionSet.len(&self) @inline => self.items.len();
