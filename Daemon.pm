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

$VERSION = 0.51;

# constructor that does NOT daemonize itself
#_______________________________________
sub new {
    my $class = shift;
    my $path  = shift || die('socket_path => REQUIRED!');
    my $self  = { 
        player      => undef,       # instance of Audio:Play:MPG123
        server      => undef,       # instance of IO::Socket::UNIX
        client      => *STDOUT,     # nice for debugging
        socket_path => $path,
        idle        => undef,       # coderef to execute while idle
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
        $self->{player}->statfreq(1);
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
    my $self      = shift;
    $SIG{INT}     =
    $SIG{HUP}     =
    $SIG{PIPE}    =
    $SIG{TERM}    =
    $SIG{__DIE__} = sub { 
        unlink($self->{socket_path});
        exit 1;
    };
}

# repeatedly executed during the idle loop
#_______________________________________
sub idle {
    my $self = shift;
    if (@_) {
        $self->{idle} = shift;
    } else {
        if (defined $self->{idle} && ref($self->{idle}) eq "CODE") {
            $self->{idle}->($self);
        }
    }
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
                $self->idle();
                my $s = $player->state();
                $self->next() if ($s == 0);
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

MP3::Daemon is meant to be subclassed -- not used directly.

    package MP3::Daemon::Simple;

    use strict;
    use vars qw(@ISA);
    use MP3::Daemon;

    @ISA = qw(MP3::Daemon);

Other perl scripts would use MP3::Daemon::Simple like this:

    my $socket_path = "/tmp/mp3d_socket";

    # start up a daemon
    MP3::Daemon::Simple->spawn($socket_path);

    # get a socket that's good for one request to the daemon
    my $client = MP3::Daemon::Simple->client($socket_path);

    print $client @command;

=head1 REQUIRES

=over 4

=item Audio::Play::MPG123

This is used to control mpg123 in remote-mode.

=item IO::Socket::UNIX

This is for client/server communication.

=item IO::Select

I like the OO interface.  I didn't feel like using normal select()
and messing with vec().

=item MP3::Info

This is for getting information from mp3 files.

=item Pod::Usage

This is an optional module that bin/mp3 uses to generate help messages.

=item POSIX

This is just for setsid.

=back

=head1 DESCRIPTION

MP3::Daemon provides a framework for daemonizing mpg123 and
communicating with it using unix domain sockets.  It provides an event
loop that listens for client requests and also polls the mpg123 player
to monitor its state and change mp3s when one finishes.  

The types of client requests available are not defined in
MP3::Daemon.  It is up to subclasses of MP3::Daemon to flesh out
their own protocol for communicating with the daemon.  This was
done to allow people freedom in defining their own mp3 player
semantics.

The following is a short description of the subclasses of 
MP3::Daemon that are packaged with the MP3::Daemon distribution.

=head2 MP3::Daemon::Simple => mp3

This subclass of MP3::Daemon provides a very straightforward mp3
player.  It comes with a client called B<mp3> that you'll find in the
bin/ directory.  It implements a very simple playlist.  It also
implements common commands one would expect from an player, and it
feels very similar to cdcd(1).  It is touted as an mpg123 front-end
for UNIX::Philosophers, because it does not have a Captive User
Interface.

For more information, `perldoc mp3`;

=head2 MP3::Daemon::PIMP => pimp

This subclass of MP3::Daemon has yet to be written.  The significant
difference between M:D:Simple and M:D:PIMP will be the
B<Plaqueluster>.  A Plaqueluster is a pseudorandom playlist that
enforces a user-definable level of non-repetitiveness.  It is also
capable of maintaining a median volume such that all mp3s are played
at the same relative volume.  Never again will you be startled by
having an mp3 recorded at a low volume being followed by an mp3
recorded I<VERY LOUDLY>.

For more information, `perldoc pimp`;

=head1 METHODS

=head2 Server-related Methods

MP3::Daemon relies on unix domain sockets to communicate.  The socket
requires a place in the file system which is referred to as
C<$socket_path> in the following descriptions.

=over 4

=item new $socket_path 

This instantiates a new MP3::Daemon.

    my $mp3d = MP3::Daemon->new("$ENV{HOME}/.mp3/mp3_socket");

=item main

This starts the event loop.  This will be listening to the socket for
client requests while polling mpg123 in times of idleness.  This
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

=item idle

This method has 2 purposes.  When called with a parameter that is a
code reference, the purpose of this method is to specify a code reference
to execute during times of idleness.  When called with no parameters,
the specified code reference will be invoked w/ an MP3::Daemon object
passed to it as its only parameter.  This method will be invoked
at regular intervals while main() runs.

Here is an example that will make the idle handler go to the next song
when there is 8 or fewer seconds left in the current MP3.

    $mp3d->idle (
        sub {
            # an MP3::Daemon::Simple object
            my $self   = shift;

            # an Audio::Play::MPG123 object
            my $player = $self->{player};

            # an arrayref with time-related info
            my $f      = $player->{frame};

            $self->next() if ($f->[2] <= 8);
        }
    );

This is a flexible mechanism for adding additional behaviours during
playback.

=back

=head2 Client Protocol

These methods are usually not invoked directly.  They are invoked when
a client makes a request.  The protocol is very simple.  The first
line is the name of the method.  Each argument to the method is
specified on successive lines.  A final blank line signifies the end
of the request.

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

=head1 SUBCLASSES

When writing a subclass of MP3::Daemon keep the following in mind.

=over 4

=item Writing the constructor

The new() method provided by MP3::Daemon returns a blessed hashref.  Feel
free to add more attributes to the blessed hash as long as you don't
accidentally stomp on the following keys.

=over 12

=item player

This is an instance of Audio::Play::MPG123.

=item server

This is an instance of IO::Socket::UNIX.

=item client

This is another instance of IO::Socket::UNIX that the daemon may
write to in order to reply to a client.

=item socket_path

This is where in the filesystem the unix domain socket is sitting.

=back

=item You must implement a next() method.

The event loop in &MP3::Daemon::main relies on it.  When a song
ends, it will execute $self->next.

=item Only methods prefixed with "_" will be available to clients.

This was to prevent mischievous clients from trying to execute methods
like new(), spawn() or main().  That would have been evil.  By only
allowing methods with names matching /^_/ to be executed, this allows
the author of a daemon to control what the client can and can't
request the daemon to do.

When a client makes a request, the following sequence happens 
in the event loop.

    my @args = $self->readCommand;
    my $do_this = "_" . shift(@args);
    if ($self->can($do_this)) { ... }

If a client requested the daemon to "play", the event loop will ask
itself C<if ($self-E<gt>can('_play'))> before taking any action.

=item Letting us know

If you write a subclass of MP3::Daemon, we (pip and beppu) would be
happy to hear from you.

=back

=head1 DIAGNOSTICS

I need to be able to report errors in the daemon better.
They currently go to /dev/null.  I need to learn how to
use syslog.

=head1 COPYLEFT

Copyleft (!c) 2001 John BEPPU.  All rights reversed.  This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 AUTHOR

John BEPPU <beppu@binq.org>

=head1 SEE ALSO

mpg123(1), Audio::Play::MPG123(3pm), pimp(1p), mpg123sh(1p), mp3(1p)

=cut

# $Id: Daemon.pm,v 1.17 2001/06/05 04:47:27 beppu Exp $
