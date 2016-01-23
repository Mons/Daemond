 #!/usr/bin/env perl

use 5.010;
use strict;
use lib::abs '../lib';#,'../blib/lib','../blib/arch';
use Test::More;
use DDP;
use Scalar::Util 'refaddr';
use Mouse::Util;
use Devel::Refcount 'refcount';


use Daemond::Ctx;

our $DES1;
our $DES2;

{
	package t::Request1;
	use Mouse;

	sub reply {
		my $self = shift;
		return 'reply for Request1';
	}

	sub DEMOLISH {
		# warn "req1 DEMOLISH (@_)";
		$DES1 = 1;
	}
}

{
	package t::Request2;
	# not Mouse;
	sub new {
		my $pkg = shift;
		return bless {@_}, $pkg;
	}

	sub reply {
		my $self = shift;
		return 'reply for Request2';
	}

	sub overmethod {
		'original';
	}

	sub DESTROY {
		# warn "req2 DESTROY (@_)";
		$DES2 = 1;
	}
}



# diag explain \%::t::;

{
	package t::App::Ctx1;

	use Daemond::Ctx -for => qw(t::Request1 t::Request2);

	use Mouse;

	has 'zzz', is =>'rw';

	# use Daemond::Ctx -for => qw(t::Request1);
	# use Mouse::Role;
	# BEGIN {
	# 	my $meta = Mouse::Meta::Role->initialize( __PACKAGE__ );
	# 	__PACKAGE__->Mouse::Role::init_meta( for_class => __PACKAGE__ );
	# }

	# BEGIN {
	# 	my $meta = Mouse::Meta::Class->initialize('t::App::Ctx1::t_Request1');
	# 	$meta->superclasses( 't::Request1' );
		
	# }
	# CHECK {
	# 	Mouse::Util::apply_all_roles( 't::App::Ctx1::t_Request1', __PACKAGE__ );
	# }

	# {
	# 	package t::App::Ctx1::t_Request1;
	# 	use Mouse;
	# 	extends 't::Request1';
	# 	with 't::App::Ctx1';
	# }


	sub ctxmethod {
		my $self = shift;
		return ref($self)." ctxmethod";
	}

	sub overmethod {
		'overriden';
	}

	# use Daemond::Ctx -for => qw(t::Request1 t::Request2);
}

my $req1 = t::Request1->new();
my $req2 = t::Request2->new();


is refcount($req1), 1, 'req1 refcount = 1'; 
is refcount($req2), 1, 'req2 refcount = 1'; 
# p $req1;
my $addr1 = refaddr $req1;
my $addr2 = refaddr $req2;

my $ctx1 = Daemond::Ctx->ctx($req1);
my $ctx2 = Daemond::Ctx->ctx($req2);

undef $req1;
undef $req2;

use Devel::FindRef;
is refcount($ctx1), 1, 'ctx1 refcount = 1'; 
is refcount($ctx2), 1, 'ctx2 refcount = 1'; 
# say Devel::FindRef::track $ctx1;

is refaddr($ctx1), $addr1, 'ctx1 is the same object';
is refaddr($ctx2), $addr2, 'ctx2 is the same object';

is ref($ctx1), 't::App::Ctx1::t_Request1', 'intermediate object 1';
is ref($ctx2), 't::App::Ctx1::t_Request2', 'intermediate object 2';

# p $ctx1;

is $ctx1->ctxmethod(), 't::App::Ctx1::t_Request1 ctxmethod', 'ctx method callable 1';
is $ctx2->ctxmethod(), 't::App::Ctx1::t_Request2 ctxmethod', 'ctx method callable 2';
is $ctx1->ctxmethod(), 't::App::Ctx1::t_Request1 ctxmethod', 'ctx method callable 1';
is $ctx2->ctxmethod(), 't::App::Ctx1::t_Request2 ctxmethod', 'ctx method callable 2';

is $ctx1->overmethod(), 'overriden', 'ctx1 method overriden';
is $ctx2->overmethod(), 'original', 'ctx2 method not overriden';
is $ctx1->overmethod(), 'overriden', 'ctx1 method overriden';
is $ctx2->overmethod(), 'original', 'ctx2 method not overriden';

# 1. DESTROY on orig must be called
is $DES1, undef, 'initial des 1';
is $DES2, undef, 'initial des 2';

is refcount($ctx1), 1, 'ctx1 refcount = 1'; 
is refcount($ctx2), 1, 'ctx2 refcount = 1'; 

undef $ctx1;
undef $ctx2;

is $DES1, 1, 'resulting des 1';
is $DES2, 1, 'resulting des 2';

done_testing();
