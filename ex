#!/usr/bin/perl -w
use strict;
use lib qw(blib/lib);

BEGIN {
    unless (-d "$ENV{HOME}/.mp3") {
        mkdir("$ENV{HOME}/.mp3", 0755);
    }
    unless (-f "Makefile") {
        system "perl *PL";
    }
    system "make";
}

my $subclass = shift || "Pimp";
my $class    = "MP3::Daemon::$subclass";

eval "use $class";
my $mp3d = $class->new("$ENV{HOME}/.mp3/mp3_socket");
$mp3d->main;

# this if for testing the daemon w/o having it fork
# $Id: ex,v 1.1.1.1 2001/01/30 12:47:44 beppu Exp $
