package Daemond::Cli;

use strict;
use warnings;
use Carp;
use Cwd ();
use Daemond::Log '$log';
use subs qw(log warn);

our %COLOR = (
	'/'        => 0,
    clear      => 0,
    reset      => 0,
    b          => 1,
    bold       => 1,
    dark       => 2,
    faint      => 2,
    underline  => 4,
    underscore => 4,
    blink      => 5,
    reverse    => 7,
    concealed  => 8,

    black      => 30,   on_black   => 40,
    red        => 31,   on_red     => 41,
    green      => 32,   on_green   => 42,
    yellow     => 33,   on_yellow  => 43,
    blue       => 34,   on_blue    => 44,
    magenta    => 35,   on_magenta => 45,
    cyan       => 36,   on_cyan    => 46,
    white      => 37,   on_white   => 47,
);
our $COLOR = join '|',keys %COLOR;

sub say ($;@) {
	my $color = -t STDOUT;
	my $msg = shift;
	for ($msg) {
		if ($color) {
			s{<($COLOR)>}{ "\033[$COLOR{$1}m" }sge;
		} else {
			s{<(?:$COLOR)>}{}sgo;
		}
		s{(?:\n|)$}{\033[0m\n};
	}
	printf STDOUT $msg, @_;
}

sub log { $log }
sub warn {
	my $e = "@_";$e =~ s{\n$}{};
	log->warn("$$: $e");
}

sub new {
	my $pkg = shift;
	my $self = bless { @_ }, $pkg;
	return $self;
}

sub force_quit { shift->d->exit_timeout }
sub usage {
	my $self = shift;
	my $cmd = $self->d->cmd;
$self->d->say(<<EOF);
<b><red>Usage: $cmd [options] [start|stop|restart]
    Options:
        -c N, --children N - redefine count of children</>
EOF
;
exit 255;
};

sub process {
	my $self = shift;
	my $pid = $self->d->pid or croak "Pid object required for Cli to operate";
	my $do = $ARGV[0] or $self->usage;
	$self->help if $do eq 'help';
	
	my $appname = $self->d->name; # TODO
	
	my $killed = 0;
	$self->{locked} = 0;
	my $info = "<b><green>$appname</>";
	
	if ($pid->lock) {
		# OK
	}
	elsif (my $oldpid = $pid->old) {
		if ($do eq 'stop' or $do eq 'restart') {
			$killed = $self->kill($oldpid);
			exit if $do eq 'stop';
			$self->{locked} = $pid->lock;
		}
		elsif ($do eq 'check') {
			if (kill(0,$oldpid)) {
				$self->d->say( "<g>running</> - pid <r>$oldpid</>");
				#$self->pidcheck($pidfile, $oldpid);
				exit;
			} 
		}
		elsif ($do eq 'start') {
			$self->d->say( "is <b><red>already running</> (pid <red>$oldpid</>)" );
			exit(3);
		}
		else {
			die "TODO?";
		}
	}
	else {
		$self->d->say( "<red>pid neither locked nor have old value</>");
		exit 255;
	}
	
	$self->d->say( "<y><b>no instance running</>" )
		if $do =~ /^(?:stop|check)$/ or ($do eq 'restart' and !$killed);
		#if $do =~ /^(reload|stop|check)$/ or ($do eq 'restart' and !$killed);
	
	exit if $do =~ /^(?:stop|check)$/;
	#$self->pidcheck($pidfile),exit if $do eq 'check';
	
	$self->d->say("<b><y>unknown command: <r>$do</>"),exit 255 if $do !~ /^(restart|start)$/;;
	$self->log->debug("$appname - $do");
}

# TODO: kill group dows not work

sub kill {
	my ($self, $pid) = @_;
	
	my $appname = $self->d->name; # TODO
	
	my $talkmore = 1;
	my $killed = 0;
	if (kill(0, $pid)) {
		$killed = 1;
		kill(INT => $pid);
		$self->d->say("<y>killing $pid with <b><w>INT</>");
		my $t = time;
		sleep(1) if kill(0, $pid);
		if ($self->force_quit and kill(0, $pid)) {
			$self->d->say("<y>waiting for $pid to die...</>");
			$talkmore = 1;
			while(kill(0, $pid) && time - $t < $self->force_quit + 2) {
				sleep(1);
			}
		}
		if (kill(TERM => $pid)) {
			$self->d->say("<y>killing $pid group with <b>TERM</><y>...</>");
			if ($self->force_quit) {
				while(kill(0, $pid) && time - $t < $self->force_quit * 2) {
					sleep(1);
				}
			} else {
				sleep(1) if kill(0, $pid);
			}
		}
		if (kill(KILL =>  $pid)) {
			$self->d->say("<y>killing $pid group with <r><b>KILL</><y>...</>");
			my $k9 = time;
			my $max = $self->force_quit * 4;
			$max = 60 if $max < 60;
			while(kill(0, $pid)) {
				if (time - $k9 > $max) {
					print "Giving up on $pid ever dying.\n";
					exit(1);
				}
				print "Waiting for $pid to die...\n";
				sleep(1);
			}
		}
		$self->d->say("<g>process $pid is gone</>") if $talkmore;
	} else {
		$self->d->say("<y>process $pid no longer running</>") if $talkmore;
	}
	return $killed;
}

1;

__END__

sub init {
	my $self = shift;
	my $daemon = shift;
	$daemon->log->prefix('CONTROL: ');
	$self->{detach}     = 1;
	$self->{alias}      = $daemon->{alias};
	$self->{path}       = $daemon->{_}{path};
	$self->{force_quit} = $daemon->force_quit;
	$self->{log}        = $daemon->{log};
}

sub process {
	my $self = shift;

	for ( $self->{_}{run} = join '/', $self->{path}, 'run','' ) {
		-d or mkdir $_ or croak "Can't create `$_': $!";
	}
	
	my $pidfile = $self->{pidfile} = $self->{_}{run}.$self->{alias}.'.pid';
	my $do;
	$self->getopt;
	$do = $ARGV[0] or $self->usage;
	$self->help if $do eq 'help';

	# Check config

	my $appname = $self->{alias};
	my $killed = 0;
	$self->{locked} = 0;

	print "$appname - configuration looks okay\n" if $do eq 'check';
	
	if (-e $pidfile) {
		if ($self->{locked} = $self->lock_pid) {
			chomp( my $pid = do { open my $p,'<',$pidfile; local $/; <$p> }  );
			if ($pid) {
				warn "$appname - have stalled (not locked) pidfile with pid $pid\n";
				die "Have running process with this pid. Won't do anything. Fix this yourself\n" if kill 0 => $pid;
				truncate $self->pidhandle,0;
			}else{
				# old process is dead
			}
		} else {
			sleep(2) if -M $pidfile < 2/86400;
			my $oldpid = do { open my $p,'<',$pidfile; local $/; <$p> };
			chomp($oldpid);
			if ($oldpid) {
				if ($do eq 'stop' or $do eq 'restart') {
					$killed = $self->kill($oldpid);
					exit if $do eq 'stop';
					$self->{locked} = $self->lock_pid;
				}
				elsif ($do eq 'check') {
					if (kill(0,$oldpid)) {
						print "$appname - running - pid $oldpid\n";
						$self->pidcheck($pidfile, $oldpid);
						exit;
					} 
				}
				elsif ($do eq 'start') {
					print "$appname is already running (pid $oldpid)\n";
					exit(3);
				}
			}
			else {
				die "$appname - Pid file $pidfile is invalid (empty) but locked.\nPossible parent exited without childs. Exiting\n";
			}
		}
	}
	else {
		#warn "No pidfile, let's lock\n";
		$self->{locked} = $self->lock_pid
			or die "Could not lock pid file $pidfile: $!";
	}
	if ($self->{locked}) {
		warn "File `$pidfile' was locked by me for command $do\n";
	}

	print "$appname - no instance running\n"
		if $do =~ /^(stop|check)$/ or ($do eq 'restart' and !$killed);
		#if $do =~ /^(reload|stop|check)$/ or ($do eq 'restart' and !$killed);

	exit if $do eq 'stop';
	$self->pidcheck($pidfile),exit if $do eq 'check';

	croak "Unknown command $do" if $do !~ /^(restart|start)$/;

}



=for rem
				if ($do eq 'stop' or $do eq 'restart') {
					$killed = $self->kill($oldpid);
					exit if $do eq 'stop';
					$self->{locked} = $self->do_lock;
				}
				elsif ($do eq 'check') {
					if (kill(0,$oldpid)) {
						print "$appname - running - pid $oldpid\n";
						#$self->pidcheck($pidfile, $oldpid);
						exit;
					} 
				}
				elsif ($do eq 'start') {
					print "$appname is already running (pid $oldpid)\n";
					exit(3);
				}
=cut

	print "$appname - no instance running\n"
		if $do =~ /^(stop|check)$/ or ($do eq 'restart' and !$killed);
		#if $do =~ /^(reload|stop|check)$/ or ($do eq 'restart' and !$killed);

	exit if $do eq 'stop';
	$self->pidcheck($pidfile),exit if $do eq 'check';

	croak "Unknown command $do" if $do !~ /^(restart|start)$/;

