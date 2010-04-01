package Vesp;
use common::sense;

use Carp ();
use Vesp::Server;

require Exporter;

our @ISA = 'Exporter';
our @EXPORT = 'http_server';

our $VERSION = '0.01';

=head1 NAME

Vesp - Small embeddable non-blocking webserver, based on AnyEvent

=head1 SYNOPSIS

  use Vesp;
  http_server undef, 8888, sub {
      my ($method, $url, $hdr, $body, $done) = @_;
      
  } 

=head1 DESCRIPTION

This module implements very simple and very configurable HTTP web server.
Embedding it into your software is very easy, and since this server doesn't
use condvars you won't get any errors if you do use it.

=head2 EXPORT

Only one function is exported C<http_server>, but there are a bunch of config
options

=over 4

=item my $guard = http_server $host, $port, [%options] => $callback

Create http web server running on $host and $port. When new http request
comes in, C<< $callback->($method, $url, $hdr, $body, $done) >> gets called.

Example: create a webserver on local machine and port 8888

    http_server undef, 8888, sub {
        my ($method, $url, $hdr, $body, $done) = @_;
 
        my $content = "Hello world\n";
        $done->(200, { 'Content-Type' => length $content }, $content);
    }

Your callback receives a number of arguments, first one is $method which
is HTTP method type, like GET or POST. Next one is $url which is request
url, an example might be "/" for root location, i.e. http client accessing
http://yourhost/. After this you have $hdr, by default they will be represented
by HTTP::Headers object, but this is configurable so lookup options below.
Then comes $body - body of http request, by default it's not parsed at all, so
you'll get a plain text, but this is also configurable. And the last option is
$done - an anonymous subroutine referency which you call when you want to send
a reply to http client.

$done callback takes a number of arguments as well, first comes http status code,
this could be represented as either number - 200, 404, 501, etc or as a string -
OK, NOT FOUND, etc. Then headers should come, either as HashRef, ArrayRef, ScalarRef
or HTTP::Headers object instance. After that comes http body content, which you can
pass in as a simple string (which i don't recomend if it's big), ScalarRef or FileHandle,
All the above parameters are required, there is another forth optional parameter -
a callback which is called when writing http response ends.

Example: Serve a static file to every client connecting (we're using IO::AIO here so
it doesn't block)

    http_server undef, 8888, sub {
        my ($method, $url, $hdr, $body, $done) = @_;
    
        aio_open "some/file", O_RDONLY, 0, sub {
            my $fh = shift
                or $done->(404, {
                    'Content-Length' => 9,
                    'Content-Type'   => 'text/plain'
                }, 'Not found'), return;
    
            $done->(200, {
                'Content-Length' => -s $fh,
                'Content-Type'   => 'text/plan' # or whatever
            }, $fh, sub {
                # at this point we're sure that
                # it has finished writing http reponse
            aio_close $fh, sub {};
            })
        };
    };

$guard is Guard object and if you undefy it, it will finish all http
requests with Temprorary unavailable error.

Now let's look at the configuration options that you have

=over 4

=item https

=item want_read_body_handle

=item want_write_body_handle

=item headers_as

=item body_as

=item url_as

=item on_connect

=item timeout

=item timeout_cb

=item psgi

=item gzip

=back

=back

=cut

sub http_server ($$@) {
    my $cb = pop;
    my ($host, $port, %args) = @_;

    my $server = Vesp::Server->new(
        host => $host,
        port => $port,
        %args
    );
    
    $server->on_request($cb);

    defined wantarray && $server->{_guard};
}

=head1 SEE ALSO

AnyEvent AnyEvent::Socket AnyEvent::Handle AnyEvent::HTTPD Twiggy

=head1 AUTHOR

Mikhail Maluyk, E<lt>mikhail.maluyk@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Mikhail Maluyk

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut

1;
