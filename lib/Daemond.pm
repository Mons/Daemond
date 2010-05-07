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

Quick summary of what the module does.

Perhaps a little code snippet.

    use Daemond;

    my $foo = Daemond->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

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
			$d->child_class('Daemond::ChildCode');
			delete ${$clr.'::'}{child}{CODE};
			return;
		};
		for (qw(name children verbose cli proc)) {
			*{ $clr .'::'.$_ }  = $pkg->_import_conf_gen($_);
		}
	}
	elsif ($opts{child}) {
		push @{ $clr.'::ISA' }, $opts{base} || 'Daemond::Child';
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
