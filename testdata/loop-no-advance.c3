module testdata_loop_no_advance;

fn void main()
{
	int i;
	int n = 10;
	int* p = &i;

	for (i = 0; i < n;) // want "loop condition never advances in the body"
	{}

	for (i = 0; i < n; i++)
	{}

	for (i = 0; i < n;)
	{
		i += 1;
	}

	for (i = 0; i < n;)
	{
		i++;
	}

	for (i = 0; i < n;)
	{
		--i;
	}

	for (i = 0; i < n;)
	{
		p = &i;
	}

	for (i = 0; i < n;)
	{
		if (i == 5)
		{
			i = i + 1;
		}
	}

	for (;;)
	{}

	// Known false-positive class: the counter advances through the pointer
	// alias `p`, which this check cannot see through -- or the loop exits
	// via `break` before an advance is ever needed. Both are documented
	// limitations, not bugs in the check.
	// The finding below is the expected one for the `break` case.
	for (i = 0; i < n;) // want "loop condition never advances in the body"
	{
		if (i == 5) break;
		*p = *p + 1;
	}
}

struct Cursor
{
	int pos;
	int len;
	Cursor* inner;
}

fn void Cursor.step(&self)
{
	self.pos++;
}

fn bool Cursor.next(&self) => ++self.pos < self.len;

fn int Cursor.count(&self) => self.len;

fn bool more() => false;

fn bool has_more(int i) => i < 3;

const int LIMIT = 10;

// the condition's variable changes in a way a plain assignment check misses
fn void method_on_condition_variable()
{
	Cursor c;
	for (; c.pos < 10;)
	{
		c.step();
	}
	for (; c.pos < 10;)
	{
		c.inner.step();
	}
}

fn void field_of_condition_variable()
{
	Cursor c;
	for (; c.pos < 10;)
	{
		c.pos++;
	}
	for (; c.pos < 10;)
	{
		c.pos = c.pos + 1;
	}
	for (; c.inner.pos < 10;)
	{
		c.inner.pos += 1;
	}
}

// the call is all the condition has: it may advance the loop itself
fn void condition_advances_itself()
{
	Cursor c;
	for (; c.next();)
	{}
	for (; !c.next();)
	{}
	for (; c.next() && LIMIT > 0;)
	{}
	for (; more();)
	{}
	for (; c.inner.count() > 0;)
	{}
}

// a plain value next to the call is still expected to change
fn void forgotten_increment_next_to_a_call(int[] a)
{
	Cursor c;
	int i;
	for (i = 0; i < a.len;) // want "loop condition never advances in the body"
	{
		if (a[i] == 0) return;
	}
	for (i = 0; i < c.count();) // want "loop condition never advances in the body"
	{}
	for (; has_more(i);) // want "loop condition never advances in the body"
	{}
	for (; c.pos < c.count();) // want "loop condition never advances in the body"
	{}
}

// writing an element, or another variable's field, advances nothing
fn void unrelated_writes(int[] a)
{
	Cursor other;
	int i;
	for (i = 0; i < a.len;) // want "loop condition never advances in the body"
	{
		a[i] = 0;
		other.pos++;
		other.step();
	}
}
