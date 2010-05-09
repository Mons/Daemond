package Daemond::Child;

use uni::perl;
use base 'Daemond::Base';
use Daemond::Scoreboard ':const';

use accessors::fast qw(id ppid spec);

use Time::HiRes qw(sleep time setitimer ITIMER_VIRTUAL);

sub is_child { 1 }

sub init {
	my $self = shift;
	$self->next::method(@_);
	$self->init_sig_die;
	$self->init_sig_handlers;
	$self->{ppid} = getppid();
	$self->log->prefix($$.' CHILD '.$self->id.($self->spec ? '.'.$self->spec : '').': ');
}

sub SIGTERM {
	my $self = shift;
	if($self->{_}{shutdown}) {
		$self->log->warn("Received TERM during shutdown, force exit");
		$self->d->exit( 1 );
	}
	$self->stop();
}

sub SIGINT {
	# IGNORE
}
sub SIGCHLD {
	# IGNORE subforks
}

sub start {
	my $self = shift;
	$self->state(STARTING);
	$self->d->proc->action('child');
	my $interval = 0.0001;
	my $wallclock = time;
	$SIG{VTALRM} = sub {
		return if $self->{_}{shutdown};
		my $delta = time - $wallclock;
		if ($delta < 0.05) {
			# We're under cpu load
			$interval *= 2;
		}
		elsif ($delta > 10) {
			# We're under idle
			$interval /=2;
		}
		#$self->log->alert("vtalarm check $delta. interval = $interval");
		$wallclock = time;
		$self->check_parent;
		return if $self->{_}{shutdown};
		setitimer ITIMER_VIRTUAL, $interval, 0;
		
	};
	setitimer ITIMER_VIRTUAL, $interval, 0;
	$self->state(READY);
	return;
}

sub check_parent {
	my $self = shift;
	return if kill 0, $self->{ppid};
	$self->log->alert("I've lost my parent, stopping...");
	$self->stop;
}

sub _run {
	my $self = shift;
	$self->start;
	$self->run;
}

sub stop_watcher {
	my $self = shift;
	setitimer ITIMER_VIRTUAL, 0, 0;
	my $timeout = $self->d->exit_timeout;
	$self->log->notice("Shutting down with timeout $timeout");
	$SIG{ALRM} = sub {
		$self->log->critical("Not exited till alarm, shoot myself in a head");
		$self->d->exit( 255 );
	};
	alarm $timeout;
	return;
}

sub stop_flag {
	my $self = shift;
	$self->{_}{shutdown} = 1;
}

sub stop {
	my $self = shift;
	$self->stop_watcher;
	$self->stop_flag;
}

sub run {
	croak "Redefine run in subclass";
}

sub run2 {
	my $self = shift;
	while ( 1 ) {
		for (1..10000) { ++$a };
		$self->check_parent;
		if ($self->{_}{shutdown}) {
			$self->log->warn("Received shutdown notice, gracefuly terminating...");
			last;
		}
		sleep 1;
		$self->log->notice("working");
	}
	warn "Child ended";
	$self->shutdown();
}

sub shutdown {
	my $self = shift;
	$self->next::method();
	$self->d->exit();
}

1;
