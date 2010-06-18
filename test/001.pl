
use common::sense;
use EV;
use AnyEvent;
use AnyEvent::HTTP;

use Vesp;



http_server undef, 8080,
    headers_as       => 'HashRef',
    want_body_handle => 1,
    sub {
        my ($method, $url, $hdr, $hdl, $done) = @_;
    
        my $body = "vesp test";
        $done->(
            200,
            {
                'Content-Length' => length $body,
                'Content-Type'   => 'text/plain'
            },
            $body,
            sub {
                #exit;
            }
      );
};

#  my $w = AE::timer 3, 0, sub {
      #foreach (0 .. 2000) {
  #        http_get 'http://127.0.0.1:8080', sub {
          #my ($body, $headers) = @_;
          #use Data::Dump 'dump';
          #dump $headers;
          #dump $body;
 #     };
      #}
     
  #};

EV::loop;
