package Vesp::Server;
use common::sense;

use Carp;
use Guard;
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

use IO::AIO;
use AnyEvent::AIO;

use constant USE_AIO  => ! $ENV{VESP_NO_AIO};
use constant WITH_AIO => HAS_AIO && USE_AIO;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
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

sub _read_headers ($$) {
    my ($hdl, $cb) = @_;
    $hdl->unshift_read(line => qr/(?<![^\012])\015\012/o, sub {
        my ($hdl, $data) = @_;
        my $headers = _parse_headers $data
            or print "error with headers" && return;
        
        if (defined $headers->{'content-length'}) {
            $hdl->unshift_read(chunk => $headers->{'content-length'}, sub {
                my ($hdl, $data) = @_;
                $cb->($headers, $data);
            });
        } else {
            $cb->($headers, "");
        }
    });
}

sub _read_head ($$);
sub _read_head ($$) {
    my ($hdl, $cb) = @_;

    $hdl->unshift_read(line => sub {
        my ($hdl, $line) = @_;
        #print "line: $line\n";
        
        if ($line =~ /(\S+) \040 (\S+) \040 HTTP\/(\d+)\.(\d+)/xso) {
            my ($meth, $url, $vm, $vi) = ($1, $2, $3, $4);

            if (! grep { $meth eq $_ } qw/GET HEAD POST PUT DELETE/) {
                #$self->error (501, "not implemented",
                #              { Allow => "GET,HEAD,POST" });
                return;
            }

            if ($vm >= 2) {
                #$self->error (506, "http protocol version not supported");
                return;
            }

            #$self->{last_header} = [$meth, $url];
            #$self->push_header;
            $cb->($meth, $url, $vm, $vi);
                        
        } elsif ($line eq '') {
            # ignore empty lines before requests, this prevents
            # browser bugs w.r.t. keep-alive (according to marc lehmann).
            _read_head $hdl, $cb;
        } else {
            #$self->error (400 => 'bad request');
        }                
    });
}

my %_status_to_str = (
    200 => 'OK',
    404 => 'NOT FOUND'
);

my %_status_to_num = map {
    $_status_to_str{$_} => $_
} keys %_status_to_str;

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
            my $offset = 0;
            my $size = -s $body;
            my $sendfile; $sendfile = sub {
                aio_sendfile $hdl->fh, $body, $offset, $size - $offset, sub {
                    my ($retval) = @_;
                    $offset += $retval if $retval > 0;
                    if ($offset >= $size) {
                        undef $hdl;
                        $done->() if $done;
                    } else {
                        $sendfile->();
                    }
                };
            };
            $sendfile->();
        } else {
            # just do a plain write to filehandle
            $hdl->push_write( (ref $body && reftype($body) eq 'SCALAR' ? $$body : $body) );
            if ($done) {
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
        my $hdl; $hdl = AnyEvent::Handle->new(fh => $fh);

        _read_head $hdl, sub {
            my ($method, $url, $vm, $vi) = @_;
            _read_headers $hdl, sub {
                my ($headers, $body) = @_;
                
        #         my %env = ();

        #         # [TODO] we don't want to do this,
        #         # instead build it as %env from scratch

        #         if ($self->{psgi}) {
        #             #$env{'REQUEST_METHOD'} = $method;
        #             #$env{'REQUEST_URI'} = $url;
        #             #$env{'HTTP_REFERER'} = $headers->{};
        #             #$env{'HTTP_USER_AGENT'} = $headers->{'User-Agent'};
        #             #$env{'PATH_INFO'} = $url; # [TODO] CHECK
        #             #$env{'QUERY_STRING'};
        #             #$env{'SERVER_PROTOCOL'} = "HTTP/$vm.$vi";
                    
        #             #$env{'psgi.multiprocess'} = "";
        #             #$env{'psgi.multithreaded'} = "";
        #             #$env{'psgi.nonblocking'} = 1;

        #             $cb->(\%env, _response_waiting_cb $hdl);
        #         } else {

                $cb->($method, $url, $headers, $body, _response_waiting_cb $hdl);
        #         }
             };
         };
    };
}

sub on_request ($$) {
    my ($self, $cb) = @_;
    tcp_server $self->{host}, $self->{port}, $self->_process_request($cb);
}

1;