package Daemond::ChildEV;

use uni::perl ':dumper';
use parent 'Daemond::Child';
use EV;

sub init_sig_handlers {
	my $self = shift;
	$self->Daemond::Child::init_sig_handlers (@_);
	warn "Resetup sig handlers for [@{[ $self->d->signals ]}] ";
	for my $sig ( $self->d->signals ) {
		my $old = $SIG{$sig};
		delete $SIG{$sig};
		if (defined $old) {
			#warn "$sig...";
			my $s;$s = EV::signal $sig => sub {
				splice @_, 0,1,$sig;
				#shift;
				#unshift @_, $sig;
				$s = $s;
				goto &$old;
			};
		}
	}
}

sub stop_flag {
	EV::unloop;
}

sub _run {
	my $self = shift;
	$self->start;
	$self->run;
	EV::loop;
}



1;
