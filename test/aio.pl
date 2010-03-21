
use common::sense;
use EV;
use AnyEvent;
use IO::AIO;
use AnyEvent::AIO;

use Fcntl;
use Scalar::Util 'reftype';

my $d;

open $d, "001.pl";
print "reftype1:", reftype($d), "\n";
use Data::Dump 'dump';
dump $d;

aio_open ("001.pl", O_RDONLY, 0777, sub {
              my ($fh) = @_;
              use Data::Dump 'dump';
              dump $fh;
              print "reftype:", reftype($fh), "\n";
              print "fileno:", fileno($fh), "\n";
              my $str = "$fh";
              print "str:", $str, "\n";
              
              
});


EV::loop;
