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

fn Holder field_assign_returned_in_pool()
{
	@pool()
	{
		Holder h;
		h.ptr = mem::talloc(int); // want "returned struct holds temp memory"
		return h;
	};
}

fn Holder literal_returned_in_pool()
{
	@pool()
	{
		return (Holder){ .ptr = mem::talloc(int) }; // want "returned struct holds temp memory"
	};
}

fn Holder initialized_var_returned_in_pool()
{
	@pool()
	{
		Holder h = { .ptr = mem::talloc(int) }; // want "returned struct holds temp memory"
		return h;
	};
}

fn StrHolder pool_local_stored_in_outer_struct()
{
	StrHolder h;
	@pool()
	{
		String s = string::tformat("%s", "x");
		h.s = s; // want "returned struct holds temp memory"
	};
	return h;
}

fn Holder literal_assigned_to_outer_struct()
{
	Holder h;
	@pool()
	{
		h = { .ptr = mem::talloc(int) }; // want "returned struct holds temp memory"
	};
	return h;
}

fn StrHolder nested_pool()
{
	@pool()
	{
		StrHolder h;
		@pool()
		{
			h.s = string::tformat("%s", "x"); // want "returned struct holds temp memory"
		};
		return h;
	};
}

fn StrHolder pool_init_struct()
{
	StrHolder h;
	@pool_init(mem, 1024)
	{
		h.s = string::tformat("%s", "x"); // want "returned struct holds temp memory"
	};
	return h;
}

// The caller's pool owns these.
fn Holder valid_no_pool()
{
	Holder h;
	h.ptr = mem::talloc(int);
	return h;
}

fn StrHolder valid_no_pool_literal()
{
	return { .s = string::tformat("%s", "x") };
}

fn StrHolder valid_allocated_before_pool()
{
	String s = string::tformat("%s", "x");
	@pool()
	{
		StrHolder h;
		h.s = s;
		return h;
	};
}

fn StrHolder valid_copied_out()
{
	StrHolder h;
	@pool()
	{
		String s = string::tformat("%s", "x");
		h.s = s.copy(mem);
	};
	return h;
}

fn Holder valid_heap()
{
	@pool()
	{
		Holder h;
		h.ptr = mem::alloc(int);
		return h;
	};
}

fn void valid_not_returned()
{
	@pool()
	{
		Holder h;
		h.ptr = mem::talloc(int);
	};
}
