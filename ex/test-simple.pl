#!/usr/bin/env perl -w
use lib::abs '../lib';
require 'log.pl';

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

