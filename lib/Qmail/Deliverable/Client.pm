package Qmail::Deliverable::Client;

use strict;
use 5.006;
use Carp qw(carp);
use base 'Exporter';
use LWP::Simple qw($ua);
use URI::Escape qw(uri_escape);

our @EXPORT_OK = qw/qmail_local deliverable/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

our $SERVER = "127.0.0.1:8998";
our $ERROR;

# rfc2822's "atext"
my $atext = "[A-Za-z0-9!#\$%&\'*+\/=?^_\`{|}~-]";
my $valid = qr/^(?!.*\@.*\@)($atext+(?:[\@.]$atext+)*)\.?\z/;

sub _remote {
    my ($command, $arg) = @_;

    my $response = $ua->get(
        "http://$SERVER/qd1/$command?" . uri_escape($arg)
    );

    my $code = $response->code;
    return undef if $code == 204;  # rpc undef

    my $sl = $response->status_line;
    if ($code == 200) {
        return $response->content;
    }

    carp $ERROR = "Server $SERVER unreachable or broken! ($sl)";
    return undef;
}

sub qmail_local {
    my ($in) = @_;
    my ($address) = lc($in) =~ /$valid/ or
        do { carp "Invalid address: $in"; return; };

    # This we can do locally. Let's not waste HTTP requests :)
    return $address if $address !~ /\@/;

    return _remote 'qmail_local', $address;
}

sub deliverable {
    my ($in) = @_;
    my ($address) = lc($in) =~ /$valid/
        or do { carp "Invalid address: $in"; return; };

    my $rv = _remote 'deliverable', $address;
    return 0x2f if not defined $rv;
    return 0x2f if not length $rv;

    return $rv;
}

1;

__END__

=head1 NAME

Qmail::Deliverable::Client - Client for qmail-deliverabled

=head1 SYNOPSIS

    use Qmail::Deliverable::Client qw(deliverable);

    $Qmail::Deliverable::Client::SERVER = "127.0.0.1:8998";

    if (deliverable "foo@example.com") { ... }

=head1 DESCRIPTION

Qmail::Deliverable comes with a daemon program called qmail-deliverabled. This
module is a front end to it.

This module requires LWP (libwww-perl), available from CPAN.

=head2 Configuration

=over 4

=item $Qmail::Deliverable::Client::SERVER

IP adress and port of the qmail-deliverabled server, joined by a colon.
Defaults to C<127.0.0.1:8998>, just like the daemon.

=back

=head2 Error reporting

The error message is reported via a warning, but also avairable via
$Qmail::Deliverable::Client::ERROR.

=head2 Functions

All documented functions are exportable, and a tag :all is available for
convenience.

Unless documented differently, these functions follow the interfaces described
in L<Qmail::Deliverable>.

=over 4

=item qmail_local $address

As Qmail::Deliverable::qmail_local. Warns and returns undef on communication
failure.

=item deliverable $address

=item deliverable $local

As Qmail::Deliverable::deliverable. Warns and returns 0x2f on communication
failure.

=back

=head1 PERFORMANCE

The server on which I benchmarked this, the client+daemon combination (on
localhost) reached 300 deliverability checks per second for assigned/virtual
users. Real users are slower: around 150 checks per second.

=head1 LEGAL

This software is released into the public domain, and does not come with
warranty or guarantee of any kind. Use it at your own risk.

=head1 AUTHOR

Juerd Waalboer <#####@juerd.nl>
