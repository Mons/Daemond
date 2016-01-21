package MyApp;

use Daemond;

name 'myapp';

lab 'Lab'; # lab '+MyApp::Lab';
ctx 'Ctx'; # ctx '+MyApp::Ctx';

use MyApp::Lab::Test;

use Mouse;
has 'smth', is => 'rw';
# || sub new { ... }

# .Cfg->new()
# .Lab->new(cfg => $cfg)
# .App->new(lab => $lab)
# $app->check();

sub check { # bare checks on console
	warn "check @_";
}

sub start { # first start of master
	warn "start @_";
}

sub rise { # rise of master
	warn "rise @_";
	# covered vars
}

sub perish { # master should go for rebirth
	warn "perish";
	# create nest
	# cover
}

sub run { # run of child
	warn "run @_";
}

sub stop { # stop for child was requested
	warn "stop";
}

1;

