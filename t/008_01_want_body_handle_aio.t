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

use Fcntl;

use AnyEvent;
use AnyEvent::HTTP;

use AnyEvent::AIO;
use IO::AIO;

use File::Slurp 'read_file';
use Vesp;

my $cv = AnyEvent->condvar;

my $filename = "test_aio_serve_file";
my $expect = read_file($filename);

http_server undef, 8080,
    want_body_handle => 1,
sub {
    my $done = pop;
    my ($method, $url, $hdr, $body_hdl) = @_;
    
    is($method, 'GET', 'method is post');
    is($url, '/', 'empty req url');

    _serve_file($filename, $done);
    
};

http_get 'http://127.0.0.1:8080/', sub {
    my ($body, $headers) = @_;
    
     
    is($body, $expect, 'correct body');
    is($headers->{'content-length'}, length($expect), "correct content length");
    
    $cv->send;
};

$cv->recv;

sub _serve_file {
    my ($path, $done) = @_;

    aio_open $path, O_RDONLY, 0, sub {
        my ($fh) = @_
            or $done->(_http_res(404, $!)), return;
        
        my $size = -s $fh;
        
        $done->(200, {
            'Content-Type'   => 'text/plain',
            'Content-Length' => $size
        }, $fh, sub {
            aio_close $fh, sub {
                pass("test");
                close $fh;
            };
        });
    };
}
