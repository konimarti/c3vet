module c3vet::fixtures::import_user;

import c3vet::fixtures::api;
import c3vet::fixtures::attrs;
import c3vet::fixtures::net;
import c3vet::fixtures::unused; // want "import 'c3vet::fixtures::unused' is unused"

fn void use_imports()
{
	api::public_api();
	c3vet::fixtures::net::tcp::connect();
}

fn void use_attr() @Hot
{}
