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
        require AnyEvent::AIO;
    };
}

use IO::AIO;
use AnyEvent::AIO;

IO::AIO::max_poll_reqs 0; # process all request in poll_cb 
IO::AIO::max_poll_time 0.1; # but limit time by 0.1 to stay responsive

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

my %_header_obj_map = (
    'HTTP::Header' => 'header'
);

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
                if ! grep { $_ eq $hdras } keys %_header_obj_map;

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
    my ($self, $type, $done) = @_;
    return sub {
        my $hdl = shift;
        undef $hdl;

        if ($done) {
            $done->(@_);
        } else {
            $self->{$type}->(@_) if $self->{$type};
        }
    };
}

sub _parse_headers ($$) {
    my ($header, $as) = @_;

    if ($as eq 'ScalarRef') {
        my $cntlen = ($header) =~ m{Content-Length:\s*(\d+)};
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
            if $key eq 'Content-length';
                        
        if (blessed $hdr) {
            my $push = $_header_obj_map{$as};
            $as->$push($key => $val);
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
    
    #for (keys %$hdr) {
    #    substr $hdr->{$_}, 0, 1, '';
    #    # remove folding:
    #    $hdr->{$_} =~ s/\012([\011\040])/$1/sgo;
    #}
    
    #HTTP::Headers->new(%$hdr);

    return ($hdr, $cntlen);
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

sub _read_headers {
    my $cb = pop;
    my $hdl = shift;
    my %options = @_;
    
    $hdl->unshift_read(line => qr/(?<![^\012])\015\012/o, sub {
        my ($hdl, $data) = @_;
        my ($headers, $cntlen) = _parse_headers $data, $options{headers_as}
            or print "error with headers" && return;
        
        if ($options{'want_body_handle'}) {
            Scalar::Util::weaken($hdl);
            $cb->($headers, $hdl);
        } else {
            if ($cntlen) {
                $hdl->unshift_read(chunk => $cntlen, sub {
                    my ($hdl, $data) = @_;
                    $cb->($headers, $data);
                });
            } else {
                $cb->($headers, "");
            }
        }
    });
}

sub _response_waiting_cb {
    my ($self, $hdl) = @_;
    return sub {
        my ($status, $hdr, $body, $done) = @_;

        # note sure about this solution
        $hdl->on_eof($self->_undef_hdl_cb('on_close', $done));
        $hdl->on_error($self->_undef_hdl_cb('on_error', $done));
        $hdl->on_timeout($self->_undef_hdl_cb('on_timeout', $done));
        
        my @s = ($status) =~ /\d/ ?
            ($status, $_status_to_str{$status}) :
            ($_status_to_num{$status}, $status) ;
        
        # [motherfucker...] redo when have time
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
        
        $hdl->push_write(
            "HTTP/1.0 $s[0] $s[1]\015\012"
            . $hdr_str
            . "\015\012"
        );
        
        if (WITH_AIO and
            "$body" =~ m{IO::AIO::fd} or
            _is_real_fh($body)
        ) {
            # use sendfile in future, for
            # now use push_read :)

             # _push_data_from_fh($hdl, $body, sub {
             #     undef $hdl;
             #     $done->() if $done;                   
             # });
             # return;
             
            # first of all we want to be sure that headers are already there...
            # then we can start our dirty hacks
            $hdl->on_drain(sub {
                # we can use sendfile if we are under linux >= 2.2
                _sendfile($hdl, $body, 0, -s $body, sub {
                    undef $hdl;
                    $done->() if $done;
                });
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

sub _process_request {
    my ($self, $cb) = @_;

    my %https;
    if ( $self->{https} ) {
        $https{tls} = 'accept';
        $https{tls_ctx} = $self->{https}            
    }
    
    return sub {
        my ($fh, $client_host, $client_port) = @_;
        my $hdl; $hdl = AnyEvent::Handle->new(
            fh          => $fh,
            on_eof      => $self->_undef_hdl_cb('on_close'),
            on_error    => $self->_undef_hdl_cb('on_error'),
            on_timeout  => $self->_undef_hdl_cb('on_timeout'),
            client_host => $client_host,
            client_port => $client_port,
            %https
        );
        
        if ($self->{on_connect}) {
            return if ! $self->{on_connect}->($hdl);
        }
        
        _read_head $hdl, sub {
            my ($method, $url, $vm, $vi) = @_;
            _read_headers $hdl,
                want_body_handle => $self->{want_body_handle},
                headers_as       => $self->{headers_as},
                sub {
                    my ($headers, $body) = @_;
                    $cb->($method, $url, $headers, $body, $self->_response_waiting_cb($hdl));
                };
         };
    };
}

sub _sendfile {
    my ($hdl, $in_fh, $offset, $size, $cb) = @_;

    aio_sendfile $hdl->fh, $in_fh, $offset, $size - $offset, sub {
        my ($retval) = @_;
        $offset += $retval if $retval > 0;
                
        if ($retval == -1 && ! ($! == EAGAIN || $! == EINTR)) {
            # does callback destroy $hdl enough?
            $hdl->{on_error}->($hdl, -1, "IO::AIO sendfile error: $!");
            return;
        }        
                        
        if ($offset >= $size) {
            $cb->();
        } else {
            _sendfile($hdl, $in_fh, $offset, $size, $cb);
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
