#!/usr/bin/env perl 

# this script validates a file type and generates a workspace
# object document for uploading into a workspace.

use strict;
use warnings;
no warnings('once');

use POSIX;
use JSON;

umask 000;

if(@ARGV != 4) {
  print_usage();
  exit __LINE__;
}

my $filetype = $ARGV[0];
my $filename = $ARGV[1];
my $s_id = $ARGV[2];
my $s_url = $ARGV[3];

my @array = ('fasta', 'fna');
if (! grep( /^$filetype$/, @array)) {
    print "Error: filetype must be one of: ".join(", ", @array)."\n";
    print_usage();
    exit __LINE__;
}

my $ws_doc;
$ws_doc->{name} = $filename;
$ws_doc->{created} = POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime);
$ws_doc->{type} = $filetype;
$ws_doc->{ref}{ID} = $s_id;
$ws_doc->{ref}{URL} = $s_url;

open OUT, ">document.json" || die "Cannot open document.json for writing.\n";
print OUT to_json($ws_doc, { ascii => 1, pretty => 1 });
close OUT;

exit(0);

sub print_usage{
    print "USAGE: kb_validate_file_and_generate_ws_doc.pl filetype filename shockid shockurl\n";
}
