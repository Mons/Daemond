#!/usr/bin/perl


use strict;
use lib::abs '..';
use Log::Any::Adapter;
use Rambler::Log;
use Log::Dispatch::File;

#{open my $f, '>', lib::abs::path('debug.log');truncate $f,0;}
my $dispatch = Rambler::Log->mklog;
$dispatch->add( Log::Dispatch::File->new(
	name => 'file', mode => 'append', filename => lib::abs::path('debug.log'), min_level => 'debug',
));
$dispatch->remove('syslog');
$dispatch->remove('screen');
Log::Any::Adapter->set( 'Dispatch', dispatcher => $dispatch );

package Test::Daemon;
use strict;

use Daemond -parent;

cli;
proc;
name 'mytest';
child {
	my $self = shift;
	warn "Run codechild @_";
	# You may override $SIG{USR2} here to interrupt operation and leave this sub
	$SIG{USR2} = sub { warn "My USR2"; sleep 11; };
	my $iter = 0;
	while (1) {
		eval{
			$self->log->debug("code run!");
			for (1..10000) { ++$a }
			if (++$iter == 1) {
				#kill TERM => getppid();
			}
			sleep 1;
		};
		warn $@ if $@;
	}
};

package main;

use uni::perl ':dumper';

my $d = Test::Daemon->new({
	pid      => '/tmp/mons.daemond.test.pid',
	children => 1,
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
