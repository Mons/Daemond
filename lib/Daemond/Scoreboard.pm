package Daemond::Scoreboard;

use uni::perl ':dumper';
use accessors::fast qw(cache _size _score fh child log);
use Sys::Mmap;
use Scalar::Util qw(weaken);

our %STATES = (
	'.' => 'Empty',
	'F' => 'Forking',
	'S' => 'Starting',
	'_' => 'Ready',
	'W' => 'Working',

	'G' => 'Finishing',
);

#our @CONST = qw( TAKEN FORKING STARTING READY WORKING FINISHING ZOMBIE );
our @CONST = qw( FORKING STARTING READY WORKING FINISHING );

sub DEBUG     () { 0 }

sub EMPTY     () { '.' }
sub TAKEN     () { '?' }
sub FORKING   () { 'F' }
sub STARTING  () { 'S' }
sub READY     () { '_' }
sub WORKING   () { 'W' }
sub FINISHING () { 'G' }
sub ZOMBIE    () { 'Z' }

sub import {
	my $me = shift;
	my $pkg = caller;
	no strict 'refs';
	@_ or return;
	if ($_[0] eq ':const') {
		*{$pkg . '::' . $_} = \&$_ for @CONST;
	}else{
		my %exp = map { $_ => 1 } @_;
		for (@CONST) {
			if (delete $exp{$_}) {
				*{$pkg . '::' . $_} = \&$_;
			}
		}
		if (%exp) {
			croak "@{[ keys %exp ]} is not exported by $me";
		}
	}
}

sub init {
	my $self = shift;
	my %args = @_;
	if ($args{size}) {
		$self->size(delete $args{size});
	}
	$self->next::method(%args);
}

sub size {
	my $self = shift;
	if (@_) {
		$self->child and croak "$$: Size change prohibited for child";
		my $size = shift;
		my $old = $self->{_size};
		my $score;
		if (defined $self->{_score} and $size == $old) {
			printf STDERR "$$: Scoreboard size not changed | [%s]\n",${$self->{_score}} if DEBUG;
			return $size;
		}
		elsif (defined $self->{_score} and $size != $old) {
			# remap;
			my $oldscore = "${$self->{_score}}";
			if ($old > $size) {
				#trunkate
				$score = substr($oldscore,0,$size);
			} else {
				# extend
				$score = $oldscore . ( '.'x( $size - $old) );
			}
			munmap ${$self->{_score}} or die "munmap failed: $!";
			printf STDERR "$$: Old scoreboard unmmapped from size %d | [%s] => [%s]\n",$old,$oldscore,$score if DEBUG;
			close $self->{fh};
			undef $self->{_score};
		} else {
			$score = '.'x$size;
			printf STDERR "$$: Init new scoreboard size %d | [%s]\n",$size,$score if DEBUG;
		}
		$self->{_size} = $size;
		
		open my $fh, '+>', undef or die "open tempfile failed: $!";
		$self->{fh} = $fh;
		print $fh $score;
		seek $fh,0,0;
		my $sc;
		my $addr = mmap($sc, $size, PROT_READ|PROT_WRITE, MAP_SHARED, $fh) or die "mmap failed: $!";
		$self->{_score} = \$sc;
		printf STDERR "$$: Scoreboard mmapped to size %d, at addr 0x%08x | [%s]\n",$size,$addr,${$self->{_score}} if DEBUG;
		return $old;
	}
	return $self->{_size};
}

sub view {
	my $self = shift;
	return '['.${$self->{_score}}.']';
}

sub take {
	my $self = shift;
	$self->{_size} > 0 or croak "$$: Scoreboard of size < 1 is useless (size=$self->{_size})";
	my $state = shift || TAKEN;
	my $slot = index(${$self->{_score}}, '.');
	printf STDERR "$$: Found slot $slot\n" if DEBUG;
	$slot == -1 and return;
	substr(${$self->{_score}},$slot,1) = $state;
	return $slot + 1;
}

sub drop {
	my $self = shift;
	my $slot = shift() - 1;
	my $ok = 0;
	if (substr(${$self->{_score}},$slot,1) ne EMPTY) {
		substr(${$self->{_score}},$slot,1) = EMPTY;
		return 1;
	} else {
		carp "$$: Slot $slot not taken";
		return 0;
	}
}

sub active_slots {
	my $self = shift;
	my @rv;
	for (0..$self->{_size}-1) {
		push @rv, $_+1 if substr(${$self->{_score}},$_,1) ne EMPTY;
	}
	return @rv;
}

sub slots {
	my $self = shift;
	my %active;
	for ($self->active_slots) {
		$active{$_} = $self->s($_)
	}
	return \%active;
}

sub s {
	my $self = shift;
	my $slot = shift;
	$slot > 0 and $slot <= $self->{_size} or croak "$$: Bad slot $slot for size $self->{_size}";
	if (@_) {
		my $old = substr(${ $self->{_score} },$slot-1,1);
		substr(${ $self->{_score} },$slot-1,1) = uc substr shift,0,1;
		return $old;
	} else {
		return substr(${ $self->{_score} },$slot-1,1);
	}
}

sub state {
	my $self = shift;
	my $slot = $self->child or carp("$$: Only child should operate on state"),return;
	if (@_) {
		my $state = shift;
		$STATES{$state} or croak "$$: Wrong state $state";
		my $old = $self->s( $slot, $state );
		printf STDERR "$$: State %s => %s\n", $old, $state if DEBUG;
		return $old;
	} else {
		return $self->s( $slot );
	}
}

sub DESTROY {
	my $self = shift;
	if ($self->child) {
		printf STDERR "$$: Destroy child\n" if DEBUG;
		$self->s($self->child,ZOMBIE);
	} else {
		if (defined $self->{_score}) {
			munmap ${$self->{_score}};
		}
	}
}

1;
