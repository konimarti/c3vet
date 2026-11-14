module testdata_unused_label;

// Two functions reuse the same label name on purpose: proves labels are
// scoped per-FN_DECL, not per-file -- f1's use of OUTER must not suppress
// f2's unused OUTER.

fn void f1()
{
	OUTER: while (true)
	{
		break OUTER;
	}
}

fn void f2()
{
	OUTER: while (true) {       // want "label 'OUTER' is never used"
	}
}

fn void f3()
{
	int i;
	UNUSED: for (i = 0; i < 10; i++) {  // want "label 'UNUSED' is never used"
	}
}

fn void f4()
{
	int i;
	int j;
	OUTER: for (i = 0; i < 10; i++)
	{
		for (j = 0; j < 10; j++)
		{
			if (j == 5) continue OUTER;
		}
	}
}
