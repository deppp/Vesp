package Vesp::Simple;
use common::sense;
use bytes;

use Carp qw(carp croak);
use Vesp;
use Vesp::Server;

use URI;
use Scalar::Util 'reftype', 'blessed';
use CGI::Simple::Cookie;

require Exporter;

our @ISA = 'Exporter';
our @EXPORT = ('vesp_route', 'vesp_before', 'vesp_http_server');
our @EXPORT_OK = ('vesp_routes');

=head1 NAME

Vesp::Simple -  

=head1 SYNOPSIS

=head1 DESCRIPTION

Simple preconfigured Vesp server, manages headers and roots for you

=cut

=head1 METHODS

=cut

=head2 vesp_http_server

=cut

our $disp;

sub vesp_http_server ($$@) {
    my ($host, $port, %args) = @_;

    my $disp_class = $args{dispatch} || 'Vesp::Simple::Dispatcher::Basic';
    $disp = $disp_class->new($args{dispatch_args});

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
        $done->(_http_res($status, $hdr, $body), $cb);               
    };
        
    Vesp::http_server $host, $port,
        header_as => 'HTTP::Headers',
        #body_as   => 'Vesp::Body', # when it's ready...
        sub {
            my ($method, $url, $hdr, $body, $done) = @_;
            
            my $req = Vesp::Simple::Request->new(
                method => $method,
                uri    => URI->new($url),
                hdr    => $hdr,
                body   => $body,
            );
            
            my ($cb, $captures) = @{ $disp->find_route($url) };
            $cb || ($done->(_http_res(404, "Route for $url not found")), return);
            
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
        };
}

=head2 vesp_before

=cut

sub vesp_before ($$@) {
    $disp->add_before_route(@_);
}

=head2 vesp_route

=cut

sub vesp_route ($$@) {
    $disp->add_route(@_);
}

=head2 vesp_routes

=cut

sub vesp_routes(@) {
    my (%args) = @_;
    vesp_route $_ => $args{$_}
        for keys %args;
}

my @_dow = qw/Sun Mon Tue Wed Thu Fri Sat/;
my @_moy = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;

sub _time2str (;$) {
    my $time = shift || time;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($time);
    sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
	    $_dow[$wday],
	    $mday, $_moy[$mon], $year+1900,
	    $hour, $min, $sec);
}

sub _http_res {
    my $body = pop;
    my ($status, $hdr) = @_;

    $hdr ||= {};
        
    return $status, {
        'Date'           => _time2str,
        'Content-Lenght' => ref($body) ? bytes::length($$body) : bytes::length($body),
        'Content-Type'   => 'text/html',
        %$hdr
    }, $body;
}

package Vesp::Simple::Dispatcher;
use common::sense;
use Carp 'confess';

=head1 NAME

Vesp::Simple::Dispatcher

=head1 DESCRIPTION

=cut

my $warning = sub {
    confess "You should define ", $_[0], " method in your dispatcher";
};

sub add_route        { $warning->('add_route') }
sub add_before_route { $warning->('add_before_route') }

# [TODO] decide if optional ?
sub find_route {} 
sub find_before_route {}

package Vesp::Simple::Dispatcher::Basic;
use common::sense;
use base 'Vesp::Simple::Dispatcher';

sub new {
    my ($class, %args) = @_;
    my $self = bless \%args, $class;

    $self->{regexp_route} = [];
    $self->{regexp_before_route} = [];
        
    $self;
}

sub add_route {
    my $cb = pop;
    my ($self, $routes, %args) = @_;

    $self->_add_any_route($routes, 'route', %args, $cb);
}

sub add_before_route {
    my $cb = pop;
    my ($self, $routes, %args) = @_;

    $self->_add_any_route($routes, 'before_route', %args, $cb);
}

sub _add_any_route {
    my $cb   = pop;
    my ($self, $routes, $type, %args) = @_;
    
    $routes = [ $routes ]
        if ! ref $routes or ref $routes eq 'Regexp';
    
    foreach my $route (@$routes) {
        if (ref $route && ref $route eq 'Regexp') {
            push @{ $self->{'regexp_' . $type} }, $route;
            push @{ $self->{'regexp_' . $type} }, $cb;
        } elsif (! ref $route) {
            $self->{$type}->{$route} = $cb;
        } else {
            die "Only Regexp and String routes are supported";
        }
    }
}

sub find_route {
    my ($self, $url) = @_;
    $self->_find_any_route($url, 'route');
}

sub find_before_route {
    my ($self, $url) = @_;
    $self->_find_any_route($url, 'before_route');
}

sub _find_any_route {
    my ($self, $url, $type) = @_;

    if (my $cb = $self->{$type}->{$url}) {
        return [$cb]
    } else {
        if (@{$self->{'regexp_' . $type}}) {
            for (my $i = 0; $i <= $#{ $self->{'regexp_' . $type} }; $i = $i + 2) {
                my $regexp = $self->{'regexp_' . $type}->[$i];
                if ($url =~ m{$regexp}) {
                    return [
                        $self->{'regexp_' . $type}->[$i + 1],           # cb
                        [grep { defined $_ } ($1, $2, $3, $4, $5, $6)]  # captures
                    ];
                }
            }
        }
    }

    return;
}

package Vesp::Simple::Request;
use common::sense;

use URI::Escape;

=head1 NAME

Vesp::Simple::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=cut

=head2 new

=cut

sub new {
    my ($class, %args) = @_;
    my $self = bless \%args, $class;

    $self;
}

=head2 method

=head2 uri

=head2 hdr

=head2 args

=cut

sub method { $_[0]->{method} }
sub uri    { $_[0]->{uri} }
sub hdr    { $_[0]->{hdr} }
sub args   { $_[0]->{captures} }

=head2 cnt

=head2 done

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

# [TODO] don't be naive :)

sub _parse_body ($) {
    return {
        map {
            split '=', URI::Escape::uri_unescape($_)
        } split '&', $_[0]
    };
}

=head2 params

=cut

sub params {
    my ($self) = @_;

    if (      ! $self->{params} &&
        defined $self->{body}
    ) {
        $self->{params} = _parse_body $self->{body};
    }

    $self->{params};
}

sub session { $_[0]->{session} }

1;
