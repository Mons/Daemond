package Daemond;

use strict;
use warnings;

our $VERSION = '1.90';

use Cwd;
use FindBin;
use Getopt::Long qw(:config gnu_compat bundling);
use POSIX qw(WNOHANG);
use Scalar::Util 'weaken';
use Fcntl qw(F_SETFL O_NONBLOCK);
use Hash::Util qw( lock_keys unlock_keys );

use EV;
use Data::Dumper;

# use Event::Emitter;
sub event {}

our $D;

our @SIG;
BEGIN {
	use Config;
	@SIG = split ' ',$Config{sig_name};
	$SIG[0] = '';
}


sub import {
	my $pkg = shift;
	my $caller = caller;
	$D = bless {}, $pkg;
	
	$D->{caller} = $caller;
	
	warn "First call $D for app $caller";

	{
		no strict 'refs';
		*{ $caller .'::d' } = sub () { $D };
		*{ $caller .'::d' } = \$D;
		for my $m (keys %Daemond::) {
			next unless $m =~ s{^export_}{};
			no strict 'refs';
			my $proto = prototype \&{ 'export_'.$m };
			$proto = '@' unless defined $proto;
			eval qq{
				sub ${caller}::${m} ($proto) { \@_ = (\$D, \@_); goto &export_$m };
				1;
			} or die;
		}
		# unless ($caller->can('new')) {
		# 	*{ $caller.'::new' } = sub {
		# 		my $pkg = shift;
		# 		my $args = ref $_[0] ? { %{ $_[0] } } : {@_};
		# 		return bless $args,$pkg;
		# 	};
		# }
		
		#${$caller."::OVERLOAD"}{dummy}++; # Register with magic by touching.
		#*{$caller.'::()'}   = sub { }; # "Make it findable via fetchmethod."
		#*{$caller.'::(&{}'} = sub {
		#	my $self = shift;
		#	return sub {
		#		warn "run it";
		#	};
		#}; # &{}
		#${$caller.'::()'}   = 1; # fallback
		#*{$caller.'::runit'} = sub { warn "runit" };
	}
	
	{
		no warnings 'redefine';
		*import = sub {
			my $caller = caller;
			no strict 'refs';
			*{ $caller .'::d' } = sub () { $D };
			*{ $caller .'::d' } = \$D;
		};
	}
}


sub register {
	my $self = shift;
	warn "register @_";
}

#### Export functions

sub export_using ($;@) {
	my $self = shift;
	my $module = shift;
	$module =~ s{^\+}{} or $module = "Daemond::$module";
	( my $fn = $module ) =~ s{::}{/}sg;
	require $fn.'.pm';
	
}

sub export_name($) {
	my $self = shift;
	$self->{src}{name} = shift;
}

sub export_nocli () {
	shift->{src}{cli} = 0;
}

#sub export_syslog($) {
#	warn "TODO: syslog";
#}

sub export_config($) {
	my $self = shift;
	$self->{src}{config_file} = shift;
}

sub export_logging(&) {
	my $self = shift;
	$self->{logconfig} = shift;
}

sub export_children ($) {
	my $self = shift;
	$self->{src}{children} = shift;
}

sub export_pid ($) {
	my $self = shift;
	$self->{src}{pidfile} = shift;
}

sub export_getopt(&) {
	my $self = shift;
	$self->{src}{options} = shift;
}

sub export_runit () {
	my $self = shift;
	$self->event("atstart");
	warn "Running...";
}

__END__

sub export_runit () {
	my $self = shift;
	$self->event("atstart");
	warn "Running...";
	$self->configure;
	# init log
	
	if ($self->{cli}) {
		#warn "Running cli";
		require Daemond::Cli;
		$self->{cli} = Daemond::Cli->new(
			d => $self,
			pid => $self->{pid},
			opt => $self->{opt},
		);
		$self->{cli}->process();
	}
	elsif ($self->{pid}) {
		#warn "Running only pid";
		if( $self->{pid}->lock ) {
			# OK
		} else {
			$self->die("Pid lock failed");
		}
	}
	else {
		$self->warn("No CLI, no PID. Beware!");
	}
	
	$self->say("<g>starting up</>... (pidfile = ".$self->abs_path( $self->pidfile ).", pid = <y>$$</>, detach = ".$self->detach.")") unless $self->silent;
	
	#if( $self->log->is_null ) {
	#	$self->warn("You are using null Log::Any. We just setup a simple screen/syslog adapter. Maybe you need to set it up with Log::Any::Adapter?");
	#	require Log::Any::Adapter;
	#	Log::Any::Adapter->set('+Daemond::Lite::Log::AdapterScreen');
	#}
	
	$self->{app} = $self->{caller}->new();
	
	$self->event("before_check");
	$self->run_check();
	$self->event("after_check");
	
	$self->log->prefix("M[$$]: ") if $self->log->can('prefix');
	
	if (defined $self->{children} and $self->{children} == 0 ) {
		# child mode
		$self->init_sig_handlers;
		
		$self->setup_signals;
		$self->{is_parent} = 0;
		$self->run_start;
		
		delete $self->{chld};
		my $exec = $self->can('exec_child'); @_ = ($self, 1); goto &$exec;
		exit 255;
	}
	
	$self->{children} > 0 or $self->die("Need at least 1 child");
	
	Daemond::Daemonization->process( $self ); #TODO: REWRITE
	
	$self->log->notice("daemonized");
	$self->proc("starting");
	
	$self->init_sig_handlers;
	
	$self->setup_signals;
	$self->setup_scoreboard;
	$self->{startup} = 1;
	$self->{is_parent} = 1;
	
	$self->proc("ready");
	
	$self->event("before_start");
	$self->run_start;
	$self->event("after_start");
	exit;
	my $grd = Daemond::Lite::Guard::guard {
		$log->warn("Leaving parent scope") if $self->{is_parent};
	};
	while () {
		#$self->d->proc->action('idle');
		if ($self->{shutdown}) {
			$self->log->notice("Received shutdown notice, gracefuly terminating...");
			#$self->d->proc->action('shutdown');
			last;
		}
		my $update = $self->check_scoreboard;
		if ( $update > 0 ) {
			#$self->start_workers($update);
			warn "spawn workers +$update" if $self->{cf}{verbose};
			for(1..$update) {
				$self->{forks}++;
				if( $self->fork() ) {
					#$self->log->debug("in parent: $new");
				} else {
					# mustn't be here
					#$self->log->debug("in child");
					return;
				};
			}
		}
		elsif ($update < 0) {
			#DEBUG_SC and $self->diag("Killing %d",-$count);
			warn "kill workers -$update" if $self->{cf}{verbose};
			while ($update < 0) {
				my ($pid,$data) = each %{ $self->{chld} };
				kill TERM => $pid or $self->log->debug("killing $pid: $!");
				$update++;
			}
		}
		
		
		$self->idle or sleep 0.1;
	}
	
	$self->shutdown();
	return;
	
	
}

#############
sub abs_path {
	my ($self,$file) = @_;
	$file = $self->{env}{cwd}.'/'.$file
		if substr($file,0,1) ne '/';
	return Cwd::abs_path( $file );
}

#############

sub proc {
	my $self = shift;
	my $msg = "@_";
	$msg =~ s{[\r\n]+}{}sg;
	$0 = "* ".$self->{name}.(
		length $self->{identifier}
			? " [$self->{identifier}]"
			: ""
	)." (".(
		exists $self->{is_parent} ?
			!$self->{is_parent} ? "child $self->{slot}" : "master"
			: "starting"
	).")".": $msg (perl)";
}


sub usage {
	my $self = shift;
	my $opts = shift;
	my $defs = shift;
	$self->init_params;
	
	print "Usage:\n\t$self->{env}{bin} [options]";
	if ( $self->{cli} ) {
		print " command";
		print "\n\nCommands are:\n";
		require Daemond::Cli;
		
		for my $cmd ( Daemond::Cli->commands ) {
			my ($name,$desc) = @$cmd;
			print "\t$name\n\t\t$desc\n";
		}
	}
	print "\n\nOptions are:\n";
	for my $opt (@{ $self->{options} }) {
		my ($desc,$eqdesc,$go, $def) = @$opt{qw( desc eqdesc getopt default)};
		my ($names) = $go =~ / ((?: \w+[-\w]* )(?: \| (?: \? | \w[-\w]* ) )*) /sx;
		my %names; @names{ split /\|/, $names } = ();
		my %opctl;
		my ($name, $orig) = Getopt::Long::ParseOptionSpec ($go, \%opctl);
		my $op = $opctl{$name}[0];
		my $oplast;
		my $first;
		print "\t";
		for ( sort { length $a <=> length $b } keys %opctl ) {
			next if !exists $names{$_};;
			print ", " if $first++;
			if (length () > 1 ) {
				print "--";
			} else {
				print "-";
			}
			print "$_";
		}
		if ($eqdesc) {
			print "$eqdesc ";
		} else {
			if ($op eq 's') {
				print "=VALUE";
			}
			elsif ($op eq 'i') {
				print "=NUMBER";
			}
			elsif ($op eq '') {
			}
			else {
				print " ($op)";
			}
		}
		if (defined $def) {
			print " [default = $def]";
		}
		if (length $desc) {
			print "\n\t\t$desc";
		}
		
		print "\n\n";
	}
	exit(255);
}


sub configure {
	my $self = shift;
	$self->env_config;
	$self->getopt_config;
	my $cfg;
	if (
		defined ( $cfg = $self->{opt}{config_file} ) or
		#defined ( $cfg = $self->{def}{config_file} ) or # ???
		defined ( $cfg = $self->{src}{config_file} ) 
	) {
		$self->{config_file} = $cfg;
		-e $cfg or $self->die("XXX No config file found: $cfg\n");
		$self->load_config;
	}
	
	$self->init_params();
	
	if ($self->{pidfile}) {
		require Daemond::Pid;
		#warn $self->{cf}{pid};
		$self->{pidfile} =~ s{%([nu])}{do{
			if ($1 eq 'n') {
				$self->{name} or $self->die("Can't assign '%n' into pid: Don't know daemon name");
			}
			elsif($1 eq 'u') {
				scalar getpwuid($<);
			}
			else {
				$self->die( "Pid name contain non-translateable entity $1" );
				'%'.$1;
			}
		}}sge;
		$self->{pid} = Daemond::Pid->new( file => $self->abs_path($self->{pidfile}), opt => $self->{opt} );
	}
	
	
}

sub option {
	my $self = shift;
	my $opt = shift;
	my $src = [ qw(opt cfg def src) ];
	if (@_ and ref $_[0]) {
		$src = shift;
	}
	my $def = shift;
	#warn "searching $opt, default: $def";
	for (@$src) {
		if ( defined $self->{$_}{$opt} ) {
			#warn "\tfound $opt in $_: $self->{$_}{$opt}";
			return ( $opt => $self->{$_}{$opt} );
		} else {
			#warn "\tnot found $opt in $_";
		}
	}
	if( defined $def ) {
		return ( $opt => $def );
	}
	else {
		()
	}
}

sub load_config {
	my $self = shift;
	my $file = $self->{config_file};
	$file = $self->{env}{cwd}.'/'.$file
		if substr($file,0,1) ne '/';
	$self->{cfg} = Daemond::Conf::load($self->abs_path( $file ));
	return;
}

sub init_params {
	my $self = shift;
	#warn Dumper $self;
	$self->{name}      = $self->option( 'name',     [ qw(src cfg env) ], $0 );
	$self->{children}  = $self->option( 'children', [ qw(opt cfg src def) ], 1);
	
	$self->{verbose}   = $self->option( 'verbose',  0);
	$self->{silent}    = $self->option( 'silent',   0);
	$self->{verbose}   = 0 if $self->{silent};
	
	$self->{detach}    = $self->option( 'detach',   1);
	
	
	$self->{cli}       = $self->option( 'cli',      [ qw(src cfg) ], 1);
	$self->{pidfile}   = $self->option( 'pid',      [ qw(src cfg) ],
		( -w "/var/run"
			? "/var/run" . (
				$< ? "/%n.%u.pid"
				: "%n.pid"
			)
			: "/tmp/%n.%u.pid"
		)
	);
	
	$self->{dies}          = $self->option( 'dies',     10);
	$self->{start_timeout} = $self->option('start_timeout', 10);
	$self->{exit_timeout}  = $self->option('exit_timeout', 10);
	$self->{check_timeout} = $self->option('check_timeout', 10);
	
	$self->{signals} = [qw(TERM INT QUIT HUP USR1 USR2)],
	$self->{cf} = []; # to die
}


sub env_config {
	my $self = shift;
	$self->{env}{cwd} = $FindBin::Bin;
	$self->{env}{bin} = $FindBin::Script;
}

sub getopt_config {
	my $self = shift;
	
	$self->{options} = [
		# name, description, getopt str, getopt sub, default
		{
			desc   => 'Print this help',
			getopt => 'help|h!',
			setto  => 'help',
		},
		{
			desc   => 'Path to config file',
			eqdesc => '=/path/to/config_file',
			getopt => 'config|c=s',
			setto  => sub {
				$_[0]{config_file} = Cwd::abs_path($_[1]);
			},
		},
		{
			desc   => 'Verbosity level',
			getopt => 'verbose|v+',
			setto  => sub { $_[0]{verbose}++ },
		},
		{
			desc   => "Don't detach from terminal",
			getopt => 'nodetach|f!',
			setto  => sub { $_[0]{detach} = 0 },
		},
		{
			desc    => 'Count of child workers to spawn',
			eqdesc  => '=count',
			getopt  => 'workers|w=i',
			setto   => 'children',
			default => 1,
		},
		{
			desc    => 'How many times child repeatedly should die to cause global terminations',
			eqdesc  => '=count',
			getopt  => 'exit-on-error|x=i',
			setto   => 'max_die',
			default => 10,
		},
		{
			desc    => 'Path to pid file',
			eqdesc  => '=/path/to/pid',
			getopt  => 'pidfile|p=s',
			setto   => sub {
				$_[0]{pidfile} = Cwd::abs_path($_[1]);
			},
		},
		{
			desc   => 'Make start/stop process less verbose',
			getopt => 'silent|s',
			setto  => 'silent',
		},
	];
	if ($self->{src}{options}) {
		push @{ $self->{options} }, $self->{src}{options}->($self);
	}
	my %opts;
	my %getopt;
	my %defs;my $i;
	for my $opt (@{ $self->{options} }) {
		my $idx = ++$i;
		if (defined $opt->{default}) {
			$defs{$idx} = $opt;
		}
		$getopt{ $opt->{getopt} } = sub {
			shift;
			delete $defs{$idx};
			if (ref $opt->{setto}) {
				$opt->{setto}->( \%opts,@_ );
			}
			else {
				$opts{ $opt->{setto} } = shift;
			}
		}
	}
	#use Data::Dumper;
	#warn Dumper \%getopt;
	GetOptions(%getopt) or $self->usage();
	$opts{help} and $self->usage();
	my %def;
	for my $opt (values %defs) {
		if (ref $opt->{setto}) {
			$opt->{setto}->( \%def, $opt->{default} );
		}
		else {
			$def{ $opt->{setto} } = $opt->{default};
		}
	}
	#warn Dumper \%opts;
	$self->{opt} = \%opts;
	$self->{def} = \%def;
}

#########

sub run_check {
	my $self = shift;
	if (my $check = $self->{app}->can('check')) {
		eval{
			$self->{app}->check( $self->{cfg} );
		1} or do {
			my $e = $@;
			$self->log->error("Check error: $e");
			exit 255;
		}
	}
}

sub run_start {
	my $self = shift;
	if (my $start = $self->{caller}->can('start')) {
		$start->($self);
	}
}

sub run_run {
	my $self = shift;
	if( my $cb = $self->{caller}->can( 'run' ) ) {
		$cb->($self);
		$self->log->notice("Child $$ correctly finished");
	} else {
		die "Whoa! no run at start!";
	}
}

############

sub shorten_file($) {
	my $n = shift;
	for (@INC) {
		$n =~ s{^\Q$_\E/}{INC:}s and last;
	}
	return $n;
}

sub init_sig_handlers {
	my $self = shift;
	my $oldsigdie = $SIG{__DIE__};
	my $oldsigwrn = $SIG{__WARN__};
	defined () and UNIVERSAL::isa($_, 'Daemond::SIGNAL') and undef $_ for ($oldsigdie, $oldsigwrn) ;
	$SIG{__WARN__} = sub {
		local *__ANON__ = "SIGWARN";
		
		if ($self and !$self->log->is_null) {
			local $_ = "@_";
			my ($file,$line);
			s{\n+$}{}s;
			#printf STDERR "sigwarn ".Dumper $_;
			if ( m{\s+at\s+(.+?)\s+line\s+(\d+)\.?$}s ) {
				($file,$line) = ($1,$2);
				s{\s+at\s+(.+?)\s+line\s+(\d+)\.?$}{}s;
			} else {
				my @caller;my $i = 0;
				my $at;
				while (@caller = caller($i++)) {
					if ($caller[1] =~ /\(eval.+?\)/) {
						$at .= " at str$caller[1] line $caller[2] which";
					}
					else {
						#$at .= " at $caller[1] line $caller[2].";
						($file,$line) = @caller[1,2];
						last;
					}
				}
				#print STDERR "match: $at\n";
				$_ .= $at;
			}
			$_ .= " at ".shorten_file($file)." line $line.";
			$self->log->warning("$_");
		}
		elsif (defined $oldsigwrn) {
			goto &$oldsigwrn;
		}
		else {
			local $SIG{__WARN__};
			local $Carp::Internal{'Daemond'} = 1;
			Carp::carp("$$: @_");
		}
	};
	bless ($SIG{__WARN__}, 'Daemond::SIGNAL');
	return;
}

sub setup_signals {
	my $self = shift;
	# Setup SIG listeners
	# ???: keys %SIG ?
	my $for = $$;
	my $mysig = 'Daemond::SIGNAL';
	for my $sig ( @{ $self->{signals} } ) {
		my $old = $SIG{$sig};
		if (defined $old and UNIVERSAL::isa($old, $mysig) or !ref $old) {
			undef $old;
		}
		$SIG{$sig} = sub {
			local *__ANON__ = "SIG$sig";
			eval {
				if ($self) {
					$self->sig(@_);
				}
			};
			warn "Got error in SIG$sig: $@" if $@;
			goto &$old if defined $old;
		};
		bless $SIG{$sig}, $mysig;
	}
	$SIG{CHLD} = sub { local *__ANON__ = "SIGCHLD"; $self->SIGCHLD(@_) };
	$SIG{PIPE} = 'IGNORE' unless exists $SIG{PIPE};
}

sub sig {
	my $self = shift;
	my $sig = shift;
	if ($self->is_parent) {
		if( my $sigh = $self->{app}->can('SIG'.$sig)) {
			@_ = ($self->{app},$sig);
			goto &$sigh;
		}
		elsif (my $sigh = $self->can('SIG'.$sig)) {
			@_ = ($self,$sig);
			goto &$sigh;
		}
		$self->log->debug("Got sig $sig, terminating");
		exit(255);
	} else {
		return if $sig eq 'INT';
		return if $sig eq 'CHLD';
		if ($sig eq 'USR1') { Carp::cluck(); return; }
		if( my $cb = $self->{app}->can( 'SIG'.$sig ) ) {
			@_ = ($self->{app},$sig);
			goto &$cb;
		}
		elsif (my $sigh = $self->can('SIG'.$sig)) {
			@_ = ($self,$sig);
			goto &$sigh;
		}
		else {
			$self->log->debug("Got sig $sig, terminating");
			exit(255);
		}
	}
}

sub childs {
	my $self = shift;
	keys %{ $self->{chld} };
}

sub SIGTERM {
	my $self = shift;
	unless ($self->is_parent) {
		if($self->{shutdown}) {
			$self->log->warn("Received TERM during shutdown, force exit");
			exit(Errno::EINTR);
		} else {
			$self->log->warn("Received TERM...");
		}
		$self->call_stop();
		return;
	}
	if($self->{shutdown}) {
		$self->log->warn("Received TERM during shutdown, force exit");
		kill KILL => -$_,$_ for $self->childs;
		exit Errno::EINTR;
	}
	$self->log->warn("Received TERM, shutting down");
	$self->{shutdown} = 1;
	my $timeout = ( $self->{exit_timeout} || 10 ) + 1;
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
	if ($self->{shutdown}) {
		my %chld = %{$self->{chld}};
		my $sig = $self->{shutdown} < 3 ? 'TERM' : 'KILL';
		if ( $self->{chld} and %chld  ) {
			# tell children once again!
			$self->log->debug("Again ${sig}'ing children [@{[ keys %chld ]}]");
			kill $sig => $_ or $self->error("Killing $_ failed: $!") for keys %chld;
		}
		
	}
	$self->{shutdown} = 1;
}

sub SIGCHLD {
	my $self = shift;
		while ((my $child = waitpid(-1,WNOHANG)) > 0) {
			my ($exitcode, $signal, $core) = ($? >> 8, $SIG[$? & 127] || $? & 127, $? & 128);
			my $died;
			if ($exitcode != 0) {
				# Shit happens with our child
				$died = 1;
				{
					local $! = $exitcode;
					$self->log->alert("Child $child died with $exitcode ($!) (".($signal ? "$signal/$SIG[$signal]":'')." core: $core)");
				}
			} else {
				if ($signal || $core) {
					{
						local $! = $exitcode;
						$self->log->error("Child $child exited by signal $signal (core: $core)");
					}
				}
				else {
					# it's ok
					$self->log->debug("Child $child normally gone");
				}
			}
			my $pid = $child;
			if($self->{chld}) {
				if (defined( my $data=delete $self->{chld}{$pid} )) { # if it was one of ours
					my $slot = $data->[0];
					$self->score_drop($slot);
					if ($died) {
						$self->{dies_cnt}++;
						if ( $self->{dies} > 0 and $self->{dies_cnt} + 1 > ( $self->{dies} ) * $self->{children} ) {
							$self->log->critical("Children repeatedly died %d times, stopping",$self->{dies_cnt});
							$self->shutdown(); # TODO: stop
						}
					} else {
						$self->{dies_cnt} = 0;
					}
				} 
				else {
					$self->log->warn("CHLD for $pid child of someone else.");
				}
			}
		}
}

sub setup_scoreboard {
	my $self = shift;
	$self->{score} = ':'.('.'x$self->{children});
}

sub score_take {
	my ($self, $status) = @_;
	if( ( my $idx = index($self->{score}, '.') ) > -1 ) {
		length $status or $status = "?";
		$status = substr($status,0,1);
		substr($self->{score},$idx,1) = $status;
		return $idx;
	} else {
		return undef;
	}
}

sub score_drop {
	my ($self, $slot) = @_;
	if ( $slot > length $self->{score} ) {
		warn "Slot $slot over bound";
		return 0;
	}
	if ( substr($self->{score},$slot, 1) ne '.' ) {
		substr($self->{score},$slot, 1) = '.';
		return 1;
	}
	else {
		warn "slot $$ not taken";
		return 0;
	}
}

sub check_scoreboard {
	my $self = shift;
	
	#$self->proc("ready [$self->{score}]");
	return 0 if $self->{forks} > 0; # have pending forks

	#DEBUG_SC and $self->diag($self->score->view." CHLD[@{[ map { qq{$_=$self->{chld}{$_}[0]} } $self->childs ]}]; forks=$self->{_}{forks}");
	
	my $count = $self->{children};
	my $check = 0;
	my $update = 0;
	while( my ($pid, $data) = each %{ $self->{chld} } ) {
		my ($slot) = @$data;
		if (kill 0 => $pid) {
			# child alive
			$check++;
			kill USR2 => $pid;
		} else {
			$self->log->critical("child $pid, slot $slot exited without notification? ($!)");
			delete $self->{chld}{$pid};
			$self->score_drop($slot);
		}
	}
	my $at = time;
	while( my ($pid, $data) = each %{ $self->{chld} } ) {
		my ($slot,$pipe,$rbuf) = @$data;
		my $r = sysread $pipe, $$rbuf, 4096, length $$rbuf;
		if ($r) {
			#warn "received $r for $slot";
			my $ix = 0;
			while () {
				last if length $$rbuf < $ix + 8;
				my ($type,$l) = unpack 'VV', substr($$rbuf,$ix,8);
				if ( length($$rbuf) - $ix >= 8 + $l ) {
					if ($type == 0) {
						# pong packet
						my $x = substr($$rbuf,$ix+8,$l);
						if ($x != $slot) {
							warn "Mess-up in pong packet for slot $slot. Got $x";
						}
						$data->[3] = $at;
					}
					else {
						warn "unknown type $type";
					}
					$ix += 8+$l;
				}
				else {
					last;
				}
			}
			$$rbuf = substr($$rbuf,$ix);
		}
		elsif (!defined $r) {
			redo if $! == Errno::EINTR;
			next if $! == Errno::EAGAIN;
			warn "read failed: $!";
		}
		else {
			warn "Child closed the pipe???";
		}
	}
	#warn sprintf "Spent %0.4fs for reading\n", time - $at;
	my $tm = $self->check_timeout;
	while( my ($pid, $data) = each %{ $self->{chld} } ) {
		my ($slot,$pipe,$rbuf,$last,$killing) = @$data;
		if (!$killing) {
			if ( time - $last > $tm ) {
				$self->log->error("Child $slot (pid:$pid) Not responding for %.0fs. Terming", time - $last  );
				$data->[4]++;
				warn "send TERM $pid";
				kill USR1 => $pid;
				kill TERM => $pid or do{
					$self->log->warn( "kill TERM $pid failed: $!. Using KILL" );
					kill KILL => $pid;
				};
			}
		}
		else {
			if ( time - $last > $tm*2 ) {
				$self->log->error("Child $slot (pid:$pid) Not exited for %.0fs. Killing", time - $last  );
				kill KILL => $pid;
			}
		}
	}
	
	#warn "check: $check/$count is alive";
	#$self->log->debug( "Current childs: %s",$self->dumper(\%check) );
	
	if ( $check != $count ) {
		$update = $count - $check;
		$self->log->debug("actual childs ($check) != required count ($count). change by $update")
			if $self->verbose > 1;
	}
	
	#$self->log->debug( "Update: %s",join ', ',map { "$_+$update{$_}" } keys %update ) if %update and $self->d->verbose > 1;
	return $update;
}

sub start_workers {
	my $self = shift;
	my ($n) = @_;
	$n > 0 or return;
	#$self->d->proc->action('forking '.$n);
	warn "start_workers +$n";
	for(1..$n) {
		$self->{forks}++;
		$self->fork() or return;
	}
}

sub DEBUG_SLOW() { 0 }
sub DO_FORK() { 1 }
sub fork : method {
	my ($self) = @_;

	# children should not honor this event
	# Note that the forked POE kernel might have these events in it already
	# This is unavoidable :-(
	$self->log->alert("!!! Child should not be here!"),return if !$self->is_parent;
	$self->log->notice("ignore fork due to shutdown"),return if $self->{shutdown};
	#warn "$$: fork";

	####
	if ( $self->{forks} ) {
		$self->{forks}--;
		#$self->d->proc->action($self->{_}{forks} ? 'forking '.$self->{_}{forks} : 'idle' );
	};

	DEBUG_SLOW and sleep(0.2);

	my $slot = $self->score_take( 'F' ); # grab a slot in scoreboard

	# Failure!  We have too many children!  AAAGH!
	unless( defined $slot ) {
		$self->log->critical( "NO FREE SLOT! Something wrong ($self->{score})" );
		return;
	}
	
	pipe my $rh, my $wh or die "Watch pipe failed: $!";
	fcntl $_, F_SETFL, O_NONBLOCK for $rh,$wh;
	
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
		$self->{chld}{$pid} = [ $slot, $rh, \(my $o), time ];
		$self->log->debug( "Parent server forked a new child [slot=$slot]. children: (".join(' ', $self->childs).")" )
			if $self->verbose > 0;
		
		if( $self->{forks} == 0 and $self->{startup} ) {
			# End if pre-forking startup time.
			delete $self->{startup};
		}
		return 1;
	}
	else {
		$self->{is_parent} = 0;
		$self->{chpipe} = $wh;
		delete $self->{chld};
		#DEBUG and $self->diag( "I'm forked child with slot $slot." );
		#$self->log->prefix('CHILD F.'.$alias.':');
		#$self->d->proc->info( state => FORKING, type => "child.$alias" );
		my $exec = $self->can('exec_child'); @_ = ($self, $slot); goto &$exec;
		#$self->exec_child();
		# must not reach here
		exit 255;
	}
	return;
}

sub shutdown {
	my $self = shift;
	
	#$self->d->proc->action('shutting down');
	
	my $finishing = time;
	
	my %chld = %{$self->{chld}};
	#$SIG{CHLD} = 'IGNORE';
	if ( $self->{chld} and %chld  ) {
		# tell children to go away
		$self->log->debug("TERM'ing children [@{[ keys %chld ]}]") if $self->verbose > 1;
		kill TERM => $_ or delete($chld{$_}),$self->warn("Killing $_ failed: $!") for keys %chld;
	}
	
	DEBUG_SLOW and sleep(2);
	
	$self->{shutdown} = 1 ;
	
	$self->log->debug("Reaping kids") if $self->verbose > 1;
	my $timeout = ( $self->exit_timeout || 10 ) + 1;
	while (1) {
		my $kid = waitpid ( -1,WNOHANG );
		#( DEBUG or DEBUG_SIG ) and
			$kid > 0 and $self->log->notice("reaping $kid");
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
	$self->log->debug("Finished") if $self->verbose;
	exit;
}


sub idle {}
sub stop {
	my $self = shift;
	if ($self->{is_parent}) {
		
	} else {
			$self->{shutdown}++ and exit(1);
			if( my $cb = $self->{app}->can( 'stop' ) ) {
				@_ = ($self->{app});
				goto &$cb;
			} else {
				exit(0);
			}
	}
}

sub parent_send {
	my $self = shift;
	my ($type, $buffer) = @_;
	utf8::encode $buffer if utf8::is_utf8 $buffer;
	syswrite($self->{chpipe}, pack('VV/a*',$type,$buffer))
			== 8+length $buffer or warn $!;
}

sub setup_child_sig {
	weaken( my $self = shift );
	$SIG{PIPE} = 'IGNORE';
	$SIG{CHLD} = 'IGNORE';
	
	die "TODO Here";
	
	my %sig = (
		TERM => bless(sub {
			local *__ANON__ = "SIGTERM";
			warn "SIGTERM received"; 
			$self->stop;
		}, 'Daemond::SIGNAL'),
		INT => bless(sub {
			local *__ANON__ = "SIGINT";
			#warn "SIGINT to child. ignored";
		}, 'Daemond::SIGNAL'),
		USR2 => bless(sub {
			local *__ANON__ = "SIGINT";
			#warn "SIGUSR2 to child. ...";
			$self->parent_send(0,$self->{slot});
			#syswrite($self->{chpipe}, pack (C => $self->{slot}))
			#	== 1 or warn $!;
		}, 'Daemond::SIGNAL'),
	);
	
	my $usersig;
	if( my $cb = $self->can( 'on_sig' ) ) {
		$usersig = 1;
		for my $sig (keys %sig) {
			$cb->($self, $sig, $sig{$sig});
		}
	}
	
	my $interval = 0.1;
	
	if ($INC{'EV.pm'}) {
		$self->{watchers}{pcheck} = EV::timer( $interval,$interval,sub {
			return if !$self or $self->{shutdown};
			$self->check_parent;
		} );
		if (!$usersig) {
			for my $sig (keys %sig) {
				$self->{watchers}{sig}{$sig} = &EV::signal( $sig => $sig{$sig} );
			}
			
		}
	}
	elsif ($INC{'AnyEvent.pm'}) {
		$self->{watchers}{pcheck} = AE::timer( $interval,$interval,sub {
			return if !$self or $self->{shutdown};
			$self->check_parent;
		} );
		if (!$usersig) {
			for my $sig (keys %sig) {
				$self->{watchers}{sig}{$sig} = &AE::signal( $sig => $sig{$sig} );
			}
			
		}
	}
	else {
		for my $sig (keys %sig) {
			$SIG{$sig} = $sig{$sig};
		}
		$SIG{VTALRM} = sub {
				return delete $SIG{VTALRM} if !$self or $self->{shutdown};
				$self->check_parent;
				setitimer ITIMER_VIRTUAL, $interval, 0;
		};
		setitimer ITIMER_VIRTUAL, $interval, 0;
	}
	
	return;
}

sub check_parent {
	my $self = shift;
	#return if kill 0, $self->{ppid};
	return if kill 0, getppid();
	$self->log->alert("I've lost my parent, stopping...");
	$self->stop;
}

sub exec_child {
	my $self = shift;
	my $slot = shift;
	delete $self->{chld};
	$self->{slot} = $slot;
	$self->log->prefix("C${slot}[$$]: ") if $self->log->can('prefix');
	$self->setup_child_sig;
	$self->proc("ready");
	
	$self->event("before_run");
	eval {
		$self->run_run;
	1} or do {
		my $e = $@;
		$self->log->error("Child error: $e");
		local $SIG{__DIE__};
		die $e;
	};
	exit;
}

sub call_stop {
	my $self = shift;
	
}


1; # End of Daemond

__END__
=head1 NAME

Daemond - Daemonization Toolkit

=head1 RATIONALE

There is a lot of daemonization utilities.
Some of them have correct daemonization, some have command-line interface, some have good pid locking.
But there is no implementation, that include all the things.

=head1 AUTHOR

Mons Anderson, C<< <mons at cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Mons Anderson, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
