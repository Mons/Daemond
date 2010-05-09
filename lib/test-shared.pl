#!/usr/bin/env perl -w
use lib::abs '../lib';
require 'log.pl';

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

