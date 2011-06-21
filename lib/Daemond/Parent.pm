package Daemond::Parent;

sub DEBUG () { 0 }
sub DEBUG_SIG () { 0 }
sub DEBUG_SLOW () { 0 }

use uni::perl ':dumper';
use base 'Daemond::Base';

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
	$self->log->prefix("$$ CONTROL: ");
	$self->d->configure(@_);
	$self->getopt();
	$self->next::method();
	$self->d->proc->info( type => 'master' );
	$self->init_children_config;
}

sub childs { keys %{ shift->{chld} } }

sub getopt_params {
	my $self = shift;
	my $opts = shift;
	return (
		"nodetach|f!"  => sub { $opts->{detach} = 0 },
		"children|c=i" => sub { shift;$opts->{children} = shift },
		"verbose|v+"   => sub { $opts->{verbose}++ },
		'exit-on-error|x=i' => \$opts->{max_die},
	)
}
sub getopt {
	my $self = shift;
	my %opts = (
		detach  => 1,
		verbose => 0,
	);
	GetOptions(
		$self->getopt_params(\%opts)
#		"nodetach|f!"  => sub { $opts{detach} = 0 },
#		"children|c=i" => sub { shift;$opts{children} = shift },
#		"verbose|v+"   => sub { $opts{verbose}++ },
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
					$self->log->alert("CHLD: child $child died with $exitcode ($!) (".($signal ? "sig: $signal, ":'')." core: $core)");
				}
			} else {
				if ($signal || $core) {
					{
						local $! = $exitcode;
						$self->log->alert("CHLD: child $child died with $signal (exit: $exitcode/$!, core: $core)");
					}
				}
				else {
					# it's ok
					$self->log->debug("CHLD: child $child normally gone");
				}
			}
			my $pid = $child;
			if($self->{chld}) {
				if (defined( my $data=delete $self->{chld}{$pid} )) { # if it was one of ours
					my $slot = $data->[0];
					$self->score->drop($slot);
					if ($died) {
						$self->{_}{dies}++;
						if ( $self->d->max_die > 0 and $self->{_}{dies} + 1 > ( $self->d->max_die ) * $self->chld_count ) {
							$self->log->critical("Children repeatedly died %d times, stopping",$self->{_}{dies});
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
	$self->d->say("<g>starting up</>... (pidfile = ".$self->d->pid->file.", pid = <y>$$</>, detach = ".$self->d->detach.", log is null: ".$self->log->is_null.")");
	if( $self->log->is_null ) {
		#$self->d->warn("You are using null Log::Any. You will see no logs. Maybe you need to set up is with Log::Any::Adapter");
		$self->d->warn("You are using null Log::Any. We just setup a simple screen adapter. Maybe you need to set it up with Log::Any::Adapter?");
		require Log::Any::Adapter;
		Log::Any::Adapter->set('+Daemond::LogAnyAdapterScreen');
	}
	$self->log->prefix("$$ PARENT: ");
	if ($self->d->detach) {
		$self->log->debug("Do detach") if $self->d->verbose > 1;
		Daemond::Daemonization->process($self);
	} else {
		$self->log->debug("Don't detach from terminal") if $self->d->verbose > 1;
	}
}


sub start {
	my $self = shift;
	
	$self->d->proc->action('starting');
	# IPC!
	$self->{_}{startup} = 1;
	$self->{_}{forks}   = 0;

	$self->score->size( $self->{chld_count} ) if $self->{chld_count};

	$self->d->proc->action('ready');
}

sub run {
	my $self = shift;
	$self->d->pid->translate;
	$self->check_env;
	$self->daemonize;
	$self->init_sig_die;
	$self->init_sig_handlers;
	$self->start;
	
	$self->score->size > 0 or $self->d->die("Scoreboard not set, possible misconfiguration. Did you forget to call next::method for start()?");
	defined $self->d->child_class or $self->d->die( "Misconfiguration: child_class not defined" );
		$self->d->child_class->can('new') or $self->d->die( "Misconfiguration: child_class not instantiable (have no `new' method)" );
		$self->d->child_class->can('run') or $self->d->die( "Misconfiguration: child_class not runnable (have no `run' method)" );
		
	$self->log->notice("Started ($$)!");
	while ( 1 ) {
		$self->d->proc->action('idle');
		if ($self->{_}{shutdown}) {
			$self->log->notice("Received shutdown notice, gracefuly terminating...");
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
			$self->log->debug("actual childs for $alias ($check{$alias}) != required count ($count). change by $update{$alias}")
				if $self->d->verbose > 1;
		};
	}
	$self->log->debug( "Update: %s",join ', ',map { "$_+$update{$_}" } keys %update ) if %update and $self->d->verbose > 1;
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
	$self->log->alert("!!! Child should not be here!"),return if !$self->is_parent;
	$self->log->notice("ignore fork due to shutdown"),return if $self->{_}{shutdown};

	####
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
		$self->log->debug( "Parent server forked a new child $alias [slot=$slot]. children: (".join(' ', $self->childs).")" )
			if $self->d->verbose > 0;
		$self->{_}{live_check}{$pid} = 1;

		if( $self->{_}{forks} == 0 and $self->{_}{startup} ) {
			# End if pre-forking startup time.
			delete $self->{_}{startup};
		}
		return 1;
	}
	else {                              # child becomes a child process
		#DEBUG and $self->diag( "I'm forked child with slot $slot." );
		$self->log->prefix('CHILD F.'.$alias.':');
		$self->d->proc->info( state => FORKING, type => "child.$alias" );
		$SIG{TERM} = bless(sub { $self->log->alert("after-fork exit"); $self->d->exit(0); }, 'Daemond::SIGNAL');
		$SIG{INT}  = bless(sub {}, 'Daemond::SIGNAL');
=for rem
		while ( 1 ) {
			sleep 1;
			 $self->log->notice("working");
		}
		exit 0;
=cut
		my $child = $self->d->child_class;
		my $childfile = join '/',split '::',$child.'.pm';
		
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
			{
				$child->_run();
			}
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
	
	my $finishing = time;
	my %chld = %{$self->{chld}};
	if ( $self->{chld} and %chld  ) {
		# tell children to go away
		$self->log->debug("TERM'ing children [@{[ keys %chld ]}]") if $self->d->verbose > 1;
		kill TERM => $_ or delete($chld{$_}),$self->warn("Killing $_ failed: $!") for keys %chld;
	}
	
	DEBUG_SLOW and sleep(2);
	$self->next::method(@_);
	
	$self->log->debug("Reaping kids") if $self->d->verbose > 1;
	my $timeout = $self->d->exit_timeout + 1;
	while (1) {
		my $kid = waitpid ( -1,WNOHANG );
		( DEBUG or DEBUG_SIG ) and $kid > 0 and $self->log->notice("reaping $kid");
		delete $chld{$kid} if $kid > 0;
		if ( time - $finishing > $timeout ) {
			$self->log->alert( "Timeout $timeout exceeded, killing rest of processes @{[ keys %chld ]}" );
			kill KILL => $_ or delete($chld{$_}) for keys %chld;
			last;
		} else {
			last if $kid < 0;
			sleep(0.01);
		}
	}
	$self->log->debug("Finished") if $self->d->verbose;
	$self->d->exit;
}

sub child_code {
	my $self = shift;
	
}

1;
