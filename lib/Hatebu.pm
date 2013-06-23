#!/usr/bin/env perl
package Hatebu;

use strict;
use warnings;
use feature 'say';
use Data::Dump qw/dump/;
use Encode;
use OAuth::Lite::Consumer;
use OAuth::Lite::Token;
use XML::Simple;

sub new {
    my ($class, $params) = @_;
    bless {%$params}, $class;
};

sub init {
    my ($self) = @_;

    my $consumer_key = $self->{consumer_key};
    my $consumer_secret = $self->{consumer_secret};
    my $access_token = $self->{access_token};
    my $access_secret = $self->{access_token_secret};

    my $consumer = OAuth::Lite::Consumer->new(
        consumer_key    => $consumer_key,
        consumer_secret => $consumer_secret,
        site => "http://b.hatena.ne.jp",
        request_token_path => q{/oauth/initiate},
        access_token_path  => q{/oauth/token},
        authorize_path     => q{https://www.hatena.ne.jp/oauth/authorize},
    );

    my $token = OAuth::Lite::Token->new(
        token  => $access_token,
        secret => $access_secret,
    );

    my $res = $consumer->request(
        method => 'GET',
        url => 'http://b.hatena.ne.jp/atom',
        token => $token,
        params => {},
    );

    unless ($res->is_success) {
        return undef;
    }

    my $xml = XML::Simple->new->XMLin($res->decoded_content, ForceArray => 1, KeyAttr => {'link' => 'rel'});
    my $api_end_point = {
        post => $xml->{link}->{'service.post'}->{href},
        feed => $xml->{link}->{'service.feed'}->{href},
    };

    $self->{consumer} = $consumer;
    $self->{token} = $token;
    $self->{api_end_point} = $api_end_point;
}

sub post {
    my ($self, $url) = @_;

    my $consumer = $self->{consumer};
    my $token = $self->{token};
    my $post_ep = $self->{api_end_point}->{post};

    my $n = {
        entry => [
            {
                xmlns => "http://purl.org/atom/ns#",
                link =>
                {
                    rel => 'related',
                    type => 'text/html',
                    href => $url,
                },
            },
        ],
    };

    my $post_xml = XML::Simple->new->XMLout($n, RootName => undef);
    my $res = $consumer->request(
        method => 'POST',
        headers => [
            'Content-Type' => 'application/xml',
        ],
        url => $post_ep,
        content => $post_xml,
        token => $token,
    );

    unless ($res->is_success) {
        return undef;
    }

    my $res_hash = XML::Simple->new->XMLin($res->decoded_content, ForceArray => 1, KeyAttr => {'link' => 'rel'});

    my $post_id = $res_hash->{id}[0];
    my $post_title = encode('utf-8', $res_hash->{title}[0]);
    my $post_url = $res_hash->{link}->{alternate}->{href};
    my $post_edit_url = $res_hash->{link}->{'service.edit'}->{href};

    return {
        id => $post_id,
        title => $post_title,
        post_url => $post_url,
        edit_url => $post_edit_url,
    };
}

sub delete {
    my ($self, $edit_url) = @_;

    my $consumer = $self->{consumer};
    my $token = $self->{token};

    my $res = $consumer->request(
        method => 'DELETE',
        url => $edit_url,
        token => $token,
    );

    unless ($res->is_success) {
        return undef;
    }

    return 1;
}

1;

