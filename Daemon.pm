package MP3::Daemon;

use strict;
use vars qw($VERSION);

# controls mpg123
use Audio::Play::MPG123;

# unixy stuff
use POSIX qw(setsid);

# client/server communication
use IO::Socket;
use IO::Select;
#use Fcntl;

$VERSION = 0.05;

# constructor that does NOT daemonize itself
#_______________________________________
sub new {
    my $class = shift;
    my $path  = shift || die('socket_path => REQUIRED!');
    my $self  = { 
        player      => undef,
        server      => undef,
        client      => *STDOUT,   # nice for debugging
        socket_path => $path,
    };
    bless ($self => $class);

    # server socket 
    $self->{server} = IO::Socket::UNIX->new (
        Type   => SOCK_STREAM,
        Local  => $self->{socket_path},
        Listen => SOMAXCONN,
    ) or die($!);
    chmod(0700, $self->{socket_path});
    #fcntl($self->{server}, F_SETFL, O_NONBLOCK);

    # player
    eval {
        $self->{player} = Audio::Play::MPG123->new || die($!);
        $self->{player}->statfreq(10);
    };
    if ($@) {
        unlink($self->{socket_path});
        die($@);
    }
    return $self;
}

# constructor that daemonizes itself
#_______________________________________
sub spawn {
    my $class = shift;

    defined(my $pid = fork)     or die "Can't fork: $!";
    unless ($pid) {
        chdir '/'               or die "Can't chdir to /: $!";
        open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
        open STDOUT, '>/dev/null'
            or die "Can't write to /dev/null: $!";
        setsid                  or die "Can't start a new session: $!";
        open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
    } else {
        # terrible hack to avoid race condition
        select(undef, undef, undef, 0.25);
        return $pid;
    }

    my $self = $class->new(@_);
    $self->main;
}

# return a socket connected to the daemon
#_______________________________________
sub client {
    my $class  = shift;
    my $socket_path = shift;
    my $client = IO::Socket::UNIX->new (
        Type   => SOCK_STREAM,
        Peer   => $socket_path,
    ) or die($!);
    $client->autoflush(1);
    return $client;
}

# destructor
#_______________________________________
sub DESTROY { }

# read from $fh until you get a blank line
#_______________________________________
sub readCommand {
    my $self = shift;
    my $fh   = $self->{client};
    my @line;

    while (<$fh>) {
        chomp;
        /^$/ && last;
        push(@line, $_);
    }
    return @line;
}

# delete the socket before exiting
#_______________________________________
sub setupSignals {
    my $self   = shift;
    $SIG{INT}  =
    $SIG{HUP}  =
    $SIG{PIPE} =
    $SIG{TERM} = sub { 
        unlink($self->{socket_path});
        exit 1;
    };
}

# the event loop
#_______________________________________
sub main {
    my $self   = shift;
    my $server = $self->{server};
    my $player = $self->{player};
    my $mpg123 = $player->IN;
    my $client;

    $self->setupSignals;

    my $s = IO::Select->new;
    $s->add($server);
    $s->add($mpg123);
    my (@ready, $fh);

    while (@ready = $s->can_read) {

        foreach $fh (@ready) {

        # [(    handle request from client    )]

            if ($fh == $server) {
                $client = $server->accept();
                $self->{client} = $client;
                $client->autoflush(1);
                my @args = $self->readCommand;
                my $do_this = "_" . shift(@args);

                if ($self->can($do_this)) {
                    print STDERR "method => $do_this\n";
                    print STDERR map { "| $_\n" } @args;
                    eval { $self->$do_this(@args) };
                    if ($@) { warn($@); }
                } else {
                    print $client "$do_this is not supported.\n";
                }
                close($client);
                $self->{client} = *STDOUT;  # nice for debugging

        # idle ._,-'~`._,-'~`-._,-'~`-._,-'~`-.

            } else {
                $player->poll(0);
                my $s = $player->state;
                $self->next if ($s == 0);
                print "(" . $player->{frame}[2] . ") [$s] \n";
            }
        }
    }
}

1;

__END__

=head1 NAME

MP3::Daemon - a daemon that possesses mpg123

=head1 SYNOPSIS

Fork a daemon

    MP3::Daemon->spawn($socket_path);

Start a server, but don't fork into background

    my $mp3d = MP3::Daemon->new($socket_path)
    $mp3d->main;

You're a client wanting a socket to talk to the daemon

    my $client = MP3::Daemon->client($socket_path);
    print $client @command;

=head1 REQUIRES

=over 4

=item Audio::Play::MPG123

This is used to control mpg123 in remote-mode.

=item Pod::Usage

This is an optional module that bin/mp3 uses to generate help messages.

=item IO::Socket::UNIX

This is for client/server communication.

=item IO::Select

I like the OO interface.  I didn't feel like using normal select()
and messing with vec().

=back

=head1 DESCRIPTION

MP3::Daemon provides a server that controls mpg123.  Clients
such as /bin/mp3 may connect to it and request the server to
manipulate its internal playlists.

=head1 METHODS

=head2 Server-related Methods

MP3::Daemon relies on unix domain sockets to communicate.  The
socket requires a place in the file system which is referred to
as C<$socket_path> in the following descriptions.

=over 4

=item new $socket_path 

This instantiates a new MP3::Daemon.

    my $mp3d = MP3::Daemon->new("$ENV{HOME}/.mp3/mp3_socket");

=item main

This starts the event loop.  This will be listening to the socket
for client requests while polling mpg123 in times of idleness.  This
method will never return.

    $mp3d->main;

=item spawn $socket_path 

This combines C<new()> and C<main()> while also forking itself into
the background.  The spawn method will return immediately to the
parent process while the child process becomes an MP3::Daemon that is
waiting for client requests.

    MP3::Daemon->spawn("$ENV{HOME}/.mp3/mp3_socket");

=item client $socket_path 

This is a factory method for use by clients who want a socket to
communicate with a previously instantiated MP3::Daemon.

    my $client = MP3::Daemon->client("$ENV{HOME}/.mp3/mp3_socket");

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

=head1 DIAGNOSTICS

I need to be able to report errors in the daemon better.
They currently go to /dev/null.  I need to learn how to
use syslog.

=head1 COPYLEFT

Copyleft (c) 2001 John BEPPU.  All rights reversed.  This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 AUTHOR

John BEPPU <beppu@binq.org>

=head1 SEE ALSO

mpg123(1), Audio::Play::MPG123(3pm), pimp(1p), mpg123sh(1p), mp3(1p)

=cut

# $Id: Daemon.pm,v 1.1.1.1 2001/01/30 12:47:44 beppu Exp $
