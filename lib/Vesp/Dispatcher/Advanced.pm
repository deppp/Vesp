package Vesp::Dispatcher::Advanced;
use common::sense;
use Carp 'croak';
use base 'Vesp::Dispatcher::Basic';

my @OK_ARGS = qw/method headers body/;

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;

    $self->{route} = [];
    $self->{before_route} = [];
    
    $self->{regexp_route} = [];
    $self->{regexp_before_route} = [];
    
    $self;
}

sub _add_any_route {
    my $cb   = pop;
    my ($self, $routes, $type, %args) = @_;

    $routes = [ $routes ]
        if ! ref $routes or ref $routes eq 'Regexp';

    foreach my $route (@$routes) {
        if (ref $route && ref $route eq 'Regexp') {
            push @{ $self->{'regexp_' . $type} }, {
                %args,
                cb => $cb,
                route => $route
            };
        } elsif (! ref $route) {
            push @{ $self->{$type} }, {
                %args,
                cb => $cb,
                route => $route
            };
        } else {
            die "Only Regexp and String routes are supported";
        }
    }
}

sub _find_any_route {
    my ($self, $url, $type, $method, $hdr, $body) = @_;

    my $check_args = sub {
        my ($entry, $method, $hdr, $body) = @_;

        return if $entry->{method} and
                $entry->{method} ne $method;
        
        if ($entry->{headers}) {
        HDR: while (my ($h, $v) = each %{ $entry->{headers} }) {
                $h = lc($h);
                foreach my $chk (keys %{$hdr}) {
                    if ($h eq lc($chk) and
                        $hdr->{$chk} =~ m{$v}
                    ) {
                        next HDR;
                    }
                }
                
                return;
            }
        }
        
        return if $entry->{body} and
                $body !~ m/$entry->{body}/;

        return 1;
    };

    # simple URL routes
    foreach my $entry (@{ $self->{$type} }) {
        next if $url ne $entry->{route};
        
        $check_args->($entry, $method, $hdr, $body) ?
            return [ $entry->{cb} ] :
            next ;
    }

    # regex routes
    foreach my $entry (@{ $self->{'regexp_' . $type} }) {
        
        $url =~ m/$entry->{route}/ ?
            my @captures = grep { defined $_ } ($1, $2, $3, $4, $5, $6) :
            next ;
        
        $check_args->($entry, $method, $hdr, $body) ?
            return [ $entry->{cb}, \@captures ] :
            next ;
    }
}

1;
