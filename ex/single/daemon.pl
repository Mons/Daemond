#!/usr/bin/env perl

use Daemond;

# using 'Say';
name 'test';
# lab ''

use Mouse;
has 'smth', is => 'rw';

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
} # EV::loop


sub stop { # stop for child was requested
	warn "stop";
}

runit(); # master ... fork ... EV::loop;