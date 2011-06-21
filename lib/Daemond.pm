package Daemond;

use strict;
use warnings;
use uni::perl ':dumper';
use Daemond::D;

=head1 NAME

Daemond - Daemonization Toolkit

=cut

our $VERSION = '0.03';

=head1 RATIONALE

There is a lot of daemonization utilities.
Some of them have correct daemonization, some have command-line interface, some have good pid locking.
But there is no implementation, that include all the things.

=head1 FEATURES

=over 4

=item * Correct daemonization

Detach, redirection of output, keeping the fileno for STD* handles, chroot, change user

=item * Pluggable engine

You can enable/disable features. Want CLI? Use CLI. Want pid? Use pid.
All is from the box, all is overridable and almost nothing is required for operation

=item * CLI (Command-line interface)

You can control your daemon with well-known commands: start, stop, restart

=item * Pidfile

Good tested pidfile implementation.

=item * Scoreboard

Use mmap'ed scoreboard

=item * Different packages for child processed and parent process

=item * Child monitoring for parent death.

=item * Timers for termination.

Child should exit within a given timeout (not handled for long-running XS subs, like DBI call)

=back

=head1 SYNOPSIS

=head2 The simpliest daemon

    package Test::Daemon;
    use strict;
    use Daemond -parent;

    name 'simple-test';  # Define a name for a daemon
    cli;                 # Use command-line interface
    proc;                # Use proc statuses ($0)
    children 2;          # How many children to fork
    child {
        my $self = shift;
        warn "Starting child | $self";
        # You may override $SIG{USR2} here to interrupt operation and leave this sub
        my $stop = 0;$SIG{USR2} = sub { $stop = 1 };
        while (!$stop) {
            $self->log->debug("code run!");
            $self->state('W'); # Set proc state W (Working)
            sleep 1;
            $self->state('_'); # Set proc state _ (Idle)
            sleep 1;
        }
    };

    package main;

    Test::Daemon->new({
        pid      => '/tmp/daemond.simple-test.pid',
    })->run;

=head2 Daemon with child subclass

    package Test::Daemon;
    use strict;
    use Daemond -parent;

    name 'child-test';  # Define a name for a daemon
    cli;                 # Use command-line interface
    proc;                # Use proc statuses ($0)
    children 2;          # How many children to fork
    
    package Test::Child;
    use strict;
    use Daemond -child => 'Test::Daemon'; # Define a child process for parent process Test::Daemon
    use Time::HiRes qw(sleep);
    
    sub start {
        my $self = shift;
        warn "I'm starting";
    }
    
    sub run {
        my $self = shift;
        while (!$self->{_}{shutdown}) {
            $self->log->debug("code run!");
            $self->state('W'); # Set proc state W (Working)
            sleep 0.1;
            $self->state('_'); # Set proc state _ (Idle)
            sleep 0.1;
        }
        $self->log->debug("Correctly leaving loop");
    }
    
    package main;

    Test::Daemon->new({
        pid      => '/tmp/daemond.simple-test.pid',
    })->run;

=head2 Daemon with AnyEvent child

    package Test::Daemon;
    use strict;
    use Daemond -parent;

    name 'child-test';  # Define a name for a daemon
    cli;                 # Use command-line interface
    proc;                # Use proc statuses ($0)
    children 1;          # How many children to fork
    
    package Test::Child;
    use strict;
    use Daemond -child => 'Test::Daemon'; # Define a child process for parent process Test::Daemon
    use accessors::fast qw(cv timer);
    use Time::HiRes qw(sleep);
    use AE;
    
    sub start {
        my $self = shift;
        $self->{cv} = AE::cv;
        warn "I'm starting";
    }
    
    sub run {
        my $self = shift;
        $self->{timer} = AE::timer 0,0.3,sub {
            $self->log->debug("code run!");
        };
        $self->{cv}->recv;
        $self->log->debug("Correctly leaving loop");
    }
    
    sub stop_flag {
        my $self = shift;
        $self->{cv}->send;
    }
    
    package main;

    Test::Daemon->new({
        pid      => '/tmp/daemond.simple-test.pid',
    })->run;

=head2 Daemon with AnyEvent children and shared socket

    package Test::Daemon;
    use strict;
    use Daemond -parent;
    use accessors::fast qw(socket backlog);

    name 'socket-test';  # Define a name for a daemon
    cli;                 # Use command-line interface
    proc;                # Use proc statuses ($0)
    children 1;          # How many children to fork

    use Carp ();
    use Errno ();
    use Socket qw(AF_INET AF_UNIX SOCK_STREAM SOCK_DGRAM SOL_SOCKET SO_REUSEADDR);

    use AnyEvent ();
    use AnyEvent::Util qw(fh_nonblocking AF_INET6);
    use AnyEvent::Socket ();

    sub start {
        my $self = shift;
        $self->next::method(@_);
        $self->{backlog} ||= 1024;
        my ($host,$service) = ($self->d->host, $self->d->port);
        # <Derived from AnyEvent::Socket>
        $host = $AnyEvent::PROTOCOL{ipv4} < $AnyEvent::PROTOCOL{ipv6} && AF_INET6 ? "::" : "0"
            unless defined $host;

        my $ipn = AnyEvent::Socket::parse_address( $host )
            or Carp::croak "cannot parse '$host' as host address";

        my $af = AnyEvent::Socket::address_family( $ipn );

        Carp::croak "tcp_server/socket: address family not supported"
            if AnyEvent::WIN32 && $af == AF_UNIX;

        CORE::socket my $fh, $af, SOCK_STREAM, 0 or Carp::croak "socket: $!";
        if ($af == AF_INET || $af == AF_INET6) {
            setsockopt $fh, SOL_SOCKET, SO_REUSEADDR, 1 or Carp::croak "so_reuseaddr: $!"
                unless AnyEvent::WIN32; # work around windows bug

            $service = (getservbyname $service, "tcp")[2] or Carp::croak "$service: service unknown"
                unless $service =~ /^\d*$/
        }
        elsif ($af == AF_UNIX) {
            unlink $service;
        }

        bind $fh, AnyEvent::Socket::pack_sockaddr( $service, $ipn ) or Carp::croak "bind: $!";

        fh_nonblocking $fh, 1;
        
        {
            my ($service, $host) = AnyEvent::Socket::unpack_sockaddr( getsockname $fh );
            $host = AnyEvent::Socket::format_address($host);
            warn "Bind to $host:$service";
        }
        
        listen $fh, $self->{backlog} or Carp::croak "listen: $!";
        # </Derived from AnyEvent::Socket>
        $self->{socket} = $fh;
    }
    
    package Test::Child;
    use strict;
    use Daemond -child => 'Test::Daemon'; # Define a child process for parent process Test::Daemon
    use accessors::fast qw(cv socket aw client);
    use Time::HiRes qw(sleep);
    use AnyEvent;
    use AnyEvent::Handle;
    
    sub start {
        my $self = shift;
        $self->{cv} = AE::cv;
        $self->{client} = {};
        warn "I'm starting";
    }
    
    sub run {
        my $self = shift;
        # <Derived from AnyEvent::Socket>
        $self->{aw} = AE::io $self->{socket}, 0, sub {
            while ($self->{socket} && (my $peer = accept my $fh, $self->{socket})) {
                my ($service, $host) = AnyEvent::Socket::unpack_sockaddr($peer);
                $self->accept($fh, AnyEvent::Socket::format_address($host), $service);
            }
        };
        # </Derived from AnyEvent::Socket>
        $self->{cv}->recv;
        $self->log->debug("Correctly leaving loop");
    }
    
    sub accept : method {
        my ($self,$fh,$host,$port) = @_;
        my $c = AnyEvent::Handle->new(fh => $fh);
        my $id = int $c;
        warn "Client $id ($host:$port) connected (".fileno($fh).")";
        $self->{client}{$id} = $c; # Keep connection in stash
        my $reader;
        my $end;$end = sub {
            warn "Client $id gone";
            undef $end; undef $reader; undef $c; # Cleanup
            delete $self->{client}{$id};
        };
        $c->on_error($end);$c->on_eof($end);
        $reader = sub {
            # Read line
            $c->push_read(line => sub {
                my $h = shift;
                return $end->() if $_[0] =~ /^\s*(?:quit|close)\s*$/i;
                # Respond
                $h->push_write("@_");
                $reader->();
            });
        };
        $reader->();
    }
    
    sub stop_flag {
        my $self = shift;
        delete $self->{aw};
        %{$self->{client}} = ();
        $self->{cv}->send;
    }
    
    package main;

    Test::Daemon->new({
        port     => 7777,
        pid      => '/tmp/daemond.socket-test.pid',
    })->run;

=cut

our %CONF;
our %REGISTRY;
sub parent_class { 'Daemond::Parent' }
sub child_class { 'Daemond::Child' }
sub childcode_class { 'Daemond::ChildCode' }

sub import {
	my $pkg = shift;
	my $clr = caller;
	my @args = @_ or return;
	my %opts;
	my $i = 0;
	while ($i < @args) {
		local $_ = $args[$i];
		if ($_ eq '-exec' ) {
			(undef,my $child) = splice @args, $i,2;
			# Here we was exec'ed with child module.
			# We should use $child, new() it, restore scoreboard and run
			die "TODO";
		}
		if ($_ eq '-parent') {
			$opts{parent} = 1;
			splice @args, $i,1;
		}
		elsif ($_ eq '-child') {
			warn "Setup child [@args] $opts{parent} ".dumper [ keys %REGISTRY ];
			if (!@args or substr($args[0],0,1) eq '-') {
				if ( keys %REGISTRY == 1 ){ 
					($opts{child}) = keys %REGISTRY;
					shift @args;
				} else {
					die "Can't define for which parent this `$clr' is child for. Define as -child => 'Parent::Class'\n";
				}
			} else {
				(undef,$opts{child}) = splice @args, $i,2;
			}
			warn "use $clr as child for $opts{child}";
		}
		elsif ($_ eq '-base') {
			(undef,$opts{base}) = splice @args, $i,2;
		}
		else {
			++$i;
		}
	}
	my $clr = caller;
	no strict 'refs';
	if ($opts{parent}) {
		$opts{base} ||= $pkg->parent_class;
		eval qq{use $opts{base}; 1} or die "$@";
		push @{ $clr.'::ISA' }, $opts{base};
		$REGISTRY{ $clr } = d();
		*{ $clr .'::child' } = sub (&) {
			my $code = shift;
			my $childcode_class = $pkg->childcode_class;
			eval "require $childcode_class;1" or die $@;
			require Daemond::ChildCode;
			$childcode_class->set_code($code);
			#$Daemond::ChildCode::CODE = $code;
			#*{ 'Daemond::ChildCode::d' } = sub () { $d };
			d->child_class($childcode_class);
			delete ${$clr.'::'}{child}{CODE};
			return;
		};
		for (qw(name children verbose cli proc signals pid)) {
			*{ $clr .'::'.$_ }  = $pkg->_import_conf_gen($_);
		}
	}
	elsif (exists $opts{child}) {
		$opts{base} ||= $pkg->child_class;
		eval qq{use $opts{base}; 1} or die "$@";
		push @{ $clr.'::ISA' }, $opts{base} unless UNIVERSAL::isa( $clr, $opts{base} );
		if ($opts{child}) {
			if (exists $REGISTRY{ $opts{child} }) {
				my $d = $REGISTRY{ $opts{child} };
				if (defined $d->child_class) {
					croak "`$opts{child}' already have defined child ".$d->child_class;
				} else {
					$d->child_class($clr);
					#*{ $clr .'::d' } = sub () { $d };
				}
			} else {
				croak "There is no class `$opts{child}' defined as Daemond -parent";
			}
		} else {
			#?
		}
	}
	else {
		croak "Neither child not parent";
	}
}

sub _import_conf_gen {
	my $self = shift;
	my $name = shift;
	return sub {
		my $pkg = caller;
		if ( exists $REGISTRY{ $pkg }) {
			$REGISTRY{$pkg}->configure($name => shift);
			{
				no strict 'refs';
				delete ${$pkg.'::'}{$name}{CODE};
			}
		} else {
			croak "Not a Daemond: $pkg for method $name";
		}
		return;
	}
}

=head1 AUTHOR

Mons Anderson, C<< <mons at cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Mons Anderson, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Daemond
