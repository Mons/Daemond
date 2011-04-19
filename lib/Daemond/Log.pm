package Daemond::Log::Object;

use uni::perl;
use Log::Any ();

sub new {
	my $self = bless {}, shift;
	$self->{log} = shift;
	$self->{caller} = 1;
	$self;
}

sub is_null {
	my $self = shift;
	my $logger = Log::Any->get_logger( category => scalar caller() );
	return ref $logger eq 'Log::Any::Adapter::Null' ? 1 : 0;
}

our %METHOD = map { $_ => 1 } Log::Any->logging_methods(),Log::Any->logging_aliases;
sub prefix {
	my $self = shift;
	$self->{prefix} = shift;
}

our $AUTOLOAD;
sub  AUTOLOAD {
	my $self = $_[0];
	my ($name) = $AUTOLOAD =~ m{::([^:]+)$};
	no strict 'refs';
	if ( exists $METHOD{$name} ) {
		my $can = $self->{log}->can($name);
		*$AUTOLOAD = sub {
			my $self = $_[0];
			my ($file,$line) = (caller)[1,2];
			@_ = ($self->{log}, $self->{prefix}.$_[1].($self->{caller} ? " [$file:$line]" : ''), @_ > 2 ? (@_[2..$#_]) : ());
			goto &$can;
		};
		goto &$AUTOLOAD;
	} else {
		if( my $can = $self->{log}->can($name) ) {
			*$AUTOLOAD = sub { splice(@_,0,1,$_[0]->{log}); goto &$can; };
			goto &$AUTOLOAD;
		} else {
			croak "No such method $name on ".ref $self;
		}
	}
}

#=cut

sub DESTROY {}

package Daemond::Log;

use uni::perl;
use Log::Any 0.12 '$log';

sub import {
	shift;
	@_ or return;
	my $caller = caller;
	no strict 'refs';
	my $logger = Log::Any->get_logger(category => 'Daemond');
	my $wrapper = Daemond::Log::Object->new( $logger );
	*{ $caller.'::log' } = \$wrapper;
}

package Daemond::LogAnyAdapterScreen;
BEGIN { $INC{'Daemond/LogAnyAdapterScreen.pm'} = __FILE__; }

use uni::perl;
use parent qw(Log::Any::Adapter::Core);

sub new { bless {@_},shift }

{
	no strict 'refs';
	for my $method ( Log::Any->logging_methods() ) {
		#warn "Create method $method";
		*$method = sub {
			shift;
			my $msg = shift;
			if (@_ and index($msg,'%') > -1) {
				$msg = sprintf $msg, @_;
			}
			$msg =~ s{\n*$}{\n};
			print STDOUT "[\U$method\E] ".$msg;
		};
	}
	my %aliases  = Log::Any->log_level_aliases;
	for my $method ( keys %aliases ) {
		#warn "Create alias $method for $aliases{$method}";
		#*$method = \&{ $aliases{ $method } };
	}
	for my $method ( Log::Any->detection_methods() ) {
		no strict 'refs';
		*$method = sub () { 1 };
	}
}


1;
