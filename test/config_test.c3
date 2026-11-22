module c3vet::config_test @test;

import c3vet;

fn void enable_all_runs_every_check_but_disable_still_wins()
{
	CheckFn noop = fn void(Ctx* ctx, Unit* u) {};
	Check off = { .name = "zz-off", .default_on = false, .run = noop };
	Check on = { .name = "zz-on", .default_on = true, .run = noop };

	Config cfg;
	cfg.init(tmem);
	assert(!cfg.runs(off) && cfg.runs(on));

	cfg.enable_all = true;
	assert(cfg.runs(off) && cfg.runs(on));

	cfg.disabled.push("zz-off");
	assert(!cfg.runs(off) && cfg.runs(on), "--disable must beat --enable-all");
}
