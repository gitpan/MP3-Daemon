use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'          => 'MP3::Daemon',
    'VERSION_FROM'  => 'Daemon.pm',
    'ABSTRACT_FROM' => 'Daemon.pm',
    'EXE_FILES'     => [ qw(bin/mp3) ],
    'dist'          => {
        'PREOP'     => 'pod2text bin/mp3 | tee README > $(DISTVNAME)/README',
        'COMPRESS'  => 'gzip -9v',
        'SUFFIX'    => '.gz',
    },
    'PREREQ_PM'     => {
        'Audio::Play::MPG123' => 0,
        'POSIX'               => 0,
        'IO::Socket'          => 0,
        'Pod::Usage'          => 0,
    },
);

# vim:syntax=perl
# $Id: Makefile.PL,v 1.1.1.1 2001/01/30 12:47:44 beppu Exp $
