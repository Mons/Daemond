package Daemond::Lab;

use Mouse;
use Mouse::Role ();

# our $INSTCLS = __PACKAGE__;
our @EXTENSIONS;

sub import {
	my $self = shift;
	my $clr = caller;
	if (@_) {
		if ($_[0] eq '-base') {
			warn "call to base $self from $clr\n";
			{
				no strict 'refs';
				push @{ $clr.'::ISA' }, __PACKAGE__;
			}
		}
		elsif ($_[0] eq '-ext') {
			warn "call to ext $self from $clr\n";
			Mouse::Meta::Role->initialize($clr);
			# push @EXTENSIONS, $clr;
			# Mouse::Role->import( 'Mouse::Role',$clr );
			Mouse::Util::apply_all_roles( $self, $clr );
		}
		else {
			die "Unknown use options [@_]";
		}
	}
	# else {
	# 	warn "merge $clr as role to $self";
	# }
}

sub BUILD {
	my $self = shift;
	warn "building $self + @EXTENSIONS";
}

1;