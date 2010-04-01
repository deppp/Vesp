#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 005_aio_serve.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 005_aio_serve.t'
#   Mikhail <depp@deppp>     2010/03/27 06:35:55

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 8;
BEGIN { use_ok( Vesp ); }

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use common::sense;

use Fcntl;
use AnyEvent;
use AnyEvent::HTTP;

use AnyEvent::AIO;
use IO::AIO;

# create 10mb file
my $filename = "test_aio_serve_file";
open (FH, "+>$filename") || die "$!";
print FH "1234567890" foreach 1 .. 1_000_000;
close FH;

my $cv = AnyEvent->condvar;

http_server undef, 8080, sub {
    my $done = pop;
    my ($method, $url, $hdr, $body) = @_;

    is($method, 'GET', 'method is get');
    is($url, '/aio_serve', 'serve request');

    aio_open $filename, O_RDONLY, 0, sub {
        my $fh = shift
            or die "$!";

        $done->(200, { 'Content-Length' => -s $fh }, $fh, sub {
            pass("served file");
            aio_close $fh, sub {
                pass("closed fh");
            }
        });
    };
    
    is($body, "", 'body is empty');
};

http_get 'http://127.0.0.1:8080/aio_serve', sub {
    my ($body, $headers) = @_;

    is(length $body, 10_000_000, 'correct body length');
    is($headers->{'content-length'}, 10_000_000, "correct content length");

    $cv->send;
};

$cv->recv;

unlink $filename;
