use strict;
use lib::abs '..';
use Log::Any::Adapter;
use Rambler::Log;

# TEST

sub Log::Any::Adapter::Core::prefix {
	warn "@_";
}

Log::Any::Adapter->set( 'Dispatch', dispatcher => Rambler::Log->mklog );
#use Log::Any '$log';
use Daemond::Log '$log';
$log->prefix("123 ");
$log->debug("test: %s", "ok");
$log->crit("epic %s","fail");
exit;




#TEST

