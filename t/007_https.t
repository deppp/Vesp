#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 007_https.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 007_https.t'
#   Mikhail <depp@deppp>     2010/03/27 07:38:02

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More qw( no_plan );
BEGIN { use_ok( Vesp ); }

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use common::sense;

use AnyEvent;
use AnyEvent::HTTP;

my $cv = AnyEvent->condvar;

http_server undef, 8080, tls => {
    key_file  => 't/test_key.pem',
    cert_file => 't/test_cert.pem'
}, sub {
    my $done = pop;
    my ($method, $url, $hdr, $body) = @_;
    
    is($method, 'GET', 'method is get');
    is($url, '/', 'empty req url');
    
    my $content = "Hello world";
    $done->(200, { 'Content-Length' => length($content) }, $content, sub {
        pass("done writing response");            
    });
            
    is($body, "", 'body is empty');
};

http_get 'https://127.0.0.1:8080/', sub {
    my ($body, $headers) = @_;
    
    my $expect = "Hello world"; 
    is($body, $expect, 'correct body');
    is($headers->{'content-length'}, length($expect), "correct content length");
    
    $cv->send;
};

$cv->recv;
