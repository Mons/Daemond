#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Daemond' );
}

diag( "Testing Daemond $Daemond::VERSION, Perl $], $^X" );
