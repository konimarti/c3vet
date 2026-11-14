module testdata_temp_wrong_free;

import std::core::mem;

fn void bad_free_local()
{
	int* p = mem::talloc(int);
	mem::free(p); // want "free called on temp-allocated memory"
}

fn void bad_free_direct()
{
	mem::free(mem::talloc(int)); // want "free called on temp-allocated memory"
}

fn void bad_free_bare()
{
	int* p = talloc(int);
	free(p); // want "free called on temp-allocated memory"
}

fn void bad_free_tmem()
{
	void* p = make_buf(tmem);
	free(p); // want "free called on temp-allocated memory"
}

fn void good_heap_free()
{
	int* p = mem::alloc(int);
	mem::free(p);
}

fn void good_null_free()
{
	mem::free(null);
}

fn void* make_buf(Allocator a) => mem::alloc(int, a);
