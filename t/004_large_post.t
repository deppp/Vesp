#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 004_large_post.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 004_large_post.t'
#   Mikhail <depp@deppp>     2010/03/27 06:31:35

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
BEGIN { use_ok( Vesp ); }

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use common::sense;

use AnyEvent;
use AnyEvent::HTTP;

my $cv = AnyEvent->condvar;
my $large_post = "";
foreach (1 .. 1_000_000) {
    $large_post .= "test" . $_ . "=" . $_;
}

http_server undef, 8080, sub {
    my $done = pop;
    my ($method, $url, $headers, $body) = @_;
    
    is($method, 'POST', 'method is post');
    is($url, '/large_post', 'url is /large_post');
    is($body, $large_post, 'post body');
    
    $done->(200, {
        'Content-Type'   => 'text/plain',
        'Content-Length' => 0
    }, "");
};

http_post 'http://127.0.0.1:8080/large_post', $large_post, sub {
    my ($body, $headers) = @_;
    is($headers->{Status}, 200, 'OK status');
    $cv->send;
};

$cv->recv;

