
use common::sense;
use Benchmark ':all';

my $header = "Content-Type: application\nContent-Length: 1999";

my $count = 100_000;

timethese ($count, {
    Regex1 => sub {
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
        
        $hdr
    },
    Regex2 => sub {
        my %hdr;

        $header =~ y/\015//d;
        
        while ($header =~ /\G
            ([^:\000-\037]+):
            [\011\040]*
            ( (?: [^\012]+ | \012 [\011\040] )* )
            \012
        /sgcxo) {
            $hdr{lc $1} .= "$2"
        }
        
        return undef unless $header =~ /\G$/sgxo;
        
        #for (keys %$hdr) {
        #    substr $hdr->{$_}, 0, 1, '';
        #    # remove folding:
        #    $hdr->{$_} =~ s/\012([\011\040])/$1/sgo;
        #}
        
        \%hdr
    }
});
