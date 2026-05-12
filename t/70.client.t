use strict;
use warnings;
use Test::More;
use Test::Warn;

use lib 'lib';
use lib 't/lib';

use Qmail::Deliverable;
use Qmail::Deliverable::Client;
use QDTest qw(setup_abs_fixtures start_daemon stop_daemon pick_port);

my $fixtures = setup_abs_fixtures();
my ($pid, $port) = start_daemon(qmail_dir => $fixtures);

END {
    stop_daemon($pid) if $pid;
}

$Qmail::Deliverable::Client::SERVER = "127.0.0.1:$port";

subtest 'qmail_local: routes to daemon and returns the local part' => sub {
    is Qmail::Deliverable::Client::qmail_local('alice@sub.example.com'),
       'alice',
       'locals path';
    is Qmail::Deliverable::Client::qmail_local('bob@example.com'),
       'example.com-bob',
       'virtualdomain path';
};

subtest 'qmail_local: undef result on unknown domain' => sub {
    is Qmail::Deliverable::Client::qmail_local('user@nowhere.test'),
       undef,
       'undef passes through (204 from daemon)';
};

subtest 'qmail_local: bare local short-circuits, no HTTP request' => sub {
    # Point SERVER at a closed port. If the client makes an HTTP request,
    # it would warn. The bare-local fast path must skip the request entirely.
    local $Qmail::Deliverable::Client::SERVER = "127.0.0.1:1";
    is Qmail::Deliverable::Client::qmail_local('alice'),
       'alice',
       'bare local returned without contacting the daemon';
};

subtest 'deliverable: numeric status from daemon' => sub {
    is Qmail::Deliverable::Client::deliverable('alice@sub.example.com'),
       0xf1,
       '0xf1 for normal delivery';
    is Qmail::Deliverable::Client::deliverable('user@nowhere.test'),
       0xff,
       '0xff for non-local';
};

subtest 'SERVER as callback' => sub {
    my $hits = 0;
    local $Qmail::Deliverable::Client::SERVER = sub {
        $hits++;
        return "127.0.0.1:$port";
    };
    is Qmail::Deliverable::Client::deliverable('alice@sub.example.com'),
       0xf1,
       'callback resolves to live daemon';
    cmp_ok $hits, '>', 0, 'callback was invoked';
};

subtest 'SERVER = undef -> faked failure, no warning' => sub {
    local $Qmail::Deliverable::Client::SERVER = undef;
    my $rv;
    my @warnings;
    {
        local $SIG{__WARN__} = sub { push @warnings, $_[0] };
        $rv = Qmail::Deliverable::Client::deliverable('alice@sub.example.com');
    }
    is $rv, 0x2f, '0x2f returned';
    is scalar(@warnings), 0, 'no warning emitted on SERVER=undef';
};

subtest 'connection failure -> 0x2f with carp' => sub {
    my $closed_port = pick_port();   # close immediately; nothing listens
    local $Qmail::Deliverable::Client::SERVER = "127.0.0.1:$closed_port";
    my $rv;
    warning_like {
        $rv = Qmail::Deliverable::Client::deliverable('alice@sub.example.com');
    } qr/unreachable|broken/i, 'warning on connection failure';
    is $rv, 0x2f, '0x2f returned';
    like $Qmail::Deliverable::Client::ERROR, qr/unreachable|broken/i,
        '$ERROR is populated';
};

subtest 'qmail_local with connection failure returns ""' => sub {
    my $closed_port = pick_port();
    local $Qmail::Deliverable::Client::SERVER = "127.0.0.1:$closed_port";
    my $rv;
    warning_like {
        $rv = Qmail::Deliverable::Client::qmail_local('alice@sub.example.com');
    } qr/unreachable|broken/i, 'warning on connection failure';
    is $rv, '', 'empty string returned for failure';
};

done_testing();
