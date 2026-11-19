module testdata_redundant_mem_free;
import std::core::mem;

fn void free_rule(char* p, char[] s)
{
	mem::free(p);             // want "mem::free is just free"
	free(s);                  // no diagnostic expected
	std::core::mem::free(p);  // want "mem::free is just free"
	mem::free(s.ptr);         // want "takes the slice directly"
}
