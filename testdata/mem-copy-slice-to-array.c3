module testdata_mem_copy_slice_to_array;
import std::core::mem;

fn void copy_rule(char[] src, char[] other)
{
	char[8] buf;
	mem::copy(&buf, src.ptr, 4);   // want "slice assignment"
	buf[:4] = src[:4];             // no diagnostic expected
	mem::copy(&buf, other.ptr, 4); // want "slice assignment"
	char[] dst = src;
	mem::copy(&dst, src.ptr, 4);   // no diagnostic expected: dst is a slice, not an array
}
