requires 'Data::Dump';
requires 'AnyEvent';
requires 'AnyEvent::IRC::Client';
requires 'AnySan';
requires 'WWW::Mechanize';
requires 'XML::Simple';
requires 'OAuth::Lite::Consumer';
requires 'LWP::Protocol::https';

on test => sub {
    requires 'Test::Perl::Critic';
};
