#!/usr/bin/perl

use strict;
use lib::abs '..';
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
