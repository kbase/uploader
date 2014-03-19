#!/usr/bin/env perl 

# this script creates a workspace object
use strict;
use warnings;
no warnings('once');

use Getopt::Long;
use IPC::Open3;
use IO::Select;
umask 000;

# options
my $type      = "";
my $id        = "";
my $data      = "";
my $workspace = "";
my $token     = $ENV{KB_AUTH_TOKEN};
my $metadata  = "";
my $url       = "http://140.221.84.209:7058";

my $options = GetOptions ("type=s"      => \$type,
			  "id=s"        => \$id,
			  "data=s"      => \$data,
			  "url=s"       => \$url,
			  "workspace=s" => \$workspace,
			  "metadata=s"  => \$metadata
			 );

if ($type eq "") {
    print  "Error: type is a required parameter\n";
    print_usage();
    exit __LINE__;
}

if ($id eq "") {
    print  "Error: id is a required parameter\n";
    print_usage();
    exit __LINE__;
}

if ($workspace eq "") {
    print  "Error: workspace is a required parameter\n";
    print_usage();
    exit __LINE__;
}

if ($token eq "") {
    print  "Error: token is a required parameter\n";
    print_usage();
    exit __LINE__;
}

unless (-s $data) {
    print  "Error: data file: [$data] does not exist or is size zero\n";
    print_usage();
    exit __LINE__;
}

$token =~ s/^\'(.*)$/$1/;
$token =~ s/^(.*)\'$/$1/;
$ENV{KB_AUTH_TOKEN} = $token;

my $cmd = "ws-url $url; ws-load -w $workspace $type $id $data";  #if \*ERROR is false, STDERR is sent to STDOUT
my $pid = open3(\*CMD_IN, \*CMD_OUT, \*CMD_ERR, $cmd);

my $kid = waitpid($pid, 0);

my $selector = IO::Select->new();
$selector->add(*CMD_ERR, *CMD_OUT);

my $std_out = "";
my $std_err = "";

while (my @ready = $selector->can_read) {
    foreach my $fh (@ready) {
        if (fileno($fh) == fileno(CMD_ERR)) { $std_err .= scalar <CMD_ERR>}
        else                                { $std_out .= scalar <CMD_OUT>}
        $selector->remove($fh) if eof($fh);
    }
}

close(CMD_OUT);
close(CMD_ERR);

if ($? > 0) {
    print "$std_err"."Exiting due to error.\n";
    exit(1); 
} else {
    print "$std_out"."Ojbect saved.\n";
}

exit(0);

sub print_usage{
    print "USAGE: kb_create_ws_object.pl -type=<object type>
                                         -id=<object id>
                                         -data=<file with json object data>
                                         -workspace=<workspace_id>
                                         -token=<kb_auth_token>
                                         [-metadata=<optional file with json object metadata>]
                                         [-url=<optional param for specifying workspace server>]\n";
}
