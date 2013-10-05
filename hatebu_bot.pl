#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use AnySan;
use AnySan::Provider::IRC;
use Encode;
use WWW::Mechanize;
use URI;
use OAuth::Lite::Consumer;
use Data::Dumper;
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

#dump($irc_conf);
#dump($hatebu_conf);

my $irc_server = $irc_conf->{server};
my $irc_channels = $irc_conf->{channels};
my $hatebu_oauth = $hatebu_conf->{oauth};
my $hatebu_ngwords = $hatebu_conf->{ngwords};

my $last_added_hatebu_id = undef;

sub _create_channelstr {
    my ($chname) = @_;
    my $password = $irc_channels->{$chname}->{password} // '';
    return "$chname $password";
}

my $channels = {};
foreach my $name (keys $irc_channels) {
    my $cs = _create_channelstr($name);
    $channels->{$cs} = {};
}

my $irc = irc
$irc_server->{host},
port => $irc_server->{port},
nickname => $irc_server->{nick},
recive_commands => ['KICK', 'PRIVMSG', 'NOTICE'],
channels => $channels;

AnySan->register_listener(
    echo => {
        cb => sub {
            my $receive = shift;
            my $message = decode_utf8($receive->message);
            my $nick = $receive->nickname;
            my $channel = $receive->{attribute}->{channel} // '';
            my $is_notice = ($receive->{attribute}->{command} // '') eq 'NOTICE' ? 1 : 0;

            if ($receive->{attribute}->{command} eq 'KICK') {
                $irc->join_channel(_create_channelstr($channel));
                return;
            }

            my $did = get_delete_id_from_message($nick, $message);
            if ($did) {
                if ($did == -1) {
                    unless ($last_added_hatebu_id) {
                        $receive->send_reply("消すモノないよ");
                        return;
                    }
                    $did = $last_added_hatebu_id;
                }
                if (_delete_hatebu($did)) {
                    $receive->send_reply("delete ok $did");
                    $last_added_hatebu_id = undef;
                } else {
                    $receive->send_reply("fail");
                }
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
                    $receive->send_reply("$TITLE_MSG $title");
                }
                #say $url, $title // '';

                return if ($is_notice);

                # '#hoge' -> 'hoge'
                my $cn = substr($channel, 1);
                return if is_hatebu_ng_channel($irc_channels->{$cn});
                return if is_hatebu_ng_message($message);
                return if is_contain_ngword($message);

                my $hatebu = Hatebu->new($hatebu_oauth);
                $hatebu->init();
                my $result = $hatebu->post($url);
                if ($result) {
                    $last_added_hatebu_id = $result->{eid};
                    $receive->send_reply("$SUCCESS_MSG $result->{eid} $result->{post_url}");
                }
                return;
            }

            if ($message =~ /パスワード/) {
                $receive->send_reply("おしえてーーーーーa（＾ー＾）");
                return;
            }
            if ($message =~ /なると/) {
                $receive->send_reply("ちょうだいーーーーー（＾ー＾）");
                return;
            }

            if (get_me_message($nick, $message)) {
                if ($is_notice) {
                    return;
                }

                $receive->send_reply('削除したい delete <はてブID>');
                $receive->send_reply('直前の削除したい cancel|yame|やめ|やっぱやめ');
                return;
            }
        }
    }
);

AnySan->run;

sub _delete_hatebu {
    my ($eid) = @_;

    my $hatebu = Hatebu->new($hatebu_oauth);
    $hatebu->init();
    return $hatebu->delete($eid);
}

sub get_delete_id_from_message {
    my ($nick, $message) = @_;

    if ($message =~ /$nick:*\s+(cancel|yame|やめ|やっぱやめ)/) {
        return -1;
    }

    if ($message =~ /$nick:*\s+delete\s+(\w+)/) {
        my $id = $1;
        return $id;
    }

    return undef;
}

sub get_me_message {
    my ($nick, $message) = @_;

    if ($message =~ /$nick/) {
        return 1;
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

