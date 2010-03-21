
use common::sense;
use EV;
use AnyEvent;
use AnyEvent::HTTP;

use Vesp;

http_server undef, 8080, sub {
    my $cb = pop @_;
    #my ($env, $done) = @_;
    #use Data::Dump 'dump';
    #dump \@_;

     my $body = "vesp test";
      $cb->(
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

  my $w = AE::timer 3, 0, sub {
      #foreach (0 .. 2000) {
          http_get 'http://127.0.0.1:8080', sub {
          #my ($body, $headers) = @_;
          #use Data::Dump 'dump';
          #dump $headers;
          #dump $body;
      };
      #}
     
  };

EV::loop;
