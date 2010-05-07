#!/usr/bin/perl


use strict;
use lib::abs '..';
use Log::Any::Adapter;
use Rambler::Log;

{( open my $f, '>', lib::abs::path('debug.log') or die "$!" ) and truncate $f;}
my $dispatch = Rambler::Log->mklog;
$dispatch->add( Log::Dispatch::File->new(
	name => 'file', filename => lib::abs::path('debug.log'), min_level => 'debug',
));
Log::Any::Adapter->set( 'Dispatch', dispatcher => $dispatch );

package Test::Daemon;
use strict;

use Daemond -parent;

cli;
name 'test';

#=for rem
package Test::Daemon::Child;

use strict;
use Daemond -child => 'Test::Daemon';

#sub start {};
#sub run   {};
#sub stop  {};
#=cut

package main;

use uni::perl ':dumper';

my $d = Test::Daemon->new({
	pid      => '/tmp/mons.daemond.test.pid',
	children => { default => 1, another => 2},
});
$d->run;

__END__
-MDaemond=exec=Test::Daemon::Child


__END__

package t::simple;

sub new {
    return bless {}, shift;
}
sub start {
    warn "starting";
}
sub stop {
    warn "stopping";
}
sub run {
    warn "run";
}

package main;
use strict;
use lib::abs '..';
    use Daemond::Simple
        -class => 't::simple',             # package that implements new, start, run, stop
        -cli   => 1,                       # the default
        -name  => 'test-daemon',           # by default will be 'simple.package';
        -pid   => '/var/run/%n.%u.pid',    # will be /var/run/my-daemon.user.pid
        # -log => ... # TODO
    ;


__END__
use Daemond::Pid;
use Daemond::Cli;

use Log::Any::Adapter;
use Rambler::Log;
use POSIX;

Log::Any::Adapter->set( 'Dispatch', dispatcher => Rambler::Log->mklog );

my %pids;

our $pidf = '/tmp/test.pid';

my @childs = (
	[
		sub {
			my $p = Daemond::Pid->new( file => $pidf );
			$p->lock;
			$SIG{TERM} = sub {warn "TERM"; return; };
			sleep 5;
		}
	],
	[ sub {
		my $p = Daemond::Pid->new( file => $pidf );
		my $cli = Daemond::Cli->new( pid => $p );
		warn "$$: Process cli";
		$cli->process;
		warn "$$: Process cli done";
		#$p->lock or warn "$$: Not locked: ".$p->old;
		exit 0;
	},sub {
		waitpid $_[0],0; delete $pids{$_[0]}
	} ],
);

while (@childs) {
	my $child = shift @childs;
	my $parent;
	if (ref $child eq 'ARRAY') {
		($child,$parent) = @$child;
	}
	if (my $pid = fork) {
		$pids{$pid}++;
		$parent->($pid) if $parent;
	} else {
		$child or exit;
		POSIX::setsid() or die "$!";
		warn "$$: started\n";
		$child->();
		exit 0;
	}
}
waitpid $_,0 for keys %pids;
