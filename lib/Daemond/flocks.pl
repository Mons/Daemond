#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use Cwd ();
use POSIX qw(O_EXCL O_CREAT O_RDWR); 
use Fcntl;# qw(LOCK_SH LOCK_EX LOCK_NB LOCK_UN);

my ($f,$file,$failures);
$file = 'flock.test';

	OPEN: {
		if (-e $file) {
			unless (sysopen($f, $file, O_RDWR)) {
				redo OPEN if $!{ENOENT} and ++$failures < 5;
				croak "open $file: $!";
			}
		} else {
			unless (sysopen($f, $file, O_CREAT|O_EXCL|O_RDWR)) {
				redo OPEN if $!{EEXIST} and ++$failures < 5;
				croak "open >$file: $!";
			}
		}
		last;
	}
	#my $r = flock($f, LOCK_EX | LOCK_NB);
	
	my $r = fcntl( $f, F_SETLK, pack('ll ll i s s',0,0, 0,0, $$, F_WRLCK() ,0) );
	if ($r) {
		warn "Flock succeeded";
		syswrite($f,"$$\n");
		sysseek $f,0,0;
		my $exit = 0;
		$SIG{INT} = sub { $exit = 1; };
		while (!$exit) {
			sleep 1;
		}
	} else {
		warn "Flock failed: $!";
	}