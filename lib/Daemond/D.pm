package Daemond::D;

use uni::perl ':dumper';
use Daemond::Void;

our $D;
sub import {
	my $pk = shift;
	$D ||= $pk->new( cmd => "$0" );
	$D->configure(@_);
	no strict 'refs';
	*{ caller().'::d' } = sub () { $D };
	return;
}

our %COLOR = (
	'/'        => 0,
    clear      => 0,
    reset      => 0,
    b          => 1,
    bold       => 1,
    dark       => 2,
    faint      => 2,
    underline  => 4,
    underscore => 4,
    blink      => 5,
    reverse    => 7,
    concealed  => 8,

    black      => 30,   on_black   => 40,
    red        => 31,   on_red     => 41, r => 31,
    green      => 32,   on_green   => 42, g => 32,
    yellow     => 33,   on_yellow  => 43, y => 33,
    blue       => 34,   on_blue    => 44, n => 34, # navy
    magenta    => 35,   on_magenta => 45,
    cyan       => 36,   on_cyan    => 46,
    white      => 37,   on_white   => 47, w => 37,
);
our $COLOR = join '|',keys %COLOR;
our $LASTSAY = 1;
sub say:method {
	my $self = shift;
	my $color = -t STDOUT;
	my $msg = ($LASTSAY ? '' : "\n")."<green>".$self->name."</> - ".shift;
	$LASTSAY = 1;
	for ($msg) {
		if ($color) {
			s{<($COLOR)>}{ "\033[$COLOR{$1}m" }sge;
		} else {
			s{<(?:$COLOR)>}{}sgo;
		}
		unless (s{\0$}{\033[0m}) {
			s{(?:\n|)$}{\033[0m\n};
		} else {
			$LASTSAY = 0;
		}
	}
	if (@_ and index($msg,'%') > -1) {
		$msg = sprintf $msg, @_;
	}
	print STDOUT $msg;
}

sub sayn {
	my $self = shift;
	my $color = -t STDOUT;
	my $msg = shift;
	$LASTSAY = 0;
	for ($msg) {
		if ($color) {
			s{<($COLOR)>}{ "\033[$COLOR{$1}m" }sge;
		} else {
			s{<(?:$COLOR)>}{}sgo;
		}
		if(s{\n$}{}) {
			$LASTSAY = 1;
		}
	}
	$msg .= "\033[0m\n" if $LASTSAY;
	if (@_ and index($msg,'%') > -1) {
		$msg = sprintf $msg, @_;
	}
	print STDOUT $msg;
}

sub warn:method {
	my $self = shift;
	my $msg = shift;
	$self->say('<r>'.$msg,@_);
}

sub die:method {
	my $self = shift;
	my $msg = shift;
	$self->say('<r>'.$msg,@_);
	$self->destroy;
	no warnings 'internal'; # Aviod 'Attempt to free unreferenced scalar' for nester sighandlers
	exit 255;
}
sub exit:method {
	my $self = shift;
	my $code = shift || 0;
	$self->destroy;
	no warnings 'internal'; # Aviod 'Attempt to free unreferenced scalar' for nester sighandlers
	exit $code;
}

sub new {
	my $pkg = shift;
	my $self = bless {
		verbose       => 0,
		max_die       => 10, # times
		start_timeout => 5,  # seconds
		exit_timeout  => 3,  # seconds
		pid           => Daemond::Void->new(),
		proc          => Daemond::Void->new(),
		cli           => Daemond::Void->new(),
		signals       => [qw(TERM INT HUP USR1 USR2 CHLD PIPE)],
		@_
	}, $pkg;
	return $self;
}

our @SIG;our %SIG_OK;
BEGIN {
	use Config;
	@SIG = split ' ',$Config{sig_name};
	@SIG_OK{@SIG} = ();
}

sub signals {
	my $self = shift;
	if (@_) {
		my %sig;
		@sig{
			qw(TERM INT CHLD), # Always required
			(map { defined $_ ? exists $SIG_OK{uc $_} ? uc $_ : croak "Bad signal: $_" : ()  } @_),
		} = ();
		$self->{signals} = [keys %sig];
	}
	return @{$self->{signals}};
}

sub configure {
	my $self = shift;
	my %args = @_==1 && ref $_[0] ? %{$_[0]} : @_;
	my @DELEGATE;
	if (exists $args{pid} and !ref $args{pid}) {
		require Daemond::Pid;
		my $pid = delete $args{pid};
		$args{pid} = Daemond::Pid->new(file => $pid);
	}
	if (exists $args{pid} and my $cls = ref $args{pid}) {
		#warn "Use pid $args{pid}";
		push @DELEGATE, $args{pid};
	}
	if (exists $args{proc} and !ref $args{proc}) {
		require Daemond::Proc;
		my $proc = Daemond::Proc->new();
		$args{proc} = $proc;
		push @DELEGATE, $proc;
		#???
		#*{ 'Daemond::Proc::d' } = sub () { $self } unless $proc->can('d');
	}
	if (exists $args{cli}) {
		$args{cli} ||= do { require Daemond::Cli;Daemond::Cli->new() };
		#warn "Use cli $args{cli}";
		push @DELEGATE, $args{cli};
	}
	for (@DELEGATE) {
		no strict 'refs';
		my $cls = ref $_;
		*{ $cls.'::d' } = sub () { $self } unless defined &{ $cls.'::d' };
	}
	
	@$self{keys %args} = values %args;
	return;
}

sub cli {
	my $self = shift;
	if (@_) {
		my $cli = shift || do { require Daemond::Cli;Daemond::Cli->new() };
		$self->{cli} = $cli;
		unless ($cli->can('d')){
			no strict 'refs';
			my $pk = ref $cli;
			*{ $pk.'::d' } = sub () { $self };
		}
	}
	return $self->{cli};
}

our $AUTOLOAD;
sub  AUTOLOAD {
	#my $self = shift;
	my ($name) = $AUTOLOAD =~ m{::([^:]+)$};
	no strict 'refs';
	*$AUTOLOAD = sub {
		my $self = shift;
		if (@_) {
			return $self->{$name} = shift;
		}
		if ( exists $self->{$name} ) {
			return $self->{$name}
		}
		return undef;
	};
	goto &$AUTOLOAD;
}

sub destroy {
	my $self = shift;
	%$self = ();
	bless $self,'Daemond::D::destroyed';
}
sub Daemond::D::destroyed::AUTOLOAD {};

1;
