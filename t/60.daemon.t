use strict;
use warnings;
use Test::More;
use LWP::UserAgent;
use URI::Escape qw(uri_escape);

use lib 'lib';
use lib 't/lib';

use Qmail::Deliverable;
use QDTest qw(setup_abs_fixtures start_daemon stop_daemon);

my $fixtures = setup_abs_fixtures();
my ($pid, $port) = start_daemon(qmail_dir => $fixtures);

my $ua = LWP::UserAgent->new(timeout => 5);
my $base = "http://127.0.0.1:$port";

sub GET { $ua->get("$base/$_[0]") }

END {
    stop_daemon($pid) if $pid;
}

subtest 'qmail_local: known local address' => sub {
    my $r = GET("qd1/qmail_local?" . uri_escape('alice@sub.example.com'));
    is $r->code, 200, '200 OK';
    is $r->content, 'alice', 'body is the local part';
};

subtest 'qmail_local: virtualdomain' => sub {
    my $r = GET("qd1/qmail_local?" . uri_escape('bob@example.com'));
    is $r->code, 200, '200 OK';
    is $r->content, 'example.com-bob', 'prepend applied';
};

subtest 'qmail_local: unknown domain -> 204 UNDEF' => sub {
    my $r = GET("qd1/qmail_local?" . uri_escape('user@nowhere.test'));
    is $r->code, 204, '204 No Content for undef result';
};

subtest 'deliverable: known address' => sub {
    my $r = GET("qd1/deliverable?" . uri_escape('alice@sub.example.com'));
    is $r->code, 200, '200 OK';
    is $r->content, sprintf('%d', 0xf1),
       'body is the decimal status code (0xf1)';
};

subtest 'deliverable: non-local domain' => sub {
    my $r = GET("qd1/deliverable?" . uri_escape('user@nowhere.test'));
    is $r->code, 200, '200 OK';
    is $r->content, sprintf('%d', 0xff), '0xff';
};

subtest 'unknown command under /qd1/ -> 403' => sub {
    my $r = GET("qd1/not_a_command?foo");
    is $r->code, 403, 'forbidden';
};

subtest 'path outside /qd1/ -> 403' => sub {
    my $r = GET("other/path");
    is $r->code, 403, 'forbidden';
};

subtest 'POST not allowed -> 403' => sub {
    my $r = $ua->post("$base/qd1/qmail_local",
        Content => 'alice@sub.example.com');
    is $r->code, 403, 'POST forbidden';
};

subtest 'non-ASCII query -> 400' => sub {
    my $r = GET("qd1/qmail_local?" . uri_escape("a\x00b"));
    is $r->code, 400, '400 Bad Request for non-printable arg';
};

subtest 'SIGHUP rereads config' => sub {
    # Before: example.com is a virtualdomain with prepend 'example.com'.
    my $before = GET("qd1/qmail_local?" . uri_escape('x@example.com'));
    is $before->content, 'example.com-x',
       'initial qmail_local result reflects current config';

    # Rewrite virtualdomains so example.com is no longer listed.
    open my $fh, '>', "$fixtures/control/virtualdomains" or die $!;
    print { $fh } "catchall.example:catchall\n.wild.org:wild\n";
    close $fh;

    kill 'HUP', $pid;

    # Poll for the change to take effect.
    my $after;
    for (1 .. 30) {
        my $r = GET("qd1/qmail_local?" . uri_escape('x@example.com'));
        if ($r->code == 204) { $after = $r; last; }
        select undef, undef, undef, 0.1;
    }
    ok $after && $after->code == 204,
       'after SIGHUP, example.com is no longer local';
};

done_testing();
