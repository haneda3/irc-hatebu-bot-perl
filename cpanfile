requires 'Data::Dump';
requires 'AnyEvent';
requires 'AnyEvent::IRC::Client';
requires 'WWW::Mechanize';
requires 'XML::Simple';
requires 'OAuth::Lite::Consumer';

on test => sub {
    requires 'Test::Perl::Critic';
};
