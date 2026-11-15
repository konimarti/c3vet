module c3vet::stdlib_root_test;

import c3vet;
import std::io;
import std::os::env;

extern fn CInt symlink(ZString target, ZString linkpath) @feat(!WIN32);

fn Path? fake_layout(String name)
{
	Path root = path::temp_directory(tmem)!.tappend(name)!;
	if (path::exists(root)) path::rmtree(root)!;
	path::mkdir(root.tappend("real/lib/std")!, true)!;
	path::mkdir(root.tappend("bin")!, true)!;
	file::save(string::tformat("%s/real/c3c", (String)root), "")!;
	return root;
}

<* PATH holds a symlink with a relative target, as in ~/.local/bin/c3c -> ../opt/c3c-x/c3c. *>
fn void test_stdlib_through_relative_symlink() @test
{
	$if !env::WIN32:
		Path root = fake_layout("c3vet_stdlib_symlink")!!;
		defer (void)path::rmtree(root);
		String r = (String)root;
		assert(symlink("../real/c3c", string::tformat("%s/bin/c3c", r).zstr_tcopy()) == 0);

		String? old_path = env::tget_var("PATH");
		String? old_std = env::tget_var("C3VET_STDLIB");
		defer
		{
			if (try old_path) env::set_var("PATH", old_path);
			if (try old_std) env::set_var("C3VET_STDLIB", old_std);
		}
		env::clear_var("C3VET_STDLIB");
		env::set_var("PATH", string::tformat("%s/bin", r));

		String std = c3vet::find_stdlib_root(tmem);
		assert(std == string::tformat("%s/bin/../real/lib/std", r), "got '%s'", std);
		assert(path::exists(path::tnew(std)!!));
	$endif
}

fn void test_stdlib_path_separator() @test
{
	Path root = fake_layout("c3vet_stdlib_sep")!!;
	defer (void)path::rmtree(root);
	String real = string::tformat("%s/real", (String)root);
	String want = string::tformat("%s/lib/std", real);
	String bin = env::WIN32 ? "c3c.exe" : "c3c";
	file::save(string::tformat("%s/%s", real, bin), "")!!;

	// Windows-style PATH entries come first and do not exist here.
	String win = string::tformat("C:\\a;C:\\b;%s", real);
	assert(c3vet::find_stdlib_in_path(win, ";", bin, tmem) == want);
	// With the wrong separator the whole string is one bogus entry.
	assert(c3vet::find_stdlib_in_path(win, ":", bin, tmem) == "");
	// POSIX form; on Windows the drive letter in `real` contains ':' itself.
	$if !env::WIN32:
		assert(c3vet::find_stdlib_in_path(string::tformat("/nonexistent:%s", real), ":", bin, tmem) == want);
	$endif
}
