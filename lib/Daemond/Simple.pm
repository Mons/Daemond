package Daemond::Simple;

use strict;
use warnings;
use Carp;

=head1 SYNOPSIS

    # daemon.pl:
    use Daemond::Simple
        -class => 'Simple::Package',       # package that implements new, start, run, stop
        -cli   => 1,                       # the default
        -name  => 'my-daemon',             # by default will be 'simple.package';
        -pid   => '/var/run/%n.%u.pid',    # will be /var/run/my-daemon.user.pid
        # -log => ... # TODO
    ;

    # usage:
    $ daemon.pl start
    $ daemon.pl restart
    $ daemon.pl stop
    # ...

=cut

sub import {
    shift;
    my %args = @_;
    warn "@_";
}

1;
