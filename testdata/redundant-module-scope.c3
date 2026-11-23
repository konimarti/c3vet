module c3vet::fixtures::rms_user;

import c3vet::fixtures::rms_dup::a;
import c3vet::fixtures::rms_outer::rms_inner;
import c3vet::fixtures::rms_shape;

struct Widget
{
	int size;
}

fn void own_helper()
{}

fn void use_qualifiers()
{
	rms_shape::Circle c; // want "'Circle' alone resolves to the same declaration"
	c.radius = 1;

	rms_user::Widget w; // want "'Widget' alone resolves to the same declaration"
	w.size = 2;

	rms_outer::rms_inner::inner_only(); // want "'rms_inner::inner_only' alone resolves to the same declaration"

	// One segment is always allowed on a call, even a self-reference --
	// never flagged (see the check's module doc comment).
	rms_shape::unique_make();
	rms_user::own_helper();

	// 'dup_make' exists in two modules: ambiguous, so the extra segment stays.
	rms_dup::a::dup_make();
}
