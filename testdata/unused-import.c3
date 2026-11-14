module c3vet::fixtures::import_user;

import c3vet::fixtures::api;
import c3vet::fixtures::unused; // want "import 'c3vet::fixtures::unused' is unused"
import c3vet::fixtures::net;

fn void use_imports()
{
	api::public_api();
	c3vet::fixtures::net::tcp::connect();
}
