package Daemond::Helpers;

use Carp;

sub import {
	my $caller = caller;
	*{$caller.'::UID'} = {};
	*{$caller.'::GID'} = {};
	tie %{$caller.'::UID'}, 'Daemond::UID::HASH';
	tie %{$caller.'::GID'}, 'Daemond::GID::HASH';
}

package Daemond::UID::HASH;

sub TIEHASH { bless do{ \(my $o) },shift;}
sub FETCH   { (getpwuid($_[1]))[0] }

package Daemond::GID::HASH;

sub TIEHASH { bless do{ \(my $o) },shift;}
sub FETCH   { (getgrgid($_[1]))[0] }

package Daemond::Tie::Handle;

use strict;
use base 'Tie::Handle';

sub TIEHANDLE {
	my $pkg = shift;
	my $sub = shift;
	bless do{ \($sub) },$pkg;
}
sub FILENO { undef }
sub BINMODE {}
sub READ {}
sub READLINE {}
sub GETC {}
sub CLOSE {}
sub OPEN { shift }
sub EOF {}
sub TELL {0}
sub SEEK {}
sub DESTROY {}

sub PRINT {
	my $self = shift;
	${$self}->( join($,,@_) );
}
sub PRINTF {
	my $self = shift;
	my $format = shift;
	${$self}->( sprintf($format,@_) );
}
sub WRITE {
	my $self = shift;
	my ($scalar,$length,$offset)=@_;
	${$self}->( substr($scalar, $offset,$length) );
	
}

1;
