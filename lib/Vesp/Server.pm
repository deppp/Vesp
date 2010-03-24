package Vesp::Server;
use common::sense;

use Carp;
use Guard;
use List::Util 'first';
use Scalar::Util 'reftype', 'blessed';

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

use HTTP::Headers;

use constant HAS_AIO => eval {
    require IO::AIO;
    require AnyEvent::AIO;
    1;
};

use AnyEvent::AIO;
use IO::AIO;

use constant USE_AIO  => ! $ENV{VESP_NO_AIO};
use constant WITH_AIO => HAS_AIO && USE_AIO;

use constant DEBUG => $ENV{VESP_DEBUG};

my %_status_to_str = (
    200 => 'OK',
    404 => 'NOT FOUND'
);

my %_status_to_num = map {
    $_status_to_str{$_} => $_
} keys %_status_to_str;

my @_supported_headers_parsers = qw/
    HTTP::Parser::XS
/;


=head1 NAME

Vesp::Server - Object oriented interface for Vesp server

=head1 SYNOPSIS

my $vesp = Vesp::Server->new(port => 8888);
$vesp->on_request(sub {
    my ($method, $url, $headers, $body, $done) = @_;
    print "$method request for $url\n";

    my $body = "Got your request";
    $done->(200, {
        'Content-Type'   => 'text/plain',
        'Content-Length' => length $body, 
    }, $body, sub {
        print "Response sent!\n";
    })
});

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item new Vesp::Server port => $port, key => value

The constructor supports these arguments.

=back

=cut

sub new {
    my ($class, %args) = @_;
    my $self = bless \%args, $class;

    if (my $hdras = $self->{headers_as}) {
        if ($hdras !~ m{Scalar|ArrayRef|HashRef}) {
            # means it wants it as an object of some kind
            carp "$hdras is not supported for parsing http headers, please consider using want_headers_handle option"
                if ! grep { $_ eq $hdras } @_supported_headers_parsers;

            require $hdras;
        }
    }

    $self;
}

sub on_request ($$) {
    my ($self, $cb) = @_;
    tcp_server $self->{host}, $self->{port}, $self->_process_request($cb);
}

sub _undef_hdl_cb {
    my ($self, $type) = @_;
    return sub {
        my $hdl = shift;
        undef $hdl;
        $self->{$type}->(@_) if $self->{$type};
    };
}

sub _parse_headers ($) {
    my ($header) = @_;
    my $hdr;

    $header =~ y/\015//d;

    while ($header =~ /\G
        ([^:\000-\037]+):
        [\011\040]*
        ( (?: [^\012]+ | \012 [\011\040] )* )
        \012
    /sgcxo) {
        $hdr->{lc $1} .= ",$2"
    }

    return undef unless $header =~ /\G$/sgxo;

    for (keys %$hdr) {
        substr $hdr->{$_}, 0, 1, '';
        # remove folding:
        $hdr->{$_} =~ s/\012([\011\040])/$1/sgo;
    }

    HTTP::Headers->new(%$hdr);
}

sub _read_head ($$);
sub _read_head ($$) {
    my ($hdl, $cb) = @_;

    $hdl->unshift_read(line => sub {
        my ($hdl, $line) = @_;
        
        if ($line =~ /(\S+) \040 (\S+) \040 HTTP\/(\d+)\.(\d+)/xso) {
            my ($meth, $url, $vm, $vi) = ($1, $2, $3, $4);

            if (! grep { $meth eq $_ } qw/GET HEAD POST PUT DELETE/) {
                $hdl->on_error->("501", "Not Implemented");
            } else {
                $cb->($meth, $url, $vm, $vi);
            }
        } elsif ($line eq '') {
            _read_head $hdl, $cb;
        } else {
            $hdl->on_error->($hdl, "400", "bad request");
        }                
    });
}

sub _read_headers ($$) {
    my $cb = pop;
    my $hdl = shift;
    my %options = @_;
    
    $hdl->unshift_read(line => qr/(?<![^\012])\015\012/o, sub {
        my ($hdl, $data) = @_;
        my $headers = _parse_headers $data
            or print "error with headers" && return;

        if ($options{'want_body_handle'}) {
            $cb->($headers, $hdl);
        } else {
            if (defined $headers->{'content-length'}) {
                $hdl->unshift_read(chunk => $headers->{'content-length'}, sub {
                    my ($hdl, $data) = @_;
                    $cb->($headers, $data);
                });
            } else {
                $cb->($headers, "");
            }
        }
    });
}

sub _response_waiting_cb ($) {
    my ($hdl) = @_;
    return sub {
        my ($status, $hdr, $body, $done) = @_;
        
        my @s = ($status) =~ /\d/ ?
            ($status, $_status_to_str{$status}) :
            ($_status_to_num{$status}, $status);
        
        # [motherfucker...]
        my $hdr_str = "";
        if (blessed $hdr && $hdr->isa('HTTP::Headers')) {
            $hdr_str = $hdr->as_string;
        } elsif (reftype $hdr eq 'HASH') {
            $hdr_str = (join "", map "\u$_: $hdr->{$_}\015\012", grep defined $hdr->{$_}, keys %$hdr);
        } elsif (reftype $hdr eq 'ARRAY') {
            # [TODO] do something
        } elsif (reftype $hdr eq 'SCALAR') {
            $hdr_str = $$hdr;
        } else {
            $hdr_str = $hdr;
        }
        
        $hdl->push_write(
            "HTTP/1.0 $s[0] $s[1]\015\012"
            . $hdr_str
            . "\015\012"
        );
        
        if (WITH_AIO and
            "$body" =~ m{IO::AIO::fd} or
            _is_real_fh($body)
        ) {
            # we can use sendfile if we are under linux >= 2.2
            _sendfile($hdl->fh, $body, 0, -s $body, sub {
                undef $hdl;
                $done->() if $done;
            });
        } else {
            # just do a plain write to filehandle
            $hdl->push_write( (ref $body && reftype($body) eq 'SCALAR' ? $$body : $body) );
            if ($done) {
                # [TODO], here i'm not sure it's the best way
                $hdl->on_drain(sub {
                    undef $hdl;
                    $done->();
                });
            }
        }
        
        # define body...
        # case aio filehandle use IO::AIO::aio_sendfile
        # case string use $hdl->push_write
        # case any other filehandle... see if it does support aio_sendfile
    };
}

sub _process_request {
    my ($self, $cb) = @_;
    return sub {
        my ($fh, $client_host, $client_port) = @_;
        my $hdl; $hdl = Vesp::Server::Handle->new(
            fh          => $fh,
            on_eof      => $self->_undef_hdl_cb('on_close'),
            on_error    => $self->_undef_hdl_cb('on_error'),
            on_timeout  => $self->_undef_hdl_cb('on_timeout'),
            client_host => $client_host,
            client_port => $client_port,
        );
        
        if ($self->{on_connect}) {
            return if ! $self->{on_connect}->($hdl);
        }
        
        _read_head $hdl, sub {
            my ($method, $url, $vm, $vi) = @_;
            _read_headers $hdl, sub {
                my ($headers, $body) = @_;
                $cb->($method, $url, $headers, $body, _response_waiting_cb $hdl);
             };
         };
    };
}

# using this as anon sub (got from Twiggy),
# creates a memleak when recurses

sub _sendfile {
    my ($fh, $body, $offset, $size, $cb) = @_;
    aio_sendfile $fh, $body, $offset, $size - $offset, sub {
        my ($retval) = @_;
        $offset += $retval if $retval > 0;
        if ($offset >= $size) {
            $cb->();
        } else {
            _sendfile($fh, $body, $offset, $size, $cb);
        }
    };
}

# taken from Plack::Util (look it up for docs), and a little bit shorten
# don't want an extra dependency just for one func

sub _is_real_fh ($) {
    my ($fh) = @_;

    my $reftype = reftype($fh);
    return unless $reftype eq 'IO' or
                  $reftype eq 'GLOB' && *{$fh}{IO};
    
    my $m_fileno = $fh->fileno;
    return unless defined $m_fileno or $m_fileno >= 0;

    my $f_fileno = fileno($fh);
    return unless defined $f_fileno or $f_fileno >= 0;

    return 1;
}

package Vesp::Server::Handle;

use common::sense;
use parent 'AnyEvent::Handle';

1;
