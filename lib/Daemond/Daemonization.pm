#
#  A role for Daemon
#
package Daemond::Daemonization;

use strict;
use Carp;
use Daemond::Helpers;
use Time::HiRes qw(sleep time);
use POSIX qw(WNOHANG);

our @SIG;
BEGIN {
	use Config;
	@SIG = split ' ',$Config{sig_name};
	$SIG[0] = '';
}

# ->process( $daemon )

sub process {
	my $pkg = shift;
	my $self = shift; # << Really a daemon object
	return unless $self->d->detach;
	return if $self->{_}{detached}++;
	my $name = $self->d->name;
	my $cmd;
	open $cmd,"|logger -t '$name [$$]'" or die "Could not open temporary syslog command: $!\n";
	close $cmd;
		# we close it, because in case of delay in child, parent will be waiting.
		# reopen it later, only in child. We know, it works
	my $parent = $$;
	defined( my $pid = fork ) or die "Could not fork: $!";
	if ($pid) { # controlling terminal
		select( (select(STDOUT),$|=1,select(STDERR),$|=1)[0] );
		if ($self->d->pid) {
			$self->d->pid->forget;
			my $timeout = $self->d->start_timeout;
			
			local $_ = $self->d->pid->file;
			$SIG{ALRM} = sub {
				$self->d->die("Daemon not started in $timeout seconds. Possible something wrong. Look at syslog");
			};
			alarm $timeout;
			$self->d->say("<y>waiting for $pid to gone</>..\0");
			while(1) {
				if( my $kid = waitpid $pid,WNOHANG ) {
					my ($exitcode, $signal, $core) = ($? >> 8, $SIG[$? & 127] // ($? & 127), $? & 128);
					if ($exitcode != 0 or $signal or $core) {
						# Shit happens with our child
						local $! = $exitcode;
						$self->d->sayn(
							"<r>exited with code=$exitcode".($exitcode > 0 ? " ($!)" : '')." ".
							($signal ? "(sig: $signal)":'').
							($core && $signal ? ' ' : '').
							( $core ? '(core dumped)' : '')."\n");
						exit 255;
					} else {
						# it's ok
						$self->d->sayn(" <g>done</>\n");
					}
					sleep 0.1;
					last;
				} else {
					$self->d->sayn(".");
					sleep 0.1;
				}
			}
			$self->d->say("<y>Reading new pid</>...\0");
			while (1) {
				my $newpid = $self->d->pid->read;
				if ($newpid == $pid) {
					-e or $self->d->die("Pidfile disappeared. Possible daemon died. Look at syslog");
					$self->d->sayn(".");
					sleep 0.1;
				} else {
					$pid = $newpid;
					$self->d->sayn(" <g>$pid</>\n");
					last;
				}
			}
			alarm 0;
			$self->d->say("<y>checking it's live</>...\0");
			sleep 0.3;
			unless (kill 0 => $pid) {
				$self->d->sayn(" <r>no process with pid $pid. Look at syslog\n");
				exit 255;
			}
			$self->d->sayn(" <g>looks ok</>\n");
=for rem
		alarm 0;
		# unless $child;
		sleep 1 if kill 0 => $child; # give daemon time to die, if it have some errors
		kill 0 => $child or die "Daemon lost. PID $child is absent. Look at syslog\n";
=cut
		}
		exit;
	} # 1st fork
	open $cmd,"|logger -t '$name [$$]'" or die "Could not open temporary syslog command: $!\n";
	local $SIG{__DIE__} = sub {
		print $cmd $self->d->name." mid-fork failed: @_";
		close $cmd;
		exit(85);
	};
	# Exitcode tests
	#die "Test";
	#kill KILL => $$;
	#kill SEGV => $$;
	#exit 255;
	
	# Make fork once again to fully detach from controller
	defined( $pid = fork ) or die "Could not fork: $!";
	if ($pid) {
		#warn "forked 2 $pid";
		$self->d->pid->forget if $self->d->pid;
		exit;
	}
	waitpid(getppid, 0);
	$self->d->pid->relock() if $self->d->pid; # Relock after forks
	close $cmd;
	open $cmd,"|logger -t '$name [$$]'" or die "Could not open temporary syslog command: $!\n";
	local $SIG{__DIE__} = sub {
		print $cmd $self->d->name." last-fork failed: @_";
		close $cmd;
		exit(85);
	};
	
	# Exit test
	# exit 255;
	
	POSIX::setsid() or croak "Can't detach from controlling terminal";
	
	$self->d->pid->relock() if $self->d->pid; # Relock after forks
	$pkg->redirect_output($self);
	close $cmd;
=for rem
	$pkg->chroot($self);
	$pkg->change_user($self);
=cut
	$self->log->notice("Daemonized! $$");
	return;
}

sub redirect_output {
	my $pkg = shift;
	my $self = shift;
	return unless $self->d->detach;
	# Keep fileno of std* correct.
	#$self->log->notice("std* fileno = %d, %d, %d", (fileno STDIN, fileno STDOUT, fileno STDERR));
	close STDIN; open STDIN, '<', '/dev/null' or die "open STDIN < /dev/null failed: $!";
	close STDOUT; open STDOUT, '>', '/dev/null' or die "open STDOUT > /dev/null failed: $!";
	close STDERR; open STDERR, '>', '/dev/null' or die "open STDERR > /dev/null failed: $!";
	if ($self->d->verbose > 0) {
		tie *STDERR, 'Daemond::Handle', sub { $self->log->warning($_[0]) };
	}
	if ( $self->d->verbose > 1 ) {
		tie *STDOUT, 'Daemond::Handle', sub { $self->log->notice($_[0]) };
	}
	#$self->log->notice("std* fileno = %d, %d, %d", fileno STDIN, fileno STDOUT, fileno STDERR);
	$self->log->warn( "Logging initialized" );
	return;
}

sub change_user {
	my $pkg = shift;
	my $self = shift;
	$self->d->user or $self->d->group or return;
	my @chown;
	my ($uid,$gid);
	warn "before change user we have UID=$UID{$<}($<), GID=$GID{$(}($(); EUID=$UID{$>}($>), EGID=$GID{$)}($))\n";
	if(defined( local $_ = $self->{user} )) {
		defined( $uid = (getpwnam $_)[2] || (getpwuid $_)[2] )
			or croak "Can't switch to user $_: No such user";
	}
	if(defined( local $_ = $self->{group} )) {
		defined( $uid = (getgrnam $_)[2] || (getgrgid $_)[2] )
			or croak "Can't switch to group $_: No such group";
	}
	if ($> == 0) {
		#warn "I'm root, I can do anything";
		# First, chown files. Later we'll couldn't do this
		for (qw( pid log )) {
			my $handle = $self->{$_.'handle'};
			local $_ = $self->{$_.'file'};
			next unless -e $_;
			my ($u,$g) = (stat)[4,5];
			#warn "my file $_ have uid=$UID{$u}($u), gid=$GID{$g}($g)";
			#local $!;
			chown $uid || -1,$gid || -1, $handle || $_ or croak "chown $_ to uid=$UID{$uid}($uid), gid=$GID{$gid}($gid) failed: $!";
			#($u,$g) = (stat)[4,5];
			#warn "now my file $_ have uid=$UID{$u}($u), gid=$GID{$g}($g)";
		}

		local $!;
		$> = $uid if defined $uid;
		croak "Change uid failed: $!" if $!;
		$) = $gid if defined $gid;
		croak "Change gid failed: $!" if $!;
	}
	else {
		croak "Can't change uid or gid by user $UID{$>}($>). Need root";
	}
	warn "after change user we have UID=$UID{$<}($<), GID=$GID{$(}($(); EUID=$UID{$>}($>), EGID=$GID{$)}($))\n";
	return
}

sub chroot {
	#TODO
}

1;
