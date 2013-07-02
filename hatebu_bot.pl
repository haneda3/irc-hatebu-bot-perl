#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';
use Data::Dump qw/dump/;
use AnyEvent;
use AnyEvent::IRC::Client;
use Encode;
use WWW::Mechanize;
use URI;
use OAuth::Lite::Consumer;

use FindBin;
use lib "$FindBin::Bin/lib";
use Hatebu;

my $ERROR_HATEBUNG_MSG = "はてブ禁止でした";
my $ERROR_IPADDR_MSG = "IPアドレスははてブしない";
my $ERROR_NGWORD_MSG = "NGワードだったのではてブしない";
my $ERROR_SITE_MSG = "サイトが見つからないのではてブしない";
my $TITLE_MSG = "【タイトル】";
my $SUCCESS_MSG = "【はてブした】";

my $irc_conf = do 'config.irc.pl' or die "$!";
my $hatebu_conf = do 'config.hatebu.pl' or die "$!";

dump($irc_conf);
dump($hatebu_conf);

my $irc_server = $irc_conf->{server};
my $irc_channels = $irc_conf->{channels};
my $hatebu_oauth = $hatebu_conf->{oauth};
my $hatebu_ngwords = $hatebu_conf->{ngwords};

my $ac;
my $irc;

while (1) {
    sleep 3;

    $ac = AnyEvent->condvar;
    $irc = AnyEvent::IRC::Client->new;

    irc_connect();

    $ac->recv;
}

sub irc_connect {
    say "irc_connect";
    # SSL使用時？
    #$irc->enable_ssl;
    $irc->connect($irc_server->{host}, $irc_server->{port}, {
            nick => $irc_server->{nick}, user => $irc_server->{user}, real => $irc_server->{real}
        });

    foreach my $name (keys $irc_channels) {
        my $password = $irc_channels->{$name}->{password} // '';
        $irc->send_srv("JOIN", "#$name", $password);
    };

    $irc->reg_cb( connect    => sub { say "connected"; } );
    $irc->reg_cb( registered => sub { say "registered";} );
    $irc->reg_cb(
        disconnect => sub {
            say "disconnect";
            $ac->send;
        }
    );
    $irc->reg_cb(
        publicmsg => sub {
            my ($irc, $channel, $msg) = @_;

            my $is_notice = $msg->{command} eq "NOTICE";
            my $message = $msg->{params}->[1] // '';

            if (get_delete_message($irc->nick, $message)) {
                if ($is_notice) {
                    return;
                }

                $irc->send_chan($channel, "NOTICE", $channel, "delete ok");
                return;
            }

            my $url = get_url_from_message($message);
            if ($url) {
                my $detail = get_detail_from_url($url);
                unless ($detail->{success}) {
                    return;
                }

                my $title = $detail->{title};
                if ($title) {
                    $irc->send_chan($channel, "NOTICE", $channel, "$TITLE_MSG $title");
                }
                say $url, $title // '';

                if ($is_notice) {
                    return;
                }

                # '#hoge' -> 'hoge'
                my $cn = substr($channel, 1);
                if (is_hatebu_ng_channel($irc_channels->{$cn})) {
                    return;
                }
                if (is_hatebu_ng_message($message)) {
                    return;
                }

                if (is_contain_ngword($message)) {
                    return;
                }

                my $hatebu = Hatebu->new($hatebu_oauth);
                $hatebu->init();
                my $result = $hatebu->post($url);
                if ($result) {
                    $irc->send_chan($channel, "NOTICE", $channel, "$SUCCESS_MSG $result->{eid} $result->{post_url}");
                }
            }
        },
        irc_notice => sub {
        },
    );
}

sub get_delete_message {
    my ($nick, $message) = @_;

    if ($message =~ /$nick:*\s+(\w+)\s+(\w+)/) {
        my $command = $1;
        my $id = $2;

        if ($command =~ /delete/) {
            my $hatebu = Hatebu->new($hatebu_oauth);
            $hatebu->init();
            my $result = $hatebu->delete($id);
            if ($result) {
                return 1;
            }
        }
    }

    return undef;
}


sub get_url_from_message {
  my ($url) = @_;

  if ($url =~ m{((http|https)://[\w/@.,%-_~=\$\?!*|]+)[\s　]*}) {
    my $u = URI->new($1);
    my $host = $u->host;
    if ($host =~ /^[0-9.]+$/) {
        # ip address
        return undef;
    }
    return $u->as_string;
  }
  return undef;
}

sub get_detail_from_url {
    my ($url) = @_;

    my $mech = WWW::Mechanize->new(ssl_opts => { verify_hostname => 0 });
    my $res = $mech->get( $url );

    my $title = undef;
    if ($mech->success) {
        $title = encode('utf-8', $mech->title);
    }
    return {
        success => $mech->success,
        title => $title,
    }
}

sub is_hatebu_ng_channel {
    my ($channel) = @_;

    if (exists($channel->{hatebu})) {
        if ($channel->{hatebu} == 0) {
            return 1;
        }
    }

    return;
}

sub is_hatebu_ng_message {
    # !付きは はてブ禁止
    my ($msg) = @_;
    if ($msg =~ /.*!.*/) {
        return 1;
    }
    return undef;
}

sub is_contain_ngword {
    my ($msg) = @_;

    foreach my $ngword (@$hatebu_ngwords) {
        return 1 if ($msg =~ /$ngword/);
    }
    return undef;
}

