module testdata_idiomatic_c3;
import std::core::mem;

fn void free_rule(char* p, char[] s)
{
	mem::free(p);             // want "mem::free is just free"
	free(s);                  // no diagnostic expected
	std::core::mem::free(p);  // want "mem::free is just free"
	mem::free(s.ptr);         // want "takes the slice directly"
	char[8] encoded = {};     // want "redundant"
	char[8] decoded;          // no diagnostic expected
	int[] nums = { 1, 2 };    // no diagnostic expected
}

fn void copy_rule(char[] src, char[] other)
{
	char[8] buf;
	mem::copy(&buf, src.ptr, 4);   // want "slice assignment"
	buf[:4] = src[:4];             // no diagnostic expected
	mem::copy(&buf, other.ptr, 4); // want "slice assignment"
	char[] dst = src;
	mem::copy(&dst, src.ptr, 4);   // no diagnostic expected: dst is a slice, not an array
}

fn void catch_default_rule(char[]? opt, char[]? other)
{
	char[] out;
	if (catch opt)                 // want "optional else operator"
	{
		out = {};
	}
	else
	{
		out = opt;
	}
	if (catch opt)                 // no diagnostic expected: branches assign different targets
	{
		out = {};
	}
	else
	{
		char[] unused = other;
	}
	out = opt ?? {};               // no diagnostic expected
}
