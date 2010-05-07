#!/usr/bin/perl

use strict;
use lib::abs '..';
use Daemond::Pid;
use Log::Any::Adapter;
use Rambler::Log;
use POSIX;

Log::Any::Adapter->set( 'Dispatch', dispatcher => Rambler::Log->mklog );

my %pids;

our $pidf = '/tmp/test.pid';

my @childs = (
	[ sub {
		my $p = Daemond::Pid->new( file => $pidf );
		$p->lock or warn "$$: Not locked: ".$p->old;
		%$p = ();
		exit 0;
	},sub { waitpid $_[0],0; warn "Created stalled lockfile"; delete $pids{$_[0]} } ],
	sub {
		my $p = Daemond::Pid->new( file => $pidf );
		$p->lock or warn "$$: Not locked: ".$p->old;
		sleep 3;
	},
	sub {
		my $p = Daemond::Pid->new( file => $pidf );
		$p->lock or warn "$$: Not locked: ".$p->old;
		sleep 3;
	}
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
		POSIX::setsid() or die "$!";
		warn "$$: started\n";
		$child->();
		exit 0;
	}
}
waitpid $_,0 for keys %pids;
__END__
if (my $pid = fork) { push @pids, $pid;
if (my $pid = fork) { push @pids, $pid;

waitpid $_,0 for @pids;
}else {
	# child
	POSIX::setsid() or die "$!";
	my $p = Daemond::Pid->new( '/tmp/test.pid' );
	sleep 1;
}
}else {
	# child
	POSIX::setsid() or die "$!";
	my $p = Daemond::Pid->new( '/tmp/test.pid' );
	sleep 1;
}
#my $p = Daemond::Pid->new( '/tmp/test.pid' );
