package MP3::Daemon::PIMP;

use strict;
use MP3::Daemon;

use vars qw(@ISA $VERSION);
@ISA     = 'MP3::Daemon';
$VERSION = 0.01;

# constructor that does NOT daemonize itself
#_______________________________________
sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    $self->{playlist} = [ ];
    $self->{n}        = undef,

    return $self;
}

"pimp!";

__END__

=head1 NAME

MP3::Daemon::PIMP - the daemon for Pip's Intergallactive Moosex Plaquluster

=head1 SYNOPSIS

Fork a daemon

    MP3::Daemon::PIMP->spawn($socket_path);

Start a server, but don't fork into background

    my $mp3d = MP3::Daemon::PIMP->new($socket_path);
    $mp3d->main;

You're a client wanting a socket to talk to the daemon

    my $client = MP3::Daemon::PIMP->client($socket_path);
    print $client @command;

=head1 REQUIRES

=over 4

=item MP3::Daemon

This is the base class.  It provides the daemonization and
event loop.

=back

=head1 DESCRIPTION

MP3::Daemon::PIMP provides a server that controls mpg123.  Clients
such as mp3(1p) may connect to it and request the server to
manipulate its internal playlists.

=head1 METHODS

=head2 Server-related Methods

MP3::Daemon::PIMP relies on unix domain sockets to communicate.  The
socket requires a place in the file system which is referred to
as C<$socket_path> in the following descriptions.

=over 4

=item new $socket_path 

This instantiates a new MP3::Daemon::PIMP.

    my $mp3d = MP3::Daemon::PIMP->new("$ENV{HOME}/.mp3/mp3_socket");

=item main

This starts the event loop.  This will be listening to the socket
for client requests while polling mpg123 in times of idleness.  This
method will never return.

    $mp3d->main;

=item spawn $socket_path 

This combines C<new()> and C<main()> while also forking itself into
the background.  The spawn method will return immediately to the
parent process while the child process becomes an MP3::Daemon::PIMP that is
waiting for client requests.

    MP3::Daemon::PIMP->spawn("$ENV{HOME}/.mp3/mp3_socket");

=item client $socket_path 

This is a factory method for use by clients who want a socket to
communicate with a previously instantiated MP3::Daemon::PIMP.

    my $client = MP3::Daemon::PIMP->client("$ENV{HOME}/.mp3/mp3_socket");

=back

=head2 Client API

These methods are usually not invoked directly.  They are invoked
when a client makes a request.  The protocol is very simple.
The first line is the name of the method.  Each argument to the
method is specified on successive lines.  A final blank line signifies
the end of the request.

    0   method name
    1   $arg[0]
    .   ...
    n-1 $arg[n-2]
    n   /^$/

Example:

    print $client <<REQUEST;
    play
    5

    REQUEST

This plays $self->{playlist}[5].

=over 8

=item command

=item command

=back

=head1 COPYLEFT

Copyleft (c) 2001 pip.  All rights reversed.  This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 AUTHOR

pip <pip@binq.org>

=head1 SEE ALSO

mpg123(1), Audio::Play::MPG123(3pm), pimp(1p), mpg123sh(1p), mp3(1p)

=cut

# $Id: PIMP.pm,v 1.3 2001/02/05 02:14:13 beppu Exp $
