package Vesp::Dispatcher::Basic;
use common::sense;
use base 'Vesp::Dispatcher';

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
    my ($self, $url, $method, $hdr, $body) = @_;
    $self->_find_any_route($url, 'route', $method, $hdr, $body);
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

1;
