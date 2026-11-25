module testdata_temp_escapes_fn;

import std::core::mem;
import std::core::string;

fn int* escape_local()
{
	@pool()
	{
		int* p = mem::talloc(int);
		return p; // want "temp-allocated memory returned out of the @pool"
	};
}

fn String escape_direct()
{
	@pool()
	{
		return string::tformat("%s", "x"); // want "temp-allocated memory returned out of the @pool"
	};
}

fn int[] escape_via_slice()
{
	@pool()
	{
		int[] arr = mem::talloc_array(int, 16);
		return arr[1..4]; // want "temp-allocated memory returned out of the @pool"
	};
}

fn void* escape_via_tmem()
{
	@pool()
	{
		void* p = make_buf(tmem);
		return p; // want "temp-allocated memory returned out of the @pool"
	};
}

struct Buf
{
	int[4] data;
}

fn int[] Buf.view(&self) => self.data[..];

fn int[] escape_via_method_call_wrapper()
{
	@pool()
	{
		Buf* p = mem::talloc(Buf);
		return p.view(); // want "temp-allocated memory returned out of the @pool"
	};
}

fn String escape_nested_pool(bool b)
{
	@pool()
	{
		String s = string::tformat("%s", "x");
		@pool()
		{
			if (b) return s; // want "temp-allocated memory returned out of the @pool"
		};
	};
	return "";
}

fn String escape_inner_only()
{
	@pool()
	{
		@pool()
		{
			String s = string::tformat("%s", "x");
			return s; // want "temp-allocated memory returned out of the @pool"
		};
	};
}

fn String escape_pool_init()
{
	mem::@pool_init(mem, 1024)
	{
		return string::tformat("%s", "x"); // want "temp-allocated memory returned out of the @pool"
	};
}

struct Holder
{
	int* ptr;
}

struct StrHolder
{
	String s;
}

fn Holder struct_field_returned()
{
	@pool()
	{
		Holder h;
		h.ptr = mem::talloc(int);
		return h; // want "temp-allocated memory returned out of the @pool"
	};
}

fn Holder struct_literal_returned()
{
	@pool()
	{
		return (Holder){ .ptr = mem::talloc(int) }; // want "temp-allocated memory returned out of the @pool"
	};
}

fn Holder struct_initialized_returned()
{
	@pool()
	{
		Holder h = { .ptr = mem::talloc(int) };
		return h; // want "temp-allocated memory returned out of the @pool"
	};
}

fn StrHolder struct_literal_assigned_returned()
{
	@pool()
	{
		String s = string::tformat("%s", "x");
		StrHolder h;
		h = { s };
		return h; // want "temp-allocated memory returned out of the @pool"
	};
}

fn StrHolder struct_set_in_nested_pool()
{
	@pool()
	{
		StrHolder h;
		@pool()
		{
			h.s = string::tformat("%s", "x");
		};
		return h; // want "temp-allocated memory returned out of the @pool"
	};
}

macro @struct_from_macro()
{
	@pool()
	{
		return (StrHolder){ .s = string::tformat("%s", "x") }; // want "temp-allocated memory returned out of the @pool"
	};
}

fn StrHolder valid_struct_without_pool()
{
	StrHolder h;
	h.s = string::tformat("%s", "x");
	return h;
}

fn StrHolder valid_struct_holds_older_temp()
{
	String s = string::tformat("%s", "x");
	@pool()
	{
		StrHolder h;
		h.s = s;
		return h;
	};
}

fn StrHolder valid_struct_holds_copy()
{
	@pool()
	{
		StrHolder h;
		h.s = string::tformat("%s", "x").copy(mem);
		return h;
	};
}

// The caller's pool owns the result.
fn String valid_no_pool()
{
	String s = string::tformat("%s", "x");
	return s;
}

fn String valid_no_pool_direct() => string::tformat("%s", "x");

fn String valid_allocated_before_pool()
{
	String s = string::tformat("%s", "x");
	@pool()
	{
		return s;
	};
}

fn String valid_returned_after_pool()
{
	@pool()
	{
		String s = string::tformat("%s", "x");
		io::printn(s);
	};
	String t = string::tformat("%s", "y");
	return t;
}

fn String valid_copied_out()
{
	@pool()
	{
		String s = string::tformat("%s", "x");
		return s.copy(mem);
	};
}

fn void* make_buf(Allocator a) => mem::alloc(int, a);
