package Daemond::Lab;

use Mouse;
use Mouse::Role ();

# our $INSTCLS = __PACKAGE__;
our @EXTENSIONS;
our @POSTPONED;

CHECK {
	$_->() for @POSTPONED;
}

sub import {
	my $self = shift;
	my $caller = caller;
	if (@_) {
		if ($_[0] eq '-base') {
			warn "call to base $self from $caller\n";
			my $meta = Mouse::Meta::Class->initialize($caller);
			$meta->superclasses($self);
		}
		elsif ($_[0] eq '-ext') {
			warn "call to ext $self from $caller\n";
			Mouse::Meta::Role->initialize($caller);
			# push @EXTENSIONS, $clr;
			# Mouse::Role->import( 'Mouse::Role',$clr );
			push @POSTPONED, sub {
				warn "Apply $caller to $self";
				Mouse::Util::apply_all_roles( $self, $caller );
			};
		}
		else {
			die "Unknown use options [@_]";
		}
	}
	# else {
	# 	warn "merge $clr as role to $self";
	# }
}

sub BUILD {
	my $self = shift;
	warn "building $self + @EXTENSIONS";
}

sub check  {}
sub start  {}
sub run    {}
sub rise   {}
sub perish {}

warn "lab loaded";
1;

__END__

# refines, amends, improves, clarify


improve
refine
enrich
amend

---

App::Lab

use Daemond::Lab;

extends 'Daemond::Lab';

#improves 'Daemond::Lab';
	# isa Daemond::Lab;

sub check {}
sub run {}

---

App::Lab::DB

use App::Lab;

refines 'App::Lab', with => 'db';
	# became a "child" to App::Lab
	# App::Lab is being injected a key 'db' with instance of an object

sub check {}
sub run {}

---

App::Lab::DB::Cfg;

use App::Lab;

refines 'App::Lab::DB', with => 'cfg';
needs   'cfg', from => 'Daemond::Cfg';

---

App::Lab::DB::T1;

refines 'App::Lab::DB', with => 't1';
needs   'db.cfg';

---

App::Lab::DB::T2;

refines 'App::Lab::DB', with => 't2';
needs   'db.cfg';
needs   'db.t1';

---

App::Lab::DB::Bundle_Of_T1_T2;

use App::Lab::DB::T1;
use App::Lab::DB::T2;

---

lab
	cfg
	log
	db
		cfg
		t1
		t2

---

package App::API::v1;

use App::Lab::DB::T1;

lab->db->t1->select();
lab->db->t2 # no

---

package App::API::v2;

use App::Lab::DB::Bundle_Of_T1_T2;
	# implicit t1, t2

lab->db->t1->select();
lab->db->t2->select();

---

D->do_check
	lab->checkall()
		cfg->check
		log->check
		db->check
			t1->check
			t2->check
	App->check(lab)

# alphabetical sort
# priority
