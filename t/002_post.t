#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 002_post.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 002_post.t'
#   Mikhail <depp@deppp>     2010/03/19 23:33:14

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
BEGIN { use_ok( Vesp ); }

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use common::sense;

use EV;
use AnyEvent;
use AnyEvent::HTTP;

my $post = "test1=1&test2=2";

http_server undef, 8080, sub {
    my $done = pop;
    my ($method, $url, $headers, $body) = @_;

    is($method, 'POST', 'method is post');
    is($url, '/', 'url is /');
    is($body, $post, 'post body');

    $done->(200, {}, "");
};

http_post 'http://127.0.0.1:8080/', $post, sub {
    my ($body, $headers) = @_;

    is($headers->{Status}, 200, 'OK status');

    EV::unloop;
};

EV::loop;

