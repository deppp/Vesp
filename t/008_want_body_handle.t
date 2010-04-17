#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 008_want_read_handle.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 008_want_read_handle.t'
#   Mikhail <depp@deppp>     2010/04/03 13:18:25

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More qw( no_plan );
BEGIN { use_ok('Vesp::Server'); }

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use common::sense;

use AnyEvent;
use AnyEvent::HTTP;

use Vesp;

my $cv = AnyEvent->condvar;

http_server undef, 8080,
    want_body_handle => 1,
sub {
    my $done = pop;
    my ($method, $url, $hdr, $body_hdl) = @_;
    
    is($method, 'POST', 'method is post');
    is($url, '/', 'empty req url');
    
    $body_hdl->push_read(chunk => $hdr->{'content-length'}, sub {
        my ($hdl, $data) = @_;
        
        is($data, "Hello world", 'body is correct');
        
        my $content = "OK";
        $done->(200, { 'Content-Length' => length($content) }, $content, sub {
            pass("done writing response");            
        });
    });
};

http_post 'http://127.0.0.1:8080/', 'Hello world', sub {
    my ($body, $headers) = @_;
    
    my $expect = "OK"; 
    is($body, $expect, 'correct body');
    is($headers->{'content-length'}, length($expect), "correct content length");
    
    $cv->send;
};

$cv->recv;
