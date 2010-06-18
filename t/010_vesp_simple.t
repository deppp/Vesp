#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 010_vesp_simple.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 010_vesp_simple.t'
#   Mikhail <depp@deppp>     2010/04/09 12:04:22

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More qw( no_plan );
BEGIN { use_ok( Vesp::Simple ); }

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use AnyEvent;
use AnyEvent::HTTP;

my $cv = AnyEvent->condvar;

vesp_http_server undef, 8080;

vesp_before qr{^[/].*} => sub {
    my ($req) = @_;
    is($req->method, 'GET', 'vesp_before');
    $req->cnt;
};

vesp_route '/simple' => sub {
    my ($req) = @_;
    my $url = $req->uri->as_string;
    like($url, qr/simple/, 'string route matched');
    $req->done->('OK');
};

vesp_route qr/vesp/ => sub {
    my ($req) = @_;
    my $url = $req->uri->as_string;
    like($url, qr/vesp/, 'regex route matched');
    $req->done('OK'); # both ways are okay
};

foreach my $path (qw(simple vesp)) {
    $cv->begin;
    http_get 'http://127.0.0.1:8080/' . $path, sub {
        my ($body, $headers) = @_;
        is($body, 'OK', 'correct body');
        $cv->end;
    };
}

$cv->recv;
