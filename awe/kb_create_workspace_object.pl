#!/usr/bin/env perl 

# this script creates a workspace object
use strict;
use warnings;
no warnings('once');

use Getopt::Long;
use File::Copy;
use File::Basename;
use POSIX qw(strftime);
use Cwd;
use JSON;
use LWP::UserAgent;
umask 000;

my $run_dir = getcwd();

# options
my $type      = "";
my $id        = "";
my $data      = "";
my $workspace = "";
my $token     = "";
my $metadata  = "";
my $url       = "http://kbase.us/services/ws";

my $options = GetOptions ("type=s"      => \$type,
			  "id=s"        => \$id,
			  "data=s"      => \$data,
			  "url=s"       => \$url,
			  "workspace=s" => \$workspace,
			  "token=s"     => \$token,
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

my $json = new JSON;
my $ua = LWP::UserAgent->new;
my $data = { 'params' => [ { "workspace" => $workspace,
			     "id" => $id,
			     "type" => $type,
			     "data" => $data,
			     "metadata" => $metadata || {} } ],
	     'method' => 'Workspace.save_object',
	     'version' => "1.1",
	     'id' => int(rand(100))."" };
  
my $response = $json->decode($ua->post($url, Authorization => $token, Content => $json->encode($data))->content);
if ($response->{result}) {
  print "Finished workspace object creation of $type - $id in workspace $workspace.\n";
} else {
  print "Error creating workspace object: ".$response->{message}."\n";
}

exit(0);

sub print_usage{
    print "USAGE: kb_create_workspace_object.pl -type=<object type>
                                                -id=<object id>
                                                -data=<file with json object data>
                                                -workspace=<workspace_id>
                                                -token=<kb_auth_token>
                                                [-metadata=<optional file with json object metadata>]\n";
}

sub TO_JSON { return { %{ shift() } }; }
