package Daemond::ChildCode;

use uni::perl ':dumper';

our $CODE;

use Daemond -child;

sub stop_flag {
	my $self = shift;
	kill USR2 => $$;
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
			die \("STOP");
		}
	};
	eval{ 
		$CODE->($self);
	};
	if(my $e = $@) {
		if (ref $e and $$e eq 'STOP') {
			$self->log->notice("STOP Exception");
		} else {
			die $e;
		}
	}
	$self->shutdown;
};

1;
