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

# my $key = <<'KEY';
# -----BEGIN RSA PRIVATE KEY-----MIICXQIBAAKBgQC3ThlrkTMdu/mTPVjTRT+VwQCndmxl1twArh1iSulGYbJvc+DtzhAGA4oic37FxFDzq8HHXw/P0NrnIvIfpzcRENERf7lac3/j9HS/Y6FkqPUthB57vM4nz5681uHn49XgWAJvGYB4PWociW2Ac1SuYfWEHnDMFiVRkcGaX5kb8wIDAQABAoGAJ35EK9DU2ostcnO9N4er82/p3Cq/oBFyxRK+cfcB25AhCbJFu/axrRoGIPYRUjrB1j4jOflZRsUQ5Mu6rucwDbe3v7RzngrxODIN/CodqvFRkm1R4E2yQuefXp8tTiVOVwR4ALYO4vqvI7Iaa+9zBNuwit1/SsiKYS/1E3WcAIECQQDlznlxYO1jiPxIg9cVR43CZrzekm1pwdX0hehQRXZWN1jqkCLvJHVLRSJ6SIcfVFdyHwja66wTXxp65hQsqLsJAkEAzDLCL+9eurFfatmWgBE5+6aYHkoazkmpbWdUesqdmUlPiQW2OggDWj8dIwykccEF4au4XLfihA7+xTrmdWDSGwJBAKVv+yWQLdXWLCjYIOME3BzzcUyaBYJ5NNoP/KqtFwACYFSc50lZ6ccCQkveIsh/I2TYyrsvpnVbpeiL8kIkRmECQGaTBNsBemt72Duba6+Pd7oC+J0WipqfhB1x74zzJPGwUuS42s4R4mU+GQvXOO/vj13KXgUtVfsScUZwDP5fkYsCQQDduHqTmnmB41zWg6FbkW/l+J/LBXEaRC3k1/MdkGundYVcr+QoCpUiIWjgigHokGHk3lko1SulsqRXh6lR6nst-----END RSA PRIVATE KEY-----
# KEY

http_server undef, 8080, https => {
    key_file  => 'key_test.pem',
    cert_file => 'cert_test.pem'
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
