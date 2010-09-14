package Vesp::Static;
use common::sense;
use Carp 'croak';

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = 'vesp_configure_static';

use Vesp::Simple 'vesp_route';
use Vesp::Util 'sendfile';

sub vesp_configure_static (@) {
    my (%args) = @_;

    croak 'Static dir required'
        if ! $args{dir};

    my $err_cb = $args{err_cb};
    my $route  = $args{route} || 'static/';
    
    vesp_route qr{^/$route(.+)$} => sub {
        my ($req) = @_;

        $err_cb->('No args'), return
            if ! @{ $req->args } && $err_cb;

        my $path = $req->args->[0];
        my $full_path = $args{dir} . '/' . $path;

        sendfile $full_path, $req->done;
    };
}

1;
