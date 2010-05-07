package Daemond::Parent;

sub DEBUG () { 1 }
sub DEBUG_SIG () { 1 }
sub DEBUG_SLOW () { 1 }
=for rem
use constant::def DEBUG => 1;
use constant::def +{
	DEBUG_SC   => DEBUG || 0,
	DEBUG_SIG  => DEBUG || 0,
	DEBUG_SLOW => 0,#DEBUG || 0,
};
=cut

use uni::perl ':dumper';
use Daemond::Base;
BEGIN { push our @ISA, 'Daemond::Base' }

use Time::HiRes qw(time sleep);
use POSIX qw(WNOHANG);
use accessors::fast
	'chld',       # a hash with child pid as a key
	'chld_count', # count of all required child within all groups
	#qw(user group syslog)
;
#  max_children max_requests start_children min_spare max_spare

use Daemond::Scoreboard ':const';

our @SIG;
BEGIN {
	use Config;
	@SIG = split ' ',$Config{sig_name};
	$SIG[0] = '';
}
use Getopt::Long qw(:config gnu_compat bundling);

sub is_parent  { 1 }

sub init {
	my $self = shift;
	$self->log->prefix('CONTROL: ');
	$self->d->configure(@_);
	$self->getopt();
	$self->next::method(@_);
	$self->d->proc->info( type => 'master' );
	$self->init_children_config;
}

sub childs { keys %{ shift->{chld} } }

sub getopt {
	my $self = shift;
	my %opts = (
		detach  => 1,
		verbose => 0,
	);
	GetOptions(
		"nodetach|f!"  => sub { $opts{detach} = 0 },
		"children|c=i" => sub { shift;$opts{children} = shift },
		"verbose|v+"   => sub { $opts{verbose}++ },
		#"nodebug!" => sub { $ND = 1 },
	); # TODO: catch errors
	$self->d->configure(%opts);
	return;
}

sub init_children_config {
	my $self = shift;
	
	my $ccfg = $self->d->children || {}; # child config
	if ($ccfg and !ref $ccfg) {
		$ccfg = $self->d->children({ default => $ccfg });
	}
	if (%$ccfg) {
		my $total=0;
		for (keys %$ccfg) {
			$total += $ccfg->{$_}
		}
		#$self->log->debug("Total children: $total");
		$self->{chld_count} = $total;
	} else {
		#$self->log->debug("No children mode");
	}
}


sub SIGTERM {
	my $self = shift;
	if($self->{_}{shutdown}) {
		$self->log->warn("Received TERM during shutdown, force exit");
		kill KILL => -$_,$_ for $self->childs;
		exit 1;
	}
	$self->log->warn("Received TERM, shutting down");
	$self->{_}{shutdown} = 1;
	my $timeout = ( $self->d->exit_timeout || 10 ) + 1;
	$self->log->warn("Received TERM, shutting down with timeout $timeout");
	$SIG{ALRM} = sub {
		$self->log->critical("Not exited till alarm, killall myself");
		kill KILL => -$_,$_ for $self->childs;
		no warnings 'internal'; # Aviod 'Attempt to free unreferenced scalar' for nester sighandlers
		exit( 255 );
	};
	alarm $timeout;
}

sub SIGINT {
	my $self = shift;
	$self->log->notice("Received INT, shutting down");
	$self->{_}{shutdown} = 1;
}

sub SIGCHLD {
	my $self = shift;
		while ((my $child = waitpid(-1,WNOHANG)) > 0) {
			my ($exitcode, $signal, $core) = ($? >> 8, $SIG[$? & 127] // $? & 127, $? & 128);
			my $died;
			if ($exitcode != 0) {
				# Shit happens with our child
				$died = 1;
				{
					local $! = $exitcode;
					$self->log->warn("CHLD: child $child died with $exitcode ($!) (".($signal ? "sig: $signal, ":'')." core: $core)");
				}
			} else {
				if ($signal || $core) {
					{
						local $! = $exitcode;
						$self->log->warn("CHLD: child $child died with $signal (exit: $exitcode/$!, core: $core)");
					}
				}
				else {
					# it's ok
					$self->log->warn("CHLD: child $child normally gone");
				}
			}
			my $pid = $child;
			if($self->{chld}) {
				if (defined( my $data=delete $self->{chld}{$pid} )) { # if it was one of ours
					my $slot = $data->[0];
					DEBUG and $self->diag( "Parent caught SIGCHLD for $pid.  children: (". join(' ', sort keys %{$self->{chld}}).")" );
					$self->score->drop($slot);
					if ($died) {
						$self->{_}{dies}++;
						if ($self->{_}{dies} > $self->d->max_die * $self->chld_count ) {
							$self->log->critical("Childs repeatedly died %d times, stopping",$self->{_}{dies});
							$self->stop();
						}
					} else {
						$self->{_}{dies} = 0;
					}
				} 
				else {
					$self->log->warn("CHLD for $pid child of someone else.");
				}
			}
		}
	
}

sub check_env {
	my $self = shift;
	
	if ($self->d->cli) {
		$self->d->cli->process;
	}
	else {
		$self->log->alert("Dummy options in no-cli mode: @ARGV") if (@ARGV);
		if ($self->d->pid) {
			if( $self->d->pid->lock ) {
				# OK
			} else {
				$self->log->alert("Pid lock failed");
				exit 255;
			}
		}
		else {
			$self->log->warn("You have configured neither cli nor pid. Beware!");
		}
	}
}

use Daemond::Daemonization;

sub daemonize {
	my $self = shift;
	#warn dumper $self->d;
	$self->d->say("<g>starting up</>... (pidfile = ".$self->d->pid->file.", pid = <y>$$</>, detach = ".$self->d->detach.")");
	$self->log->prefix('PARENT: ');
	if ($self->d->detach) {
		$self->log->notice("Do detach");
		Daemond::Daemonization->process($self);
	} else {
		$self->log->notice("Don't detach from terminal");
	}
	$self->log->notice("Ready");
	#exit;
}


sub start {
	my $self = shift;
	
	$self->d->proc->action('starting');
	# IPC!
	$self->{_}{startup} = 1;
	$self->{_}{forks}   = 0;

	$self->score->size( $self->{chld_count} ) if $self->{chld_count};

	$self->d->proc->action('ready');
	$self->log->warn("ready to serve");
}

sub run {
	my $self = shift;
	$self->check_env;
	$self->daemonize;
	$self->init_sig_die;
	$self->init_sig_handlers;
	$self->start;
	warn "Started!";
	while ( 1 ) {
		$self->d->proc->action('idle');
		if ($self->{_}{shutdown}) {
			$self->log->warn("Received shutdown notice, gracefuly terminating...");
			$self->d->proc->action('shutdown');
			last;
		}
		$self->check_scoreboard;
		$self->idle or sleep 0.1;
	}
	$self->shutdown();
}

sub stop {
	my $self = shift;
	$self->{_}{shutdown} = 1;
}

sub idle {}

sub check_scoreboard {
	my $self = shift;
	
	return if $self->{_}{forks} > 0; # have pending forks

	my $slots=$self->score->slots;
	#DEBUG_SC and $self->diag($self->score->view." CHLD[@{[ map { qq{$_=$self->{chld}{$_}[0]} } $self->childs ]}]; forks=$self->{_}{forks}");

	my %check;
	my %update;
	while(my($pid, $data)=each %{ $self->{chld} }) {
		my ($slot, $alias) = @$data;
		if (kill 0 => $pid) {
			# child alive
			$check{$alias}++;
		} else {
			$self->log->critical("child $pid, slot $slot exitted without notification? ($!)");
			delete $self->{chld}{$pid};
			$self->score->drop($slot);
		}
	}
	#$self->log->debug( "Current childs: %s",$self->dumper(\%check) );
	while ( my ($alias, $count) = each %{ $self->d->children } ) {
		$check{$alias} ||= 0;
		$check{$alias} != $count and do {
			$update{$alias} = $count - $check{$alias};
			$self->log->debug("actual childs for $alias ($check{$alias}) != required count ($count). change by $update{$alias}");
		};
	}
	$self->log->debug( "Update: %s",dumper(\%update) ) if %update;
	while ( my ($alias, $count) = each %update ) {
		if ( $count > 0 ) {
			$self->start_workers($alias, $count);
		} else {
			#DEBUG_SC and $self->diag("Killing %d",-$count);
			while ($count < 0) {
				while( my ($pid,$data) = each %{ $self->{chld} } ) {
					next if $data->[1] ne $alias;
					kill TERM => $pid or $self->log->debug("killing $pid: $!");
					$count++;
				}
			}
		}
	}
}

sub start_workers {
	my $self = shift;
	my ($alias,$n) = @_;
	$n > 0 or return;
	DEBUG and $self->diag( "Fork off $n $alias children" );
	$self->d->proc->action('forking '.$n);
	for(1..$n) {
		$self->{_}{forks}++;
		$self->fork($alias) or return;
	}
}

sub DO_FORK() { 1 }
sub fork : method {
	my ($self,$alias) = @_;

	# children should not honor this event
	# Note that the forked POE kernel might have these events in it already
	# This is unavoidable :-(
	$self->diag("!!! Child should not be here!"),return if !$self->is_parent;
	$self->log->notice("ignore fork due to shutdown"),return if $self->{_}{shutdown};

	####
	DEBUG and $self->diag( "pending forks=$self->{_}{forks} ([@{[ $self->childs ]}])" );
	if ( $self->{_}{forks} ) {
		$self->{_}{forks}--;
		$self->d->proc->action($self->{_}{forks} ? 'forking '.$self->{_}{forks} : 'idle' );
	};

	DEBUG_SLOW and sleep(0.2);

	my $slot = $self->score->take( FORKING ); # grab a slot in scoreboard

	# Failure!  We have too many children!  AAAGH!
	unless( defined $slot ) {
		$self->log->critical( "NO FREE SLOT! Something wrong" );
		return;
	}

	DEBUG and $self->diag( "Forking a child $alias" );
	my $pid;
	if (DO_FORK) {
		$pid = fork();
	} else {
		$pid = 0;
	}
	unless ( defined $pid ) {            # did the fork fail?
		$self->log->critical( "Fork failed: $!" );
		$self->score->drop($slot);   # give slot back
		return;
	}
	DEBUG_SLOW and sleep(0.2);
	
	if ($pid) {                         # successful fork; parent keeps track
		$self->{chld}{$pid} = [ $slot, $alias ];
		DEBUG and $self->diag( "Parent server forked a new child $alias. children: (".join(' ', $self->childs).")" );
		$self->{_}{live_check}{$pid} = 1;

		if( $self->{_}{forks} == 0 and $self->{_}{startup} ) {
			# End if pre-forking startup time.
			delete $self->{_}{startup};
		}
		return 1;
	}
	else {                              # child becomes a child process
		DEBUG and $self->diag( "I'm forked child with slot $slot." );
		$self->log->prefix('CHILD F.'.$alias.':');
		$self->d->proc->info( state => FORKING, type => "child.$alias" );
		$SIG{TERM} = sub { $self->log->notice("exit"); exit 0; };
=for rem
		while ( 1 ) {
			sleep 1;
			 $self->log->notice("working");
		}
		exit 0;
=cut
		my $child = $self->d->child_class;
		my $childfile = join '/',split '::',$child.'.pm';
		
		$self->log->debug('loading class: %s',$child);
		$self->d->child_class->can('new')
			or eval "use $child;1"
			or delete($INC{ $childfile }),die "$@";
		
		# We need keys, that supports by child and exists in parent
		my %parent = map {$_=>1} $self->field_list;
		delete $parent{_}; # It's a local state var
		my %child =  map {$_=>1} $child->field_list;
		my @inherit = grep { exists $parent{$_} } keys %child;
		
		my %data;
		@data{@inherit} = @$self{@inherit};
		
		if (eval {
			$child = $child->new( { %data, id => $slot, spec => $alias } );
			$child->score($self->score);
			$child->score->child($slot);
			
			#warn "New child ".$child->score->child." is: ".$child->score.' = '.Dumper($child->score);
			#$child->create_session();
			#$child->ipc->create_session;
			$child->_run();
			1;
		}) {
			$child->log->notice("Child correctly finished");
		} else {
			my $e = $@;
			$child->log->critical("Child error: $e");
			die $e;
		}
		#warn "Child reached to the END";
		CORE::exit;
	}
	return;
}

sub shutdown {
	my $self = shift;

	$self->d->proc->action('shutting down');
	$self->log->notice("Shutdown requested");

	my $finishing = time;
	my %chld = %{$self->{chld}};
	if ( $self->{chld} and %chld  ) {
		# tell children to go away
		$self->log->notice("TERM'ing children [@{[ keys %chld ]}]");
		kill TERM => $_ or delete($chld{$_}),$self->warn("Killing $_ failed: $!") for keys %chld;
	}

	DEBUG_SLOW and sleep(2);
	$self->next::method(@_);
	warn "pgrp=".getpgrp();

	$self->log->notice("Reaping kids");
	my $timeout = $self->d->exit_timeout + 1;
	while (1) {
		my $kid = waitpid ( -1,WNOHANG );
		( DEBUG or DEBUG_SIG ) and $kid > 0 and $self->log->notice("reaping $kid");
		delete $chld{$kid} if $kid > 0;
		if ( time - $finishing > $timeout ) {
			warn "Timeout $timeout exceeded, killing rest of processes @{[ keys %chld ]}\n";
			kill KILL => $_ or delete($chld{$_}) for keys %chld;
			last;
		} else {
			last if $kid < 0;
			sleep(0.01);
		}
	}
	$self->log->notice("Finished");
	$self->exit;
}

sub exit : method {
	my $self = shift;
	$self->d->destroy;
	warn "TODO: Do something on exit";
	exit 0;
}

1;
