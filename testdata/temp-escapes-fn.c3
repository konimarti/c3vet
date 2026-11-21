module testdata_temp_escapes_fn;

import std::core::mem;
import std::core::string;

fn int* escape_direct()
{
	int* p = mem::talloc(int);
	return p; // want "temp-allocated memory returned from a function"
}

fn int* escape_via_local()
{
	int* p = mem::talloc(int);
	return p; // want "temp-allocated memory returned from a function"
}

fn int[] escape_via_slice()
{
	int[] arr = mem::talloc_array(int, 16);
	return arr[1..4]; // want "temp-allocated memory returned from a function"
}

fn void* escape_via_tmem()
{
	void* p = make_buf(tmem);
	return p; // want "temp-allocated memory returned from a function"
}

fn String escape_via_tformat()
{
	String s = string::tformat("%s-%s", "x", "y");
	return s; // want "temp-allocated memory returned from a function"
}

fn String escape_via_method_wrapper()
{
	String s = "x".tconcat("y");
	return s; // want "temp-allocated memory returned from a function"
}

fn int* valid_heap()
{
	int* p = mem::alloc(int);
	return p;
}

fn int valid_value()
{
	int x = 123;
	return x;
}

fn void* make_buf(Allocator a) => mem::alloc(int, a);
