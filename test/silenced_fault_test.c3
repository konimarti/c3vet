module c3vet::silenced_fault_test @test;
import c3vet;
import c3vet::testdata;
fn void silenced_fault() { testdata::verify_check(c3vet::SILENCED_FAULT, "testdata/silenced-fault.c3"); }
