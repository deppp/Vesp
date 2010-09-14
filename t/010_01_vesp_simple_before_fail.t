#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 010_01_vesp_simple_before_fail.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 010_01_vesp_simple_before_fail.t'
#   Mikhail <depp@deppp>     2010/09/11 12:39:15

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 2;
BEGIN { use_ok( Vesp::Simple ); }

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use AnyEvent;
use AnyEvent::HTTP;

my $cv = AE::cv;

vesp_http_server undef, 8080;

vesp_before qr{.*} => sub {
    my $req = shift;
    $req->done('OK');
};

vesp_route '/test' => sub {
    my $req = shift;
    # should never be called;
    fail('call to vesp_route');
};

http_get 'http://127.0.0.1:8080/test', sub {
    my ($body, $headers) = @_;
    is ($body, 'OK', 'vesp_before okay');
    $cv->send;
};

$cv->recv;
