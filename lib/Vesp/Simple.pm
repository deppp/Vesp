package Vesp::Simple;
use common::sense;
use bytes;

use Carp qw(carp croak);
use Vesp;
use Vesp::Body;
use Vesp::Server;
use Vesp::Util 'respond';

use URI;
use Scalar::Util 'reftype', 'blessed';
use CGI::Simple::Cookie;

require Exporter;

our @ISA = 'Exporter';
our @EXPORT = ('vesp_route', 'vesp_before', 'vesp_http_server');
our @EXPORT_OK = ('vesp_routes', 'vesp_drop_route');

=head1 NAME

Vesp::Simple - Simple http server

=head1 SYNOPSIS

=head1 DESCRIPTION

Simple preconfigured Vesp server, manages headers, body, roots and other stuff for you

=cut

=head1 METHODS

=cut

=head2 vesp_http_server $host, $port, %args

=cut

our $disp;

sub vesp_http_server ($$@) {
    my ($host, $port, %args) = @_;

    my $disp_class = $args{dispatcher} || 'Vesp::Dispatcher::Basic';
    # [TODO]
    eval "require $disp_class";
        
    $disp = $disp_class->new($args{dispatcher_args});

    my $route_done = sub {
        my $done = shift;
        my ($status, $hdr, $body, $cb);
        
        if (scalar @_ == 1) {
            $body = shift;
        } else {
            my %args = @_;
            
            $status = $args{status};
            $hdr    = $args{headers};
            $body   = $args{body};
            $cb     = $args{cb};
        }
        
        if (! defined $body) {
            carp "Body is required param";
            $body = "Default body";
        } 
        
        $status ||= 200;
        $done->(respond($status, $hdr, $body), $cb);               
    };
    
    Vesp::http_server $host, $port,
        header_as => 'HTTP::Headers',
        want_body_handle => 1,
        sub {
            my ($method, $url, $hdr, $hdl, $done) = @_;
            
            my $body = Vesp::Body->new(
                ctype  => $hdr->{'content-type'},
                length => $hdr->{'content-length'},
            );

            $body->init($hdl, sub {
                my ($body) = @_;
                
                my $req = Vesp::Simple::Request->new(
                    method => $method,
                    uri    => URI->new($url),
                    hdr    => $hdr,
                    body   => $body,
                );

                my ($cb, $captures) = @{ $disp->find_route($url, $method, $hdr, $body) };
                $cb || ($done->(respond 404, "Route for $url not found"), return);
                
                $req->{captures} = $captures;
                $req->{done} = sub { $route_done->( $done, @_ ) };
                
                # right now we use only 1 before route, not multiple
                my $before = $disp->find_before_route($url);
                if (my $before_cb = shift @$before) {
                    $req->{cnt} = sub { $cb->($req) };
                    $before_cb->($req);                
                } else {
                    $cb->($req);
                }
            });
        };
}

=head2

=cut

sub vesp_drop_route {
    croak "not implemented yet"
}

=head2 vesp_before

=cut

sub vesp_before ($$@) {
    $disp->add_before_route(@_);
}

=head2 vesp_route $route, $callback

Defines new http route. Example:

    vesp_route '/some/page' => sub {
        my ($req) = @_;
        $req->done('OK');
    }

Array of routes is okay:

    vesp_route ['/some/page', 'another/page'] => sub {
        my ($req) = @_;
        $req->done('OK');
    }

Regex and array of regex is okay as well:

    vesp_route qr{^/some/\d+/show/?$} => sub {
        my ($req) = @_;
        $req->done('OK');
    }

=cut

sub vesp_route ($$@) {
    $disp->add_route(@_);
}

=head2 vesp_routes %args

Defined several routes in one call, example:

    vesp_routes
        '/some/page'   => sub {},
        'another/page' => sub {}

=cut

sub vesp_routes(@) {
    my (%args) = @_;
    vesp_route $_ => $args{$_}
        for keys %args;
}

package Vesp::Simple::Request;
use common::sense;

use URI::Escape;

=head1 NAME

Vesp::Simple::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

Vesp::Simple request object, easily access methods urls headers etc.

=head1 METHODS

=cut

=head2 new

=cut

sub new {
    my ($class, %args) = @_;
    my $self = bless \%args, $class;

    my $qparams = $self->{uri}->query;
    foreach my $kv (split /&/, $qparams) {
        my @kv = split /=/, $kv;
        $self->{qparams}->{$kv[0]} = $kv[1];
    }
    
    $self;
}

=head2 method

HTTP method

=head2 uri

Requested url as URI object

=head2 hdr

Headers as HTTP::Headers object

=head2 args

Captures from regexp matched variables ($1, $2, $3, etc).
Example:

    vesp_route qr{/some/page/([\d]+)/?$} => sub {
        my ($req) = @_;
        
    }

    GET /some/page/10

    $req->args->[0] holds "10"

=head2 body

Access to body of the request (example: data submitted via html form),
look at Vesp::Body documentation for avialable methods.

=cut

sub method { $_[0]->{method} }
sub uri    { $_[0]->{uri} }
sub hdr    { $_[0]->{hdr} }
sub args   { $_[0]->{captures} }
sub body   { $_[0]->{body} }

=head2 cnt

When request is processed in "vesp_before" callback, you need to
call "cnt" method for dispatch to continue it's job.

=head2 done $body || %args

When you're done processing reuqest you need to call "done" method,
this will send $body response to client. You can tune more params
than just body if you supply %args:

=item status

HTTP status code, default is 200

=item headers

Hashref with additional headers

=item body

Body of the response

=item cb

Callback which will be called when after all data has been written to
client and connection was closed.

=back

=cut

sub cnt    { (delete $_[0]->{cnt})->() }
sub done   {
    my $self = shift;
    delete $self->{cnt};
    
    if (@_) {
        $self->{done}->(@_);
    } else {
        $self->{done}
    }
}

=head2 query_params [$key]

URIs query parameters

=cut

sub query_params {
    my $self = shift;

    if (@_) {
        my $key = shift;
        return $self->{qparams}->{$key}
    } else {
        return $self->{qparams};
    }
}

=head2 session

might be removed in future versions

=cut

sub session { $_[0]->{session} }

1;
