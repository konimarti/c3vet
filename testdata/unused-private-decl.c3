module c3vet::fixtures::private_scope;

fn void dead_private() @private
{} // want "@private declaration 'dead_private'"
fn void sibling_private() @private
{}
fn void referenced_private() @private
{
	referenced_private();
}
fn void dead_local() @local
{} // want "@local declaration 'dead_local'"
fn void used_local() @local
{}

fn void local_user()
{
	used_local();
}

// reached without being named
fn void at_init() @local @init
{}
fn void at_fin() @local @finalizer
{}
fn void exported() @private @export("exported_symbol")
{}
fn void a_test() @private @test
{}
fn void a_benchmark() @private @benchmark
{}
fn void kept() @private @nostrip
{}
int exported_global @private @export("exported_global_symbol") = 1;

struct Vec
{
	int[2] v;
}

fn int Vec.get(&self, sz i) @operator([]) @private => self.v[i];
fn Vec Vec.add(self, Vec o) @operator(+) @private => self;

interface Speaker
{
	fn void speak();
}

struct Dog (Speaker)
{
	int x;
}

fn void Dog.speak(&self) @private @dynamic
{}

// c3c ignores @private and @local on methods, so these are public
fn void Dog.helper(&self) @private
{}
fn void Dog.local_helper(&self) @local
{}
macro Dog.shortcut(&self) @private => self.x;
