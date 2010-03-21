package Vesp;
use common::sense;

use Carp ();
use Vesp::Server;

require Exporter;

our @ISA = 'Exporter';
our @EXPORT = 'http_server';

our $VERSION = '0.01';

sub http_server ($$@) {
    my $cb = pop;
    my ($host, $port, %args) = @_;

    my $server = Vesp::Server->new(
        host => $host,
        port => $port,
        %args
    );
    
    $server->on_request($cb);

    defined wantarray && $server->{_guard};
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Vesp - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Vesp;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Vesp, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Mikhail, E<lt>depp@nonetE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Mikhail

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
