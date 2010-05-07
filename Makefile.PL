use inc::Module::Install;

name     'Daemond';
all_from 'lib/Daemond.pm';
author   'Mons Anderson <mons@cpan.org>';
license  'perl';

build_requires 'Test::More';

auto_install;

WriteAll;

