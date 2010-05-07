package Daemond::Helpers;

use Carp;

sub import {
	my $caller = caller;
	*{$caller.'::UID'} = {};
	*{$caller.'::GID'} = {};
	tie %{$caller.'::UID'}, 'Daemond::UID::HASH';
	tie %{$caller.'::GID'}, 'Daemond::GID::HASH';
	@_ = ('Daemond::Tie::Caller');
	goto &Daemond::Tie::Caller::import;
}

package Daemond::UID::HASH;

sub TIEHASH { bless do{ \(my $o) },shift;}
sub FETCH   { (getpwuid($_[1]))[0] }

package Daemond::GID::HASH;

sub TIEHASH { bless do{ \(my $o) },shift;}
sub FETCH   { (getgrgid($_[1]))[0] }

package Daemond::Tie::Caller;

=head1 SYNOPSIS

Simple usage of tied scalar or hash for using caller inside double quoted strings.
Main purpose is the debugging and error logging.
Default format is like in warn or die.
Carp is good, but not for strict caller depth

	# Instead of
	my ($file,$line) = (caller(1))[1,2];
	warn "Your message at $file line $line.\n";
	
	# May be used
	warn "Your message at $caller.\n";
	# Or
	warn "Your message at $caller{1}.\n";

=cut

use strict;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

BEGIN {
	defined &DEBUG or *DEBUG = sub () { 0 };
}
tie our $caller, __PACKAGE__;
our $DEFAULT = 'caller';
our $FORMAT;
our %FORMATS = (
	pk => '%1$s' ,
	sub => '%3$s' ,
	warn => '%2$s line %3$s',
	pfl  => '%1$s %2$s %3$s',
);

defined $FORMAT or $FORMAT = $FORMATS{warn}; # Classic die/warn format: "at <file> line <line>" 
#defined $FORMAT or our $FORMAT  = '%1$s'; # Only package name

sub import {
	my $me = shift;
	my $pkg = caller;
	@_ = @_ ? @_ : ($DEFAULT);
	no strict 'refs';
	for (@_) {
		my $ok = 0;
		my $sym = $pkg.'::'.$_;
		
		if (s/^\$// or /^\w/) {
			DEBUG and warn "$me: \$$sym";
			*$sym = \$pkg; # just define the sym
			tie $$sym, $me;
			$ok++;
		}
		if(s/^%// or /^\w/) {
			DEBUG and warn "$me: \%$sym";
			*$sym = {}; # just define the sym
			tie %$sym, $me;
			$ok++;
		}
		
		$ok or die "Wrong argument `$_' for $me $caller";
	}
}

sub _caller {
	my ($i,$add) = ( @_ ? @_ : (1,0) );
	if ($i and $i =~ /^(!?)~(.+)$/) {
		my $not = $1 ? 1 : 0;
		my $ptr = $2;
		$i = 0;
		while(1) {
			local ($_,$a,$b) = caller(++$i);
			defined or $i--,last;
			my $ok = ( /$ptr/ xor $not );
			DEBUG > 1 and warn sprintf "\t$i: $_ ($a $b) (%s %s~ (/$ptr/:%s) => %s)",$_, $not ? '!':'', /$ptr/?1:0, $ok ? 1 : 0;
			$ok and last;
		}
	}else{
		$i += 2
	}
	caller($i+($add||0))
}

sub TIEHASH { bless do{ \(my $o) },shift;}
sub TIESCALAR { bless do{ \(my $o) },shift;}
sub FETCH   {
	shift;
	local $FORMAT = $FORMAT;
	#warn Dumper [$;,@_];
	if (@_ and $_[0] =~ /$;/) {
		my ($format,$i) = split $;,$_[0],2;
		#warn "using format $format";
		if( index($FORMATS{$format} || $format,'%') > -1 ) {
			$FORMAT = $FORMATS{$format} || $format;
			@_ = ($i);
		}else{
			$i = $format.$;.$i;
		}
		my ($ptrn,$add) = split $;,$i,2;
		warn "$ptrn | $add";
		@_ = ($ptrn,$add);
	}
	#warn "format is $FORMAT";
	DEBUG > 1 and warn "fetch caller for @_";
	local @_ = _caller(@_);
	if (@_) {
		return sprintf $FORMAT, @_
	} else { return }
}

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
