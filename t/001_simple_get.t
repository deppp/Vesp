#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 001_get.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 001_get.t'
#   Mikhail <depp@deppp>     2010/03/19 23:23:09

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 7;
BEGIN { use_ok( Vesp ); }

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use common::sense;

use AnyEvent;
use AnyEvent::HTTP;

my $cv = AnyEvent->condvar;

http_server undef, 8080, sub {
    my $done = pop;
    my ($method, $url, $hdr, $body) = @_;

    is($method, 'GET', 'method is get');
    is($url, '/', 'url is /');
    is($body, "", 'body is empty');

    my $res = "test";
    $done->(200, { 'Content-Length' => length $res }, $res, sub {
        pass("on_done callback called");
    });
};

http_get 'http://127.0.0.1:8080/', sub {
    my ($body, $headers) = @_;

    is($body, "test", 'body is text');
    is($headers->{'content-length'}, 4, "one header only");

    $cv->send;
};

$cv->recv;
