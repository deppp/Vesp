use strict;
use warnings;
use inc::Module::Install;

name 'Vesp';

perl_version '5.008';
all_from     'lib/Vesp.pm';
license      'perl';

requires 'common::sense';
requires 'AnyEvent';
requires 'AnyEvent::AIO';

requires 'IO::AIO';
requires 'IO::AIO::Temp';

requires 'Scalar::Util';
requires 'List::Util';

requires 'HTTP::Message';
requires 'HTTP::Headers';

requires 'CGI::Simple::Cookie';

test_requires 'Test::More';

tests_recursive();
WriteAll();
