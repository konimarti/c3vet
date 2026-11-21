module testdata_temp_escapes_pool;

import std::core::mem;
import std::core::string;

struct Holder
{
	int* ptr;
}

fn void test_pool_escapes()
{
	int* outer_p = null;
	Holder h;

	@pool()
	{
		outer_p = mem::talloc(int); // want "temp-allocated memory inside @pool assigned to variable declared outside pool"

		int* inner_p = mem::talloc(int);
		outer_p = inner_p; // want "temp-allocated memory inside @pool assigned to variable declared outside pool"

		h.ptr = mem::talloc(int); // want "temp-allocated memory inside @pool assigned to variable declared outside pool"

		// Local to pool: safe
		int* local_to_pool = mem::talloc(int);
		int val = 42;
		outer_p = &val;
	};
}

fn void test_pool_escapes_via_wrapper()
{
	String outside;

	@pool()
	{
		String t = string::tformat("hello %s", "x");
		outside = t; // want "temp-allocated memory inside @pool assigned to variable declared outside pool"

		String u = "a".tconcat("b");
		outside = u; // want "temp-allocated memory inside @pool assigned to variable declared outside pool"
	};
}
