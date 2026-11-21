module testdata_temp_escapes_struct;

import std::core::mem;
import std::core::string;

struct Holder
{
	int* ptr;
}

struct StrHolder
{
	String s;
}

fn Holder test_field_assign_escape()
{
	Holder h;
	h.ptr = mem::talloc(int); // want "temp-allocated memory stored into struct field and returned"
	return h;
}

fn Holder test_direct_lit_escape()
{
	return (Holder){ .ptr = mem::talloc(int) }; // want "temp-allocated memory stored into struct field and returned"
}

fn Holder test_init_var_escape()
{
	Holder h = { .ptr = mem::talloc(int) }; // want "temp-allocated memory stored into struct field and returned"
	return h;
}

fn Holder test_valid_heap()
{
	Holder h;
	h.ptr = mem::alloc(int);
	return h;
}

fn StrHolder test_field_assign_escape_via_wrapper()
{
	StrHolder h;
	h.s = string::tformat("%s", "x"); // want "temp-allocated memory stored into struct field and returned"
	return h;
}

fn void test_not_returned()
{
	Holder h;
	h.ptr = mem::talloc(int);
}
