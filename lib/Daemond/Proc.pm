package Daemond::Proc;

use uni::perl ':dumper';
our @FIELDS = qw(name action state type);
our %FIELDS; @FIELDS{@FIELDS} = (1)x@FIELDS;

sub new {
	my $pk = shift;
	my $self = bless {
		type => "dummy",
		action => "dummy",
		@_
	}, $pk;
	$self;
}

sub stats {
	my $self = shift;
	return '';
}

sub info {
	my $self = shift;
	my %args = @_;
	my $update = 0;
	for (keys %args) {
		if(exists $FIELDS{$_}) {
			$update = 1 if $self->{$_} ne $args{$_};
			$self->{$_} = $args{$_};
		} else {
			carp ref($self)." have no field $_";
		}
	}
	$self->refresh if $update;
	return;
}

sub refresh {
	my $self = shift;
	$0 =
		"<> ". # << Daemond ;)
		$self->{name} .
		( $self->{type} ? " ($self->{type})" : '' ).
		': '.
		( $self->{state} ? "[$self->{state}] " : '').
		$self->{action}. ' '.
		$self->stats;
}

for my $acc (@FIELDS) {
	no strict 'refs';
	*$acc = sub {
		my $self = shift;
		if (@_) {
			if ($self->{$acc} ne $_[0]) {
				my $old = $self->{$acc};
				$self->{$acc} = shift;
				$self->refresh();
				return $old;
			}
		}
		return $self->{action};
	};
}

1;
