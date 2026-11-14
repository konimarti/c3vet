<* Detect positive integer literals outside an explicit integer cast's range. *>
module c3vet;

import c3::parser;
import c3::lexer;

const Check CONST_NARROWING_OVERFLOW = {
	.name          = "const-narrowing-overflow",
	.doc           = "an integer literal is outside the range of its explicit cast type",
	.tier          = Tier.SYNTAX,
	.default_on    = false,
	.skip_on_error = true,
	.run           = &run_const_narrowing_overflow,
};

struct NarrowingWalker
{
	Ctx*  ctx;
	Unit* unit;
}

fn void run_const_narrowing_overflow(Ctx* ctx, Unit* u)
{
	NarrowingWalker w = { .ctx = ctx, .unit = u };
	parser::walk(u.ast(), u.root(), &visit_narrowing, &w);
}

fn bool visit_narrowing(Ast* ast, NodeId id, any context) @local
{
	NarrowingWalker* w = (NarrowingWalker*)context;
	Node* cast = ast.node(id);
	if (cast.kind != NodeKind.CAST || ast.kind(cast.rhs) != NodeKind.INT_LIT) return true;
	String type_name;
	bool is_signed;
	uint bits = integer_type_width(ast, w.unit.toks(), cast.lhs, &type_name, &is_signed);
	if (!bits) return true;
	ulong value;
	bool overflow;
	if (!parse_integer_literal(w.unit.toks().text_at(ast.node(cast.rhs).tok), &value, &overflow)) return true;
	ulong max_value;
	if (is_signed)
	{
		max_value = bits == 64 ? ulong::max >> 1 : (((ulong)1 << (bits - 1)) - 1);
	}
	else
	{
		max_value = bits == 64 ? ulong::max : (((ulong)1 << bits) - 1);
	}
	if (overflow || value > max_value)
	{
		w.ctx.report(w.unit, id, CONST_NARROWING_OVERFLOW.name,
			"integer literal %s is out of range for cast target '%s'",
			w.unit.toks().text_at(ast.node(cast.rhs).tok), type_name);
	}
	return true;
}

fn uint integer_type_width(Ast* ast, TokenList* toks, NodeId type, String* name, bool* is_signed) @local
{
	if (type == parser::NONE || ast.kind(type) != NodeKind.TYPE_BASE) return 0;
	*name = toks.text_at(ast.node(type).tok);
	switch (*name)
	{
		case "char": *is_signed = false; return 8;
		case "ichar": *is_signed = true; return 8;
		case "short": *is_signed = true; return 16;
		case "ushort": *is_signed = false; return 16;
		case "int": *is_signed = true; return 32;
		case "uint": *is_signed = false; return 32;
		case "long": *is_signed = true; return 64;
		case "ulong": *is_signed = false; return 64;
		default: return 0;
	}
}

fn bool parse_integer_literal(String text, ulong* value, bool* overflow) @local
{
	uint base = 10;
	sz at = 0;
	if (text.len >= 2 && text[0] == '0')
	{
		if (text[1] == 'x' || text[1] == 'X') { base = 16; at = 2; }
		else if (text[1] == 'b' || text[1] == 'B') { base = 2; at = 2; }
		else if (text[1] == 'o' || text[1] == 'O') { base = 8; at = 2; }
	}
	*value = 0;
	*overflow = false;
	bool saw_digit = false;
	for (; at < text.len; at++)
	{
		char c = text[at];
		if (c == '_') continue;
		int digit = integer_digit(c);
		if (digit < 0 || (uint)digit >= base) break;
		saw_digit = true;
		if (*value > (ulong::max - (ulong)digit) / base)
		{
			*overflow = true;
			*value = ulong::max;
		}
		else if (!*overflow)
		{
			*value = *value * base + (ulong)digit;
		}
	}
	return saw_digit;
}

fn int integer_digit(char c) @local
{
	if (c >= '0' && c <= '9') return (int)(c - '0');
	if (c >= 'a' && c <= 'f') return (int)(c - 'a') + 10;
	if (c >= 'A' && c <= 'F') return (int)(c - 'A') + 10;
	return -1;
}
