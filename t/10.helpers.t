use strict;
use warnings;
use Test::More;
use Test::Warn;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

use lib 'lib';
use lib 't/lib';

use Qmail::Deliverable ':all';
$Qmail::Deliverable::qmail_dir = 't/fixtures';
Qmail::Deliverable::reread_config();

subtest '_potential_exts' => sub {
    is_deeply [ Qmail::Deliverable::_potential_exts('') ],
              [ '' ],
              'empty ext yields one empty entry';

    is_deeply [ Qmail::Deliverable::_potential_exts('foo') ],
              [ 'foo' ],
              'ext without dash yields only the exact value';

    is_deeply [ Qmail::Deliverable::_potential_exts('foo-bar') ],
              [ 'foo-bar', 'foo-default' ],
              'single dash yields exact then user-default';

    is_deeply [ Qmail::Deliverable::_potential_exts('foo-bar-baz') ],
              [ 'foo-bar-baz', 'foo-bar-default', 'foo-default' ],
              'double dash walks back right-to-left';
};

subtest '_prepend' => sub {
    is Qmail::Deliverable::_prepend('example.com'),       'example.com',
       'exact virtualdomain match';
    is Qmail::Deliverable::_prepend('catchall.example'),  'catchall',
       'second exact match';
    is Qmail::Deliverable::_prepend('foo.wild.org'),      'wild',
       'wildcard .wild.org matches subdomain';
    is Qmail::Deliverable::_prepend('a.b.c.wild.org'),    'wild',
       'wildcard .wild.org matches deeper subdomain';
    is Qmail::Deliverable::_prepend('not-listed.test'),   undef,
       'no match and no catch-all yields undef';
    is Qmail::Deliverable::_prepend('wild.org'),          'wild',
       'wildcard .wild.org also matches the bare wild.org domain';
};

subtest '_prepend catch-all' => sub {
    my $tmp = tempdir(CLEANUP => 1);
    make_path("$tmp/control", "$tmp/users");
    open my $vd, '>', "$tmp/control/virtualdomains" or die $!;
    print { $vd } ":catchall\n";
    close $vd;
    open my $lo, '>', "$tmp/control/locals" or die $!;
    close $lo;
    open my $as, '>', "$tmp/users/assign" or die $!;
    print { $as } ".\n";
    close $as;

    local $Qmail::Deliverable::qmail_dir = $tmp;
    Qmail::Deliverable::reread_config();

    is Qmail::Deliverable::_prepend('any-domain.test'), 'catchall',
       'empty-key entry in virtualdomains is the catch-all';
    is Qmail::Deliverable::_prepend('foo.bar.baz'),     'catchall',
       'catch-all also matches deep names';

    # Restore default fixture state
    $Qmail::Deliverable::qmail_dir = 't/fixtures';
    Qmail::Deliverable::reread_config();
};

subtest 'invalid addresses are rejected with a warning' => sub {
    my @bad = (
        'a@b@c',          # two @
        '.foo',           # leading dot
        'foo..bar',       # double dot
        'foo@',           # trailing @
        '@foo',           # leading @
        '',               # empty
        "ctl\x01char",    # control character
    );

    for my $addr (@bad) {
        warning_like { Qmail::Deliverable::qmail_local($addr) }
            qr/Invalid address/,
            "qmail_local('$addr') warns";
        warning_like { Qmail::Deliverable::qmail_user($addr) }
            qr/Invalid address/,
            "qmail_user('$addr') warns";
        warning_like { Qmail::Deliverable::dot_qmail($addr) }
            qr/Invalid address/,
            "dot_qmail('$addr') warns";
        warning_like { Qmail::Deliverable::deliverable($addr) }
            qr/Invalid address/,
            "deliverable('$addr') warns";
    }
};

subtest 'trailing-dot tolerance' => sub {
    # The $valid regex allows a single trailing dot; it should be tolerated.
    is Qmail::Deliverable::qmail_local('alice@sub.example.com.'),
       'alice',
       'trailing dot on address is allowed';
};

done_testing();
