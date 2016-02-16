package Daemond::Log::Null;

sub new {
	my $pkg = shift;
	my $self = bless {}, $pkg;
	return $self;
}
sub AUTOLOAD {
	our $AUTOLOAD;
	warn $AUTOLOAD;
}
# sub DESTROY {
# }
# sub DEMOLISH {
# }

package Daemond::Log;

use strict;
use Carp;
use Scalar::Util qw(weaken);
use EV;
use Time::HiRes;
use Time::Local;

sub new {
	my $pkg = shift;
	my $self = bless {}, $pkg;
	$self->{default} = Daemond::Log::Logger->new;
	return $self;
}

{
	my $tzgen = int(time()/600)*600;
	my $tzoff = timegm_nocheck( localtime($tzgen) ) - $tzgen;
	#warn "gen at ".localtime()." as for ".localtime($tzgen);
	sub timeset {
		my ($time,$ms) = Time::HiRes::gettimeofday();
		if ($time > $tzgen + 600) {
			$tzgen = int($time/600)*600;
			$tzoff = timegm_nocheck( localtime($tzgen) ) - $tzgen;
		}
		[ [ gmtime($time+$tzoff) ], $ms, EV::now() - $time - $ms/1e6 ];
	}
}


sub LOG_EMERG    () { 0 }
sub LOG_ALERT    () { 1 }
sub LOG_CRIT     () { 2 }
sub LOG_ERR      () { 3 }
sub LOG_WARNING  () { 4 }
sub LOG_NOTICE   () { 5 }
sub LOG_INFO     () { 6 }
sub LOG_DEBUG    () { 7 }

our %METHODS;
BEGIN {
	%METHODS = (
		trace     => [ 'trace',     LOG_DEBUG,   'TRC',  ],
		debug     => [ 'debug',     LOG_DEBUG,   'DBG',  ],
		info      => [ 'info',      LOG_INFO,    'INF',  ],
		notice    => [ 'notice',    LOG_NOTICE,  'NTC',  ],
		warning   => [ 'warning',   LOG_WARNING, 'WRN',  ],
		error     => [ 'error',     LOG_ERR,     'ERR',  ],
		critical  => [ 'critical',  LOG_CRIT,    'CRT',  ],
		alert     => [ 'alert',     LOG_ALERT,   'ALR',  ],
		emergency => [ 'emergency', LOG_EMERG,   'EMR',  ],
	);
	our %ALIAS = (
		warn  => 'warning',
		crit  => 'critical',
		err   => 'error',
		emerg => 'emergency',
	);
	while (my ($met,$prm) = each %METHODS) {
		my ($as, $num, $str) = @$prm;
		my $sub = sub {
			my $self = shift;
			my $msg = @_ ? shift : '""';
			if (@_ and index($msg,'%') > -1) {
				$msg = sprintf $msg, @_;
			}
			$msg =~ s{\n*$}{};

			$self->{default}->$as( $num, $str, $msg);
		};
		{
			no strict 'refs';
			*{$met} = $sub;
		}
	}
	while (my ($met,$as) = each %ALIAS) {
		no strict 'refs';
		*$met = *$as;
	}
}

sub AUTOLOAD {
	our $AUTOLOAD;
	my ($logger) = $AUTOLOAD =~ m{([^:]+)$};
	my $self = shift;
	if (@_) {
		carp "Wrong log method '$logger'";
		return;
	}
	if (not exists $self->{$logger}) {
		carp "Access to nonexistent logger '$logger'";
		weaken($self->{$logger} = $self);
	}
	my $sub = sub {
		return $_[0]{$logger};
	};
	{
		no strict 'refs';
		*{$logger} = $sub;
	}
	return $self->{$logger};

}

sub DESTROY {
	my $self = shift;
	for (values %$self) {
		$_->DEMOLISH;
	}
}

package Daemond::Log::Logger;

use strict;

=for info

Logger keeps several destinations

interface:

$obj->{log method not alias}( $NUM_LVL, $STR_LVL, $message )

=cut

sub new {
	my $pkg = shift;
	my @destinations = @_;
	my $self = bless \@destinations, $pkg;
	return $self;
}

BEGIN {
	while (my ($met,$prm) = each %Daemond::Log::METHODS) {
		my ($as) = @$prm;
		next unless $met eq $as;
		my $sub = sub {
			my $self = shift;
			my $timeset = Daemond::Log::timeset();
			warn "@_";
			for (@$self) {
				$_->$as($timeset,@_);
			}
		};
		{
			no strict 'refs';
			*{$met} = $sub;
		}
	}
}

package Daemond::Log::Dest;

use strict;

=for info

Logger keeps several destinations

interface:

$obj->{log method not alias}( $NUM_LVL, $STR_LVL, \@localtime, $message )


default date format = %Y-%m-%dT%H:%M:%S.%3N

sub logstrftime($format,$hirespart,$evoft ...) {
	if ($hirespart) {
		return strftime($format).".".sprintf($hirespart)
	}
}

$host, $prog, $level, $$, $date, $message

{hostname} {level} {date} {message}
format -> "%1$s %3$s %5$s $6$s"

{hostname} {level} {message}
format -> "%1$s %3$s $5$s"


if ($self->{date_format}) {
	$date = strftime($date_format, @{ \@localtime });
}
sprintf $format, $host, $prog, $level, $$, $date, $message;

=cut



1;
__END__

use Daemond;

# destinations:
#   file   (configured)
#   scribe (configured)
#   syslog (enabled always)
#   screen (always enabled by -f for every action)

config:

logger:
	default:
		syslog:
			facility: local0
			level: warn
			hires: 1
			format: "{hostname} {progname} {pid} {level} {date:%Y-%m-%d} {message}"
		screen:
			level: debug
		file:
			/var/log/%n.log
		scribe:
			host,port
	alt:
		syslog:
			facility: local7
		screen:
			level: debug
			# disable_on_nodetach?

# format?

# logger {
# 	logfile {
# 		name => '/var/log/'.$d->name.'.log';
# 	};
# 	syslog {
# 		facility => '...',
# 		[ ident => '...', ] # default -> daemon name
# 		level => 'warn',
# 	};
# 	syslog{
# 		facility => '...',
# 		[ ident => '...', ] # default -> daemon name
# 		level => 'warn',
# 	}, 'altname';
# 	logscreen {
# 		level => 'debug',		
# 	};
# 	scribe {
# 		...
# 	};
# };

...
sub {
	lab->log->debug(...) # write to every default
	lab->log->alt->debug()
	lab->log( ... ) # => lab->log->crit(...)
	lab->log->nonexistent->debug() # fallback to default + warn
	warn # (by SIG__WARN__ to logwarn or default)
}

---

use Daemond::Log '$log';

$log->configure

$log->debug( 'format', 'args', 'args' );


