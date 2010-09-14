#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 013_vesp_util.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 013_vesp_util.t'
#   Mikhail <depp@deppp>     2010/08/01 17:36:05

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
BEGIN {
    use_ok( Vesp );
    use_ok( Vesp::Util );
}

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use AnyEvent;
use AnyEvent::HTTP;

my $cv = AnyEvent->condvar;

http_server undef, 8888, sub {
    my ($method, $url, $hdr, $body, $done) = @_;

    if ($url eq '/') {
        $done->(Vesp::Util::respond 'OK');
    } elsif ($url eq '/redirect') {
        $done->(Vesp::Util::redirect 'http://127.0.0.1:8888/');
    }
};

$cv->begin;
http_get 'http://127.0.0.1:8888/', sub {
    my ($body, $hdr) = @_;
    is($body, 'OK', 'respond');
    $cv->end;
};

$cv->begin;
http_get 'http://127.0.0.1:8888/redirect', sub {
    my ($body, $hdr) = @_;
    is ($hdr->{Status}, 200, 'status');
    is ($body, 'OK', 'body');
    $cv->end;
};

$cv->recv;
