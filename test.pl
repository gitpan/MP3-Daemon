use Test;
use MP3::Daemon;
use strict;

BEGIN { plan tests => 2 }

ok(1);

my $rc = system("perl -Iblib/lib -c bin/mp3 2> /dev/null");
ok(!$rc);
