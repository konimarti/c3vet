module testdata_contract_void_return;

<*
 @return "always zero"
*>
fn void f(int n) {}                  // want "@return is documented on a function that returns void"

<*
 @require n > 0
*>
fn void g(int n) {}

fn void h(int n) {}

<*
 @return "the doubled value"
*>
fn int k(int n) => n * 2;

<*
 @return "always zero"
*>
fn void m(int n) {} // c3vet:ignore[contract-void-return]
