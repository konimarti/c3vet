module testdata_temp_to_global;

import std::core::mem;
import std::core::string;

int* g_ptr = null;
tlocal int* g_tlocal_ptr = null;
String g_str = "";

int* g_bad_init = mem::talloc(int); // want "temp-allocated memory assigned to a global or thread-local variable"

fn void assign_global_direct()
{
	g_ptr = mem::talloc(int); // want "temp-allocated memory assigned to a global or thread-local variable"
}

fn void assign_global_local()
{
	int* p = mem::talloc(int);
	g_ptr = p; // want "temp-allocated memory assigned to a global or thread-local variable"
}

fn void assign_tlocal()
{
	int* p = mem::talloc(int);
	g_tlocal_ptr = p; // want "temp-allocated memory assigned to a global or thread-local variable"
}

fn void assign_static_local()
{
	static int* s_ptr = null;
	int* p = mem::talloc(int);
	s_ptr = p; // want "temp-allocated memory assigned to a global or thread-local variable"
}

fn void assign_tlocal_local_init()
{
	tlocal int* t_ptr = mem::talloc(int); // want "temp-allocated memory assigned to a global or thread-local variable"
}

fn void valid_local_assign()
{
	int* p = mem::talloc(int);
	int* q = null;
	q = p;
}

fn void assign_global_via_wrapper()
{
	g_str = string::tformat("%s", "x"); // want "temp-allocated memory assigned to a global or thread-local variable"
}

fn void valid_foreach_var(String[] xs)
{
	foreach (x : xs) x = string::tformat("%s", x);
	foreach_r (i, x : xs) x = string::tformat("%s", i);
}

fn void valid_body_param(String[] xs)
{
	@each(xs; x)
	{
		x = string::tformat("%s", x);
	};
}

fn void valid_heap_global()
{
	g_ptr = mem::alloc(int);
}
