package Vesp::Body;
use bytes;
use common::sense;

use AnyEvent::AIO;
use IO::AIO;
use IO::AIO::Temp;

use List::Util 'first';

use HTTP::Message;

our $TYPES = {
    'application/octet-stream'          => 'Vesp::Body::OctetStream',
    'application/x-www-form-urlencoded' => 'Vesp::Body::UrlEncoded',
    'multipart/form-data'               => 'Vesp::Body::MultiPart',
};

=head1 NAME

Vesp::Body - simple http body parser

=head1 SYNOPSIS



=head1 DESCRIPTION

Hacked from HTTP::Body mostly

=cut

sub new {
    my ($class, %args) = @_;
    
    my $ct   = lc $args{ctype};
    my $type = first { index( $ct, $_ ) >= 0 } keys %{$TYPES};
    
    my $to   = $TYPES->{ $type || 'application/octet-stream' };
    my $self = bless {
        len   => $args{length},
        ctype => $args{ctype}
    }, $to;

    $self->{params} = {};
    $self;
}

sub init {
    my ($self, $hdl, $cb) = @_;

    if ($self->{len}) {
        # [BUG] it might be a race condition here
        $hdl->on_eof(sub {
            $cb->($self);
        });
        
        $hdl->on_read(sub {
            my $buf = delete $hdl->{rbuf};
            $self->_add($buf, sub {});

            $self->{len} -= length $buf;
            
            if ($self->{len} <= 0) {
                $hdl->on_read(undef);
                $hdl->on_eof(undef);
                $cb->($self);
            }
        });
    } else {
        $cb->();
    }
}

sub _add {
    my ($self, $data, $cb) = @_;
        
    if ( defined $data ) {
        $self->{length} += length( $data );
        $self->{buffer} .= $data;
    }

    $self->_spin(sub {});
}

sub body  { $_[0]->{body} }

=head2 params $key

Access body params

=cut

sub params ($$) {
    my $self = shift;
    my $key  = shift;
    
    if (@_) {
        my $value = shift;
        if (exists $self->{params}->{$key}) {
            for ( $self->{params}->{$key} ) {
                $_ = [$_] unless ref($_) eq "ARRAY";
                push( @$_, $value );
            }
        } else {
            $self->{params}->{$key} = $value;
        }
    } else {
        if ($key) {
            return $self->{params}->{$key};
        } else {
            return $self->{params};
        }
    }
}

=head2 uploads

unimplemented

=cut

sub uploads {
    my $self = shift;
    
}

package Vesp::Body::OctetStream;
use common::sense;
use base 'Vesp::Body';

sub _spin {
    my ($self, $cb) = @_;

    # aio_tempfile sub {
    #     my ($fh, $filename, $guard) = @_;
    #     $self->{body} = $filename;
    #     $self->{_tmpfile_guard} = $guard;

    #     my $buf = $body->{buffer};
                
    #     aio_write $fh, 0, bytes::length($buf), $buf, 0, sub {
    #         # [BUG] check...
    #         $body->{state} = 'done';
    #         $cb->();
    #     };
    # };
}

package Vesp::Body::UrlEncoded;
use common::sense;
use base 'Vesp::Body';

our $DECODE = qr/%([0-9a-fA-F]{2})/;

our %hex_chr;

for my $num ( 0 .. 255 ) {
    my $h = sprintf "%02X", $num;
    $hex_chr{ lc $h } = $hex_chr{ uc $h } = chr $num;
}

sub _spin {
    my ($self, $cb) = @_;

    #return unless $self->length == $self->content_length;

    $self->{buffer} =~ s/\+/ /g;

    for my $pair ( split( /[&;](?:\s+)?/, $self->{buffer} ) ) {
        
        my ( $name, $value ) = split( /=/, $pair , 2 );
        
        next unless defined $name;
        next unless defined $value;
        
        $name  =~ s/$DECODE/$hex_chr{$1}/gs;
        $value =~ s/$DECODE/$hex_chr{$1}/gs;

        $self->params($name, $value);
    }
    
    $self->{buffer} = '';
    
    $cb->();
}

package Vesp::Body::MultiPart;
use common::sense;
use base 'Vesp::Body';

sub _spin {
    my ($self, $cb) = @_;

    unless ( $self->{ctype} =~ /boundary=\"?([^\";]+)\"?/ ) {
        my $content_type = $self->{ctype};
        Carp::croak("Invalid boundary in content_type: '$content_type'");
    }

    $self->{boundary} = $1;
    $self->{state} = 'preamble';
        
    while (1) {
        if ( $self->{state} =~ /^(preamble|boundary|header|body)$/ ) {
            my $method = "parse_$1";
            $cb->(), return unless $self->$method;
        }

        else {
            Carp::croak('Unknown state');
        }
    }
    
    #my @parse_methods = qw/preamble boundary header body/;
    #foreach my $mpart (@parse_methods) {
    #    my $method = 'parse_' . $mpart;
    #    $cb->(), return
    #        if ! $self->$method;
    #}
    
    #
    $cb->();
}

sub boundary {
    return shift->{boundary};
}

sub boundary_begin {
    return "--" . shift->boundary;
}

sub boundary_end {
    return shift->boundary_begin . "--";
}

sub crlf () {
    return "\x0d\x0a";
}

sub delimiter_begin {
    my $self = shift;
    return $self->crlf . $self->boundary_begin;
}

sub delimiter_end {
    my $self = shift;
    return $self->crlf . $self->boundary_end;
}

sub parse_preamble {
    my $self = shift;
    
    my $index = index( $self->{buffer}, $self->boundary_begin );

    unless ( $index >= 0 ) {
        return 0;
    }

    # replace preamble with CRLF so we can match dash-boundary as delimiter
    substr( $self->{buffer}, 0, $index, $self->crlf );

    $self->{state} = 'boundary';

    return 1;
}

sub parse_boundary {
    my $self = shift;

    if ( index( $self->{buffer}, $self->delimiter_begin . $self->crlf ) == 0 ) {

        substr( $self->{buffer}, 0, length( $self->delimiter_begin ) + 2, '' );
        $self->{part}  = {};
        $self->{state} = 'header';

        return 1;
    }

    if ( index( $self->{buffer}, $self->delimiter_end . $self->crlf ) == 0 ) {

        substr( $self->{buffer}, 0, length( $self->delimiter_end ) + 2, '' );
        $self->{part}  = {};
        $self->{state} = 'done';

        return 0;
    }

    return 0;
}

sub parse_header {
    my $self = shift;

    my $crlf  = $self->crlf;
    my $index = index( $self->{buffer}, $crlf . $crlf );

    unless ( $index >= 0 ) {
        return 0;
    }

    my $header = substr( $self->{buffer}, 0, $index );

    substr( $self->{buffer}, 0, $index + 4, '' );

    my @headers;
    for ( split /$crlf/, $header ) {
        if (s/^[ \t]+//) {
            $headers[-1] .= $_;
        }
        else {
            push @headers, $_;
        }
    }

    my $token = qr/[^][\x00-\x1f\x7f()<>@,;:\\"\/?={} \t]+/;

    for my $header (@headers) {

        $header =~ s/^($token):[\t ]*//;

        ( my $field = $1 ) =~ s/\b(\w)/uc($1)/eg;

        if ( exists $self->{part}->{headers}->{$field} ) {
            for ( $self->{part}->{headers}->{$field} ) {
                $_ = [$_] unless ref($_) eq "ARRAY";
                push( @$_, $header );
            }
        }
        else {
            $self->{part}->{headers}->{$field} = $header;
        }
    }

    $self->{state} = 'body';

    return 1;
}

sub parse_body {
    my $self = shift;

    my $index = index( $self->{buffer}, $self->delimiter_begin );

    if ( $index < 0 ) {

        # make sure we have enough buffer to detect end delimiter
        my $length = length( $self->{buffer} ) - ( length( $self->delimiter_end ) + 2 );

        unless ( $length > 0 ) {
            return 0;
        }

        $self->{part}->{data} .= substr( $self->{buffer}, 0, $length, '' );
        $self->{part}->{size} += $length;
        $self->{part}->{done} = 0;

        $self->handler( $self->{part} );

        return 0;
    }

    $self->{part}->{data} .= substr( $self->{buffer}, 0, $index, '' );
    $self->{part}->{size} += $index;
    $self->{part}->{done} = 1;

    $self->handler( $self->{part} );

    $self->{state} = 'boundary';

    return 1;
}

sub handler {
    my ( $self, $part ) = @_;

    unless ( exists $part->{name} ) {

        my $disposition = $part->{headers}->{'Content-Disposition'};
        my ($name)      = $disposition =~ / name="?([^\";]+)"?/;
        my ($filename)  = $disposition =~ / filename="?([^\"]*)"?/;
        # Need to match empty filenames above, so this part is flagged as an upload type

        $part->{name} = $name;

        #if ( defined $filename ) {
        #    $part->{filename} = $filename;

        #    if ( $filename ne "" ) {
        #        my $fh = File::Temp->new( UNLINK => 0, DIR => $self->tmpdir );

        #        $part->{fh}       = $fh;
        #        $part->{tempname} = $fh->filename;
        #    }
        #}
    }

    #if ( $part->{fh} && ( my $length = length( $part->{data} ) ) ) {
    #    $part->{fh}->write( substr( $part->{data}, 0, $length, '' ), $length );
    #}
    
    if ( $part->{done} ) {

        #if ( exists $part->{filename} ) {
        #    if ( $part->{filename} ne "" ) {
        #        $part->{fh}->close if defined $part->{fh};

        #        delete @{$part}{qw[ data done fh ]};

        #        $self->upload( $part->{name}, $part );
        #    }
        #}
        #else {
            $self->params( $part->{name}, $part->{data} );
        #}
    }
}

1;
