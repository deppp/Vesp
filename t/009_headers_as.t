#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 009_headers_as.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 009_headers_as.t'
#   Mikhail <depp@deppp>     2010/04/07 10:37:17

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 25;
BEGIN { use_ok( Vesp ); }

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use common::sense;

use AnyEvent;
use AnyEvent::HTTP;

use Vesp;
use Scalar::Util 'reftype';

my %test = (
    ScalarRef => sub {
        ok(reftype $_[0] eq 'SCALAR', 'scalar ref')
    },
    ArrayRef => sub {
        ok(reftype $_[0] eq 'ARRAY', 'array ref')
    },
    HashRef => sub {
        ok(reftype $_[0] eq 'HASH', 'hash ref')
    },
    'HTTP::Headers' => sub {
        ok(ref $_[0] eq 'HTTP::Headers', 'http headers')
    }
);

foreach my $headers_as_type (keys %test) {
    my $cv = AnyEvent->condvar;
    my $check = $test{$headers_as_type};
    
    my $server = http_server undef, 8080,
        headers_as => $headers_as_type,
    sub {
        my $done = pop;
        my ($method, $url, $hdr, $body) = @_;

        is($method, 'POST', 'method is post');
        is($url, '/', 'empty req url');
        
        $check->($hdr);
        
        my $content = "OK";
        $done->(200, { 'Content-Length' => length($content) }, $content, sub {
            pass("done writing response");            
        });
    };

    $cv->cb(sub { undef $server });
        
    http_post 'http://127.0.0.1:8080/', 'Hello world', sub {
        my ($body, $headers) = @_;
        
        my $expect = "OK"; 
        is($body, $expect, 'correct body');
        is($headers->{'content-length'}, length($expect), "correct content length");
        $cv->send;
    };
    
    $cv->recv;
}
