package Vesp::Server;
use common::sense;

use Carp;
use Guard;
use List::Util 'first';
use Scalar::Util 'reftype', 'blessed', 'weaken';
use Errno qw(EAGAIN EINTR);

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

use HTTP::Headers;

BEGIN {
    use constant HAS_AIO => eval {
        require IO::AIO;
        IO::AIO->import;
        require AnyEvent::AIO;
        1;
    };
}

use constant USE_AIO  => ! $ENV{VESP_NO_AIO};
use constant WITH_AIO => HAS_AIO && USE_AIO;

if (WITH_AIO) {
    IO::AIO::max_poll_reqs 0;   # process all request in poll_cb 
    IO::AIO::max_poll_time 0.1; # but limit time by 0.1 to stay responsive
}

use constant DEBUG => $ENV{VESP_DEBUG};

my %_status_to_str = (
    200 => 'OK',
    404 => 'Not Found',
    503 => 'Service Unavailable'
);

my %_status_to_num = map {
    $_status_to_str{$_} => $_
} keys %_status_to_str;

my %_header_obj_map = (
    'HTTP::Headers' => 'header'
);

my @_clients = ();

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
            croak "$hdras is not supported for parsing http headers"
                if ! grep { $_ eq $hdras } keys %_header_obj_map;
            
            eval "require $hdras" || croak @$;
        }
    }
    
    # [TODO]
    # if (my $compress = $self->{compress}) {
    #     eval { require Compress::Zlib };
    # }
    
    $self->{_guard} = AnyEvent::Util::guard {
        undef $self->{_tcp_server_guard};
        foreach (@_clients) {
            # [TODO]
        }
    };
    
    $self;
}

sub _parse_headers ($$) {
    my ($header, $as) = @_;

    if ($as eq 'ScalarRef') {
        my ($cntlen) = $header =~ /Content-Length:\s*(\d+)/;
        return (\$header, $cntlen); 
    }
    
    $as ||= 'HashRef';
    $header =~ y/\015//d;
    
    my $hdr;
    my $cntlen;
    
    if ($as !~ m{HashRef|ArrayRef}) {
        $hdr = $as->new;
    }
    
    while ($header =~ /\G
        ([^:\000-\037]+):
        [\011\040]*
        ( (?: [^\012]+ | \012 [\011\040] )* )
        \012
    /sgcxo) {
        my ($key, $val) = ($1, $2);
        $key =~ s{\012([\011\040])}{$1}sgo;

        $cntlen = $val
            if lc($key) eq 'content-length';
                        
        if (blessed $hdr) {
            my $push = $_header_obj_map{$as};
            $hdr->$push($key => $val);
        } else {
            if ($as eq 'HashRef') {
                $hdr->{lc $key} = $val;
            } elsif ($as eq 'ArrayRef') {
                push @$hdr, (lc($key) => $val);
            } else {
                croak "Can't understand required headers format";
            }
        }
    }
    
    return undef unless $header =~ /\G$/sgxo;
    return ($hdr, $cntlen);
}

sub _read_head ($$);
sub _read_head ($$) {
    my ($state, $cb) = @_;

    $state->{hdl}->unshift_read(line => sub {
        if ($_[1] =~ /(\S+) \040 (\S+) \040 HTTP\/(\d+)\.(\d+)/xso) {
            my ($meth, $url, $vm, $vi) = ($1, $2, $3, $4);
            
            if (! grep { $meth eq $_ } qw/GET HEAD POST PUT DELETE/) {
                #$hdl->on_error->("501", "Not Implemented");
            } else {
                $cb->($meth, $url, $vm, $vi);
            }
        } elsif ($_[1] eq '') {
            _read_head $state, $cb;
        } else {
            # [BUG] try https request on non https server
            #$hdl->on_error->($hdl, "400", "bad request");
        }                
    });
}

sub _read_headers {
    my $cb = pop;
    my $state = shift;
    my %options = @_;
    
    $state->{hdl}->unshift_read(line => qr/(?<![^\012])\015\012/o, sub {
        my ($headers, $cntlen) = _parse_headers $_[1], $options{headers_as}
            or print "error with headers" && return;
        
        if ($options{'want_body_handle'}) {
            $_[0]->on_eof (undef);
            $_[0]->on_error (undef);
            $_[0]->on_read  (undef);
            
            $cb->($headers, $_[0]);
        } else {
            if ($cntlen) {
                $_[0]->unshift_read(chunk => $cntlen, sub {
                    $cb->($headers, $_[1]);
                });
            } else {
                $cb->($headers, "");

            }
        }
    });
}

sub _write_http_res {
    my $state = shift;
    my ($status, $hdr, $body, $done) = @_;

    my @s = ($status) =~ /\d/ ?
        ($status, $_status_to_str{$status}) :
        ($_status_to_num{$status}, $status) ;
        
    my $hdr_str = "";
    if (blessed $hdr && $hdr->isa('HTTP::Headers')) {
        $hdr_str = $hdr->as_string("\015\012");
    } elsif (reftype $hdr eq 'HASH') {
        $hdr_str = (join "", map "\u$_: $hdr->{$_}\015\012", grep defined $hdr->{$_}, keys %$hdr);
    } elsif (reftype $hdr eq 'ARRAY') {
        # [TODO] do something
    } elsif (reftype $hdr eq 'SCALAR') {
        $hdr_str = $$hdr;
    } else {
        $hdr_str = $hdr;
    }
        
    $state->{hdl}->push_write(
        "HTTP/1.0 $s[0] $s[1]\015\012"
        . $hdr_str
        . "\015\012"
    );
        
    if (WITH_AIO and
        ("$body" =~ m{IO::AIO::fd} or _is_real_fh($body))
    ) {
        # [BUG] if tls enabled we have a bug here
        #if ($self->{https}) {
            # read whole fh and push write
        #}
        
        # first of all we want to be sure that headers are already there...
        # then we can start our dirty hacks
        $state->{hdl}->on_drain(sub {
            # we can use sendfile if we are under linux >= 2.2
            _sendfile($state->{fh}, $body, 0, -s $body, sub {
                $state->{hdl}->destroy if $state->{hdl};
                undef $state;
                
                $done->() if $done;
            });
        });
    } else {
        # just do a plain write to filehandle
        $state->{hdl}->push_write( (ref $body && reftype($body) eq 'SCALAR' ? $$body : $body) );
        $state->{hdl}->on_drain(sub {
            $state->{hdl}->destroy if $state->{hdl};
            undef $state;
                
            $done->() if $done;
        });
    }
}

sub _push_data_from_fh {
    my ($hdl, $fh, $cb) = @_;
    _write_data($hdl, $fh, 0, -s $fh, $cb);
}

sub _write_data {
    my ($hdl, $fh, $offset, $size, $cb) = @_;
    
    my $buffer = "";
    aio_read $fh, $offset, 8192, $buffer, 0, sub {
        my ($retval) = @_;
        $offset += $retval if $retval > 0;
        $hdl->push_write($buffer);
                
        if ($offset >= $size) {
            $cb->();
        } else {
            _write_data($hdl, $fh, $offset, $size, $cb);
        }
    }
}

sub on_request ($$) {
    my ($self, $cb) = @_;
    
    my %tls;
    if ( $self->{tls} ) {
        $tls{tls} = 'accept';
        $tls{tls_ctx} = delete $self->{tls}            
    }

    my %args;
    $args{timeout} = $self->{timeout} || 300;
        
    $self->{_tcp_server_guard} = tcp_server $self->{host}, $self->{port}, sub {
        my %state = (
            fh          => $_[0],
            client_host => $_[1],
            client_port => $_[2]
        );
        
        $state{hdl} = Vesp::Server::Handle->new(%state, %tls, %args);
        
        $state{hdl}->on_error(sub {
            %state = ();
            $cb->(undef, undef, undef, $_[2], undef);
        });
        
        $state{hdl}->on_eof(sub {
            %state = ();
            $cb->(undef, undef, undef, "Unexpected end-of-file", undef);
        });
        
        Scalar::Util::weaken (my $s = \%state);
                
        _read_head $s, sub {
            #my ($method, $url, $vm, $vi) = @_;
            $state{method} = shift;
            $state{url}    = shift;
            _read_headers $s,
                want_body_handle => $self->{want_body_handle},
                headers_as       => $self->{headers_as},
                sub {
                    #my ($headers, $body) = @_;
                    $cb->($state{method}, $state{url}, @_, sub {
                        #my ($status, $hdr, $body, $done) = @_;
                        _write_http_res($s, @_);
                    });
                };
         };
    };
}

sub _sendfile {
    my ($out_fh, $in_fh, $offset, $size, $cb) = @_;

    aio_sendfile $out_fh, $in_fh, $offset, $size - $offset, sub {
        my ($retval) = @_;
        $offset += $retval if $retval > 0;
                
        if ($retval == -1 && ! ($! == EAGAIN || $! == EINTR)) {
            # does callback destroy $hdl enough?
            # $hdl->{on_error}->($hdl, -1, "IO::AIO sendfile error: $!");
            return;
        }        
                        
        if ($offset >= $size) {
            $cb->();
        } else {
            _sendfile($out_fh, $in_fh, $offset, $size, $cb);
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
