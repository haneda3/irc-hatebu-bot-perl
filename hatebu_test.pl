#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dump qw/dump/;
use Data::Dumper;

use FindBin;
use lib "$FindBin::Bin/lib";
use Hatebu;

my $irc_conf = do 'config.irc.pl' or die "$!";
my $hatebu_conf = do 'config.hatebu.pl' or die "$!";

#dump($irc_conf);
#dump($hatebu_conf);

my $irc_server = $irc_conf->{server};
my $irc_channels = $irc_conf->{channels};
my $hatebu_ngwords = $hatebu_conf->{ngwords};

my $a = Hatebu->new($hatebu_conf->{oauth});

$a->init();
my $res = $a->post('http://www.google.com');
dump $res;
my $eid = $res->{eid};

#$a->delete($res->{edit_url});
$res = $a->delete($eid);
#$res = $a->delete('http://www.google.com');
dump $res;

