package Daemond::Void;

use overload
	'bool' => sub { 0 },
	fallback => 1;

sub new { bless \do {my $o},shift };
sub AUTOLOAD {}

1;
