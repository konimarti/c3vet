module c3vet::fixtures::rms_shape;

struct Circle
{
	int radius;
}

fn void unique_make()
{}

module c3vet::fixtures::rms_outer::rms_inner;

fn void inner_only()
{}

module c3vet::fixtures::rms_dup::a;

fn void dup_make()
{}

module c3vet::fixtures::rms_dup::b;

fn void dup_make()
{}
