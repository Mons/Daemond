#!/usr/bin/env perl -w
use lib::abs '../lib';
require 'log.pl';

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

