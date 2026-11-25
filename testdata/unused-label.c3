module testdata_unused_label;

// Two functions reuse the same label name on purpose: proves labels are
// scoped per-FN_DECL, not per-file -- f1's use of OUTER must not suppress
// f2's unused OUTER.

fn void f1()
{
	while OUTER: (true)
	{
		break OUTER;
	}
}

fn void f2()
{
	while OUTER: (true) // want "label 'OUTER' is never used"
	{}
}

fn void f3()
{
	int i;
	for UNUSED: (i = 0; i < 10; i++) // want "label 'UNUSED' is never used"
	{}
}

fn void f4()
{
	int i;
	int j;
	for OUTER: (i = 0; i < 10; i++)
	{
		for (j = 0; j < 10; j++)
		{
			if (j == 5) continue OUTER;
		}
	}
}

fn void targeted_by_nextcase(int x)
{
	switch OUTER: (x)
	{
		case 1:
			switch (x)
			{
				default:
					nextcase OUTER: 2;
			}
		case 2:
			break;
		default:
			break;
	}
}

fn void unlabelled_nextcase(int x)
{
	switch UNUSED: (x) // want "label 'UNUSED' is never used"
	{
		case 1:
			nextcase 2;
		case 2:
			break;
		default:
			break;
	}
}
