use Log::Any::Adapter;
use Rambler::Log;
use Log::Dispatch::File;

#{open my $f, '>', lib::abs::path('debug.log');truncate $f,0;}
my $dispatch = Rambler::Log->mklog;
$dispatch->add( Log::Dispatch::File->new(
	name => 'file', mode => 'append', filename => lib::abs::path('debug.log'), min_level => 'debug',
));
$dispatch->remove('syslog');
#$dispatch->remove('screen');
Log::Any::Adapter->set( 'Dispatch', dispatcher => $dispatch );
