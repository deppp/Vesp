package Vesp::Dispatcher;
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

1;
