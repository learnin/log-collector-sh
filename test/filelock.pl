#!/usr/bin/perl

my ($file_prefix, $file_suffix, $sleep_seconds) = @ARGV;
my $file = $file_prefix . $$ . $file_suffix;

open my $fh, '>', $file
  or die "Cannot open '$file': $!";
sleep $sleep_seconds;
close $fh;
