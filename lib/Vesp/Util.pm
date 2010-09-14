package Vesp::Util;
use common::sense;
use bytes;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(redirect sendfile respond);

use Carp;
use Fcntl;

use AnyEvent::AIO;
use IO::AIO;

=head1 NAME

Vesp::Util - various utils for Vesp server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 redirect

=cut

sub redirect {
    my $js_redirect = sub {
        my ($url) = @_;
        return "";
    };
        
    if (scalar @_ == 1) {
        my $url = shift;
        return respond(
            302,
            { Location => $url },
            $js_redirect->($url)
        );
    } else {
        carp "any other param except url is not implemented";
        #my (%args) = @_;
        #return respond(
        #    302,
        #    {{ %{$args{hdr}}, 'Location' => $args{url} },
        #    $args{body} || $js_redirect->($args{url})
        #);
    }
}

sub sendfile ($$@) {
    my ($file, $done, $cb) = @_;
    
    # [TODO] optimize
    
    aio_open $file, O_RDONLY, 0, sub {
        my $fh = shift
            or die;
        
        $done->(body => $fh, cb => sub {
            aio_close $fh, sub { close $fh };
        });
    };
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

=head2 respond

=cut

sub respond ($;@) {
    my $body = pop;
    my ($status, $hdr) = @_;
    
    $hdr    ||= {};
    $status ||= 200;
    
    return $status, {
        'Date'           => _time2str,
        'Content-Lenght' => ref($body) ? bytes::length($$body) : bytes::length($body),
        'Content-Type'   => 'text/html',
        %$hdr
    }, $body;
}

=head1 AUTHOR

Mikhail Maluyk <mikhail.maluyk@gmail.com> 2010

=cut

1;
