package Daemond::Base;

use uni::perl ':dumper';
use accessors::fast (
	# 'ipc',    # ipc. TODO
	'proc',   # $0 proc operator
	'score',  # scoreboard
	'_',      # state var
);
# _ - 
# TODO: ipc

use Daemond::Log '$log';
sub log:method { $log }

use Daemond::Proc;
use Daemond::D;

BEGIN {
	*usleep = sub (;$) { select undef,undef,undef,$_[0] || 0.2 };
}

sub is_child  { 0 }
sub is_parent { 0 }

sub init {
	my $self = shift;
	$self->next::method(@_);
	my $args = shift;
	$self->d->name or croak "I need daemon name";
	$self->d->proc->name($self->d->name);
	$self->{proc} ||= Daemond::Proc->new();
	#$self->init_sig_die;
	#$self->init_sig_handlers;
	$self->score( Daemond::Scoreboard->new() ) unless $self->score;
	return;
}

sub init_sig_die {
	my $self = shift;
	my $oldsigdie = $SIG{__DIE__};
	my $oldsigwrn = $SIG{__WARN__};
	if (defined $oldsigdie and UNIVERSAL::isa($oldsigdie, 'Daemond::SIGNAL')) {
		undef $oldsigdie;
	}
	$SIG{__DIE__} = sub {
		CORE::die shift,@_ if $^S;
		CORE::die shift,@_ if $_[0] =~ m{ at \(eval \d+\) line \d+.\s*$};
		$self->{_}{shutdown} = $self->{_}{die} = 1;
		my $trace = '';
		my $i = 0;
		while (my @c = caller($i++)) {
			$trace .= "\t$c[3] at $c[1] line $c[2].\n";
		}
		my $msg = "@_";
		if ( $self->log->is_null ) {
			print STDERR $msg;
		} else {
			$self->log->critical("$$: pp=%s, DIE: %s\n\t%s",getppid(),$msg,$trace);
		}
		goto &$oldsigdie if defined $oldsigdie;
		$self->d->exit( 255 );
	};
	bless ($SIG{__DIE__}, 'Daemond::SIGNAL');
	if (defined $oldsigwrn and UNIVERSAL::isa($oldsigwrn, 'Daemond::SIGNAL')) {
		undef $oldsigwrn;
	}
	$SIG{__WARN__} = sub {
		if ($self and !$self->log->is_null) {
			local $_ = "@_";
			s{\n+$}{};
			$self->log->warning($_);
		}
		elsif (defined $oldsigwrn) {
			goto &$oldsigwrn;
		}
		else {
			CORE::warn("$$: @_");
		}
	};
	bless ($SIG{__WARN__}, 'Daemond::SIGNAL');
	return;
}

sub init_sig_handlers {
	my $self = shift;
	# Setup SIG listeners
	# ???: keys %SIG ?
	my $for = $$;
	my $mysig = 'Daemond::SIGNAL';
	#for my $sig ( qw(TERM INT HUP USR1 USR2 CHLD) ) {
	for my $sig ( $self->d->signals ) {
		my $old = $SIG{$sig};
		if (defined $old and UNIVERSAL::isa($old, $mysig) or !ref $old) {
			undef $old;
		}
		$SIG{$sig} = sub {
			eval {
				if ($self) {
					$self->sig(@_);
				}
			};
			warn "Got error in SIG$sig: $@" if $@;
			goto &$old if defined $old;
		};
		bless $SIG{$sig}, $mysig;
	}
}

sub diag {
	my $self = shift;
	my $fm = shift;
	$fm =~ s{\n$}{};
	$self->log->debug($fm,@_);
	return 1;
}

sub warn : method {
	my $self = shift;
	my $fm = shift;
	$fm =~ s{\n$}{};
	$self->log->warn($fm,@_);
	return;
}

# Proc methods

sub state {
	my $self = shift;
	return '*' unless $self->is_child;
	$self->log->warn("No scoreboard @{[(caller(1))[1,2]]}"),return '?' unless $self->score;
	#$self->log->debug("set state to @_") if @_;
	my $r = $self->score->state(@_);
	$self->d->proc->state(@_) if @_; # If state changed, update proc;
	$r;
}

sub sig {
	my $self = shift;
	my $sig = shift;
	if( my $sigh = $self->can('SIG'.$sig)) {
		@_ = ($self);
		goto &$sigh;
	}
	$self->log->debug("Got sig $sig, terminating");
	$self->d->exit(255);
}

sub create_session {
	my $self = shift;
	# Setup some features
	
	$self->{_}{stats} = {
		start => time,
		req   => 0,
	};
	
	# $self->ipc( Daemond::IPC->new() ) unless $self->ipc;
}

sub run {
	confess "Redefine run in subclass";
}

sub ipc_message {
	my $self = shift;
	croak "Not implemented";
}

sub shutdown {
	my $self = shift;
	$self->d->proc->action('shutting down');
	$self->{_}{shutdown} = 1 ;                    # prevent race conditions
	return;
}

1;

