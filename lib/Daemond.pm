package Daemond;

use strict;
use warnings;
use uni::perl ':dumper';
use Daemond::D;
use Daemond::Parent;
use Daemond::Child;

=head1 NAME

Daemond - Daemonization Toolkit

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

=head2 The simpliest daemon

    package Test::Daemon;
    use strict;
    use Daemond -parent;

    name 'simple-test';  # Define a name for a daemon
    cli;                 # Use command-line interface
    proc;                # Use proc status ($0)
    children 2;          # How many children to fork
    child {
        my $self = shift;
        warn "Starting child";
        # You may override $SIG{USR2} here to interrupt operation and leave this sub
        my $stop = 0;
        $SIG{USR2} = sub { $stop = 1 };
        my $iter = 0;
        while (!$stop) {
            $self->log->debug("code run!");
            sleep 1;
        }
    };

    package main;

    Test::Daemon->new({
        pid      => '/tmp/daemond.simple-test.pid',
        children => 1,
    })->run;

=head2 Daemon with child subclass



=cut

our %CONF;
our %REGISTRY;

sub import {
	my $pkg = shift;
	my @args = @_ or return;
	my $clr = caller;
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
			(undef,$opts{child}) = splice @args, $i,2;
		}
		elsif ($_ eq '-base') {
			(undef,$opts{base}) = splice @args, $i,2;
		}
		else {
			++$i;
		}
	}
	no strict 'refs';
	if ($opts{parent}) {
		push @{ $clr.'::ISA' }, $opts{base} || 'Daemond::Parent';
		my $d =
			#${ $clr.'::D' } =
			Daemond::D->new(package => $clr, cmd => "$0");
		$REGISTRY{ $clr } = $d;
		*{ $clr .'::d' } = sub () { $d };
		*{ $clr .'::child' } = sub (&) {
			my $code = shift;
			require Daemond::ChildCode;
			$Daemond::ChildCode::CODE = $code;
			*{ 'Daemond::ChildCode::d' } = sub () { $d };
			$d->child_class('Daemond::ChildCode');
			delete ${$clr.'::'}{child}{CODE};
			return;
		};
		for (qw(name children verbose cli proc signals)) {
			*{ $clr .'::'.$_ }  = $pkg->_import_conf_gen($_);
		}
	}
	elsif (exists $opts{child}) {
		push @{ $clr.'::ISA' }, $opts{base} || 'Daemond::Child';
		if ($opts{child}) {
			if (exists $REGISTRY{ $opts{child} }) {
				my $d = $REGISTRY{ $opts{child} };
				if (defined $d->child_class) {
					croak "`$opts{child}' already have defined child ".$d->child_class;
				} else {
					$d->child_class($clr);
					*{ $clr .'::d' } = sub () { $d };
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

use Getopt::Long qw(:config gnu_compat bundling);

sub _getopt {
	my $self = shift;
	my %opts;
	GetOptions(
		"nodetach|f!"  => sub { $opts{detach} = 0 },
		"children|c=i" => sub { shift;$opts{children} = shift },
		"verbose|v+"   => sub { $opts{verbose}++ },
		#"nodebug!" => sub { $ND = 1 },
	); # TODO: catch errors
	return %opts;
}

sub new {
	my $pkg = shift;
	my $self = bless {}, $pkg;
	my %opts = $self->_getopt;
	my %cf = (
		%{ $CONF{$pkg} },
		%{$_[0]},
		%opts,
	);
	warn dumper \%cf;
	return $self;
}

sub run {}


=head1 AUTHOR

Mons Anderson, C<< <mons at cpan.org> >>

=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2010 Mons Anderson, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Daemond
