#!/usr/bin/perl -Iblib/lib -Iblib/arch -I../blib/lib -I../blib/arch
# 
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 012_vesp_body.t'

# Test file created outside of h2xs framework.
# Run this like so: `perl 012_vesp_body.t'
#   Mikhail <depp@deppp>     2010/07/31 13:19:16

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 5;
BEGIN {
    use_ok( 'Vesp::Simple' );
    use_ok( 'Vesp::Body' );
}

#########################

# Insert your test code below, the Test::More module is used here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use AnyEvent;
use AnyEvent::HTTP;
use HTTP::Request::Common;

my $cv = AnyEvent->condvar;

vesp_http_server undef, 8080;

vesp_route '/body_test_url_encoded' => sub {
    my ($req) = @_;
    
    is($req->body->params->{hello}, 'world', 'url encoded ok1');
    is($req->body->params('name'), 'miha', 'url encoded ok2');
        
    $req->done('OK');
};

vesp_route '/body_test_multi_part' => sub {
    my ($req) = @_;
    
    is($req->body->params->{hello}, 'world', 'multi part ok');
    
    $req->done('OK');
};

# url encoded
$cv->begin;
http_post 'http://127.0.0.1:8080/body_test_url_encoded',
    'hello=world&name=miha',
    headers => { 'Content-type' => 'application/x-www-form-urlencoded' },
    sub {
        my ($body, $headers) = @_;
        $cv->end;
    };

# simple multi-part
my $req = POST 'http://127.0.0.1:8080/body_test_multi_part',
    Content_type => 'form-data',
    Content => [hello => 'world'];

$cv->begin;
http_post 'http://127.0.0.1:8080/body_test_multi_part',
    $req->{_content},
    headers => { 'Content-type' => $req->{_headers}->{'content-type'} },
    sub {
        my ($body, $headers) = @_;
        $cv->end;
    };

TODO: {
    # complex multi part (file uploads)
    #$cv->begin;
    #http_post 'http://127.0.0.1:8080/body_test_multi_part',
    #    $req->{_content},
    #    headers => { 'Content-type' => $req->{_headers}->{'content-type'} },
    #    sub {
    #        my ($body, $headers) = @_;
    #        $cv->end;
    #    };
};

$cv->recv;
