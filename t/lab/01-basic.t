#!/usr/bin/env perl

use 5.010;
use strict;
use lib::abs '../../lib';#,'../blib/lib','../blib/arch';
use Test::More;
use DDP;
#use Scalar::Util 'refaddr';
#use Mouse::Util;
#use Devel::Refcount 'refcount';

use Daemond::Lab;
use Daemond::Lab::Cfg;
use Daemond::Lab::Log;

my $lab = Daemond::Lab->new();

p $lab;

p $lab->cfg;