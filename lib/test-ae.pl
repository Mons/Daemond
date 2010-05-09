#!/usr/bin/env perl -w
use lib::abs '../lib';
require 'log.pl';

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

