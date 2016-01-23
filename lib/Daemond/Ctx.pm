package Daemond::Ctx::_Base;

use Mouse;

has 'id', is => 'ro', default => '1234';

sub DEMOLISH {
	# warn "DEMOLISH context @_";
}

package Daemond::Ctx;

use strict;
use Carp;
use Mouse;
use Mouse::Role ();
use Scalar::Util 'refaddr';

our %MAP;
our @ROLEMAPS;
our %OUT;
our %SRC;

CHECK {
	for (@ROLEMAPS) {
		Mouse::Util::apply_all_roles( @$_ );
	}
}

sub is_loaded {
	my $name = shift;
	my $file = join( '/', split('::', $name) ). ".pm";
	return 1 if $INC{$file};
	my $tbl = \%::;
	for my $part ( split('::', $name) ) {
		return 0 unless exists $tbl->{ $part.'::' };
		$tbl = $tbl->{ $part.'::' };
	}
	# warn "found symtable: $tbl for $name";
	return 1;
}



sub prx_autoload {
	our $AUTOLOAD;

	my $self = $_[0];
	# warn "auto $AUTOLOAD on $self";
	my $pkg = ref $self;
	my $ref = refaddr($self);
	my $ctx = $OUT{$ref} or croak "No ctx";
	my ($method) = $AUTOLOAD =~ /([^:]+)$/;


	if (my $meth = $SRC{$pkg}->can($method)) {
		# warn "$self: orig have $method $meth";
		{
			no strict 'refs';
			*{ $pkg.'::'. $method } = $meth;
		}
		goto &$meth;
	}
	if (my $meth = $ctx->can($method)) {
		# my $isa = Mouse::Util::get_linear_isa( $pkg );
		# shift $isa while @$isa and $isa->[0] ne ref $self;
		# warn "next: $isa->[0]";
		# Mouse::Util::get_code_ref($class, 'DEMOLISH')
		if (exists $ctx->meta->{attributes}{ $method }) {
			# warn "attribute: $method";
			{
				no strict 'refs';
				*{ $pkg.'::'. $method } = sub {
					# splice(@_, 0,1, $OUT{refaddr $_[0]});
					# goto &$meth;
					$OUT{refaddr shift}->$method(@_);
				};
			}
			splice(@_, 0,1, $ctx);
			goto &$meth;
		} else {
			# warn "not an attribute: $method";
			# if (eval { $ctx->meta })
			{
				no strict 'refs';
				*{ $pkg.'::'. $method } = $meth;
			}
			goto &$meth;
		}
	}
	else {
		croak qq{Can't locate object method "$method" via package "$pkg"};
	}
}

sub prx_destroy {
	my $base = shift;
	my $desname = shift;
	return sub {
		# warn "prx des";
		my $self = shift;
		my $ref = refaddr($self);
		# warn "des on prx $self";
		my $ctx = $OUT{$ref} or croak "No ctx";
		# warn "des on ctx $ctx";
		my $prxdes = $base->can('DESTROY');
		# warn "call DESTROY $prxdes on $self";
			# use DDP;
			# p Mouse::Util::get_linear_isa(ref $self);
		eval { $self->$prxdes(); 1} or do {
			warn;
		};
		# warn "cleanup";
		bless $self, $desname;
		delete $OUT{$ref};
	};
}

sub des_destroy {}

sub des_autoload {
	our $AUTOLOAD;
	warn "call to destroyed $AUTOLOAD";
	return;
}

sub import {
	my $pkg = shift;
	@_ or return;
	my $caller = caller;
	my $callfile = join( '/', split('::', $caller) ). ".pm";
	if (@_) {
		my @fors;
		ARGS:
		while (@_) {
			my $action = shift;
			if ($action eq '-for') {
				while (@_) {
					if ($_[0] =~ /^-/) {
						next ARGS;
					} else {
						push @fors, shift @_;
					}
				}
			}
			else {
				croak "Unknown action $action";
			}
		}

		@fors or croak "-for requires at least one delegate";

		# 1. Upgrade Ctx to a Mouse class

		my $meta = Mouse::Meta::Class->initialize($caller);
		$meta->superclasses('Daemond::Ctx::_Base');
		# $caller->Mouse::Role::init_meta( for_class => $caller);
		$INC{$callfile} //= (caller)[1];
		# warn "Created Mouse class $caller for context";

		for my $reqclass (@fors) {
			unless( is_loaded($reqclass) ) {
				my $file = join( '/', split('::', $reqclass) ). ".pm";
				eval {require $file;}
					or croak $@;
			}
			# 2. create subclass for proxy request
			my $prxname = $caller.'::'.join("_",split "::",$reqclass);
			my $desname = $prxname.'::DES';
			{
				no strict 'refs';
				# warn "add AUTOLOAD and DESTROY to $prxname";
				*{$prxname.'::AUTOLOAD'} = \&prx_autoload;
				*{$prxname.'::DESTROY'} = prx_destroy($reqclass,$desname);
				@{$prxname.'::ISA'} = ($reqclass);
			}
			$SRC{$prxname} = $reqclass;

			# 3. create subclass for destroyed request
			{
				no strict 'refs';
				*{$desname.'::AUTOLOAD'} = \&des_autoload;
				*{$desname.'::DESTROY'} = \&des_destroy;
				@{$desname.'::ISA'} = ($prxname);
			}

			# my $pkgname = $caller.'::'.join("_",split "::",$reqclass);
			# {
			# 	no strict 'refs';
			# 	# warn "\tinitialize $pkgname as mouse class with parent $reqclass";
			# 	my $meta = Mouse::Meta::Class->initialize($pkgname);
			# 	# $pkgname->init_meta();
			# 	use DDP;
			# 	# p $meta;

			# 	$meta->superclasses($reqclass);

			# 	# p $pkgname->meta;
			# 	#push @{ $pkgname . '::ISA' }, $reqclass;

			# 	my $fn = join( '/', split('::', $reqclass) ). ".pm";
			# 	$INC{$fn} = (caller)[1];
			# }
			# # warn "\tsubclass = $pkgname";

			# if (my $meta = eval { $reqclass->meta }) {
			# 	# warn "meta: $meta";
			# }
			# else {
			# 	warn $@;
			# }
			# push @ROLEMAPS, [$pkgname, $caller];
			# Mouse::Util::apply_all_roles( $pkgname, 'Daemond::Ctx::_Base', $caller );
			# # warn "result: $pkgname with role $caller for $reqclass";

			$MAP{ $reqclass } and croak "$reqclass already registered for $MAP{ $reqclass }";
			$MAP{ $reqclass } = [$prxname, $caller];
		}
	}
}


sub ctx {
	shift;
	my $object = shift;
	my $class = ref $object or croak "Context expects object, but got '$object'";
	exists $MAP{ $class } or croak "Class '$class' not registered in context";
	# warn "convert $class into @{ $MAP{ $class } }";

	my ($prx, $ctx) = @{ $MAP{ $class } };

	$OUT{ refaddr($object) } = $ctx->new();
	return bless $object, $prx;
}

1;