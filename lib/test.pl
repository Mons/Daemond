#!/usr/bin/env perl -w

use strict;
use lib::abs '.','../lib';


package Test::Daemon;
use strict;

use Daemond -parent;

cli;
name 'test';
child 'Child';
#child sub { ... };

package Test::Daemon::Child;

use strict;
use Daemond -child => 'Test::Daemon';

sub sig   {};
sub start {};
sub run   {};
sub stop  {};

package main;

use uni::perl ':dumper';

my $d = Test::Daemon->new({
	children => 2,
});

warn dumper $d,$d->d;

$d->run;

__END__
-MDaemond=exec=Test::Daemon::Child
