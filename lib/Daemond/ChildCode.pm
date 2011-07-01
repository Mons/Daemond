package Daemond::ChildCode;

use uni::perl ':dumper';

our $CODE;

use parent 'Daemond::Child';
#use Daemond -child;

sub set_code {
	shift;
	$CODE = shift;
}

sub stop_flag {
	my $self = shift;
	warn "Stop flag in childcode";
	kill USR2 => $$ or warn "Can't 'kill' myself with USR2: $!";
}

sub run {
	my $self = shift;
	$SIG{USR2} = sub {
		if ($self->{_}{shutdown}) {
			$self->log->alert("USR2: Already shutting down, exit");
			$self->d->exit(255);
		} else {
			warn "Stop by USR2";
			$self->{_}{shutdown} = 1;
			die bless \do{my $o}, 'Daemond::ChildCode::STOPException';
		}
	};
	eval{ 
		$CODE->($self);
	};
	if(my $e = $@) {
		if (ref $e and UNIVERSAL::isa($e, 'Daemond::ChildCode::STOPException')) {
			$self->log->notice("STOP Exception");
		} else {
			die $e;
		}
	}
	$self->shutdown;
};

1;
