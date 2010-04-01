#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 003_large_get.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 003_large_get.t'
#   Mikhail <depp@deppp>     2010/03/27 06:22:54

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

# 10 mb
my $big_body = "";
foreach (1 .. 1_000_000) {
    $big_body .= '1234567890';    
}

http_server undef, 8080, sub {
    my $done = pop;
    my ($method, $url, $hdr, $body) = @_;

    is($method, 'GET', 'method is get');
    is($url, '/large_get', 'url is /large_get');
    is($body, "", 'body is empty');
    
    $done->(200, { 'Content-Length' => length $big_body }, $big_body, sub {
        pass("on_done callback called");
    });
};

http_get 'http://127.0.0.1:8080/large_get', sub {
    my ($body, $headers) = @_;
    
    is($body, $big_body, 'body is text');
    is($headers->{'content-length'}, 10_000_000, "content length");
    
    $cv->send;
};

$cv->recv;
