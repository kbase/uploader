#!/kb/runtime/bin/perl

use strict;
use warnings;

no warnings('once');

use Config::Simple;
use JSON;
use File::Slurp;
use Getopt::Long;
use LWP::UserAgent;
use MIME::Base64;
use Data::Dumper;
use Pod::Usage;
use String::Random qw(random_regex random_string);

umask 000;

my $CONFIG = '/kb/deployment/deployment.cfg';
my $OAUTH_URL = 'https://nexus.api.globusonline.org/goauth/token?grant_type=client_credentials';

=head1 NAME

uploader -- upload data into KBase

=head1 VERSION

1

=head1 SYNOPSIS

uploader [-h] [-p KB_password] [-u KB_user] [-t data_type] [-w workspace] [-m metadata_file] [-f data_file] [-i submission_id] -a action

=head1 DESCRIPTION

Upload data into KBase as a validated type. Data is first uploaded to a staging area and then submitted to a validation pipeline that upon successful validation imports the data into a selected workspace. Some data types may require metadata. Metadata templates for a data type can be retrieved and filled out metadata can be validated prior to submission. While the validation is in progress, the status of the submission can be retrieved. Data in the staging area can be deleted or transmogrified prior to submission.

Parameters:

=over 8

=item -a B<action>

the action to be executed. Can be one of

=over 16

=item B<upload>

upload a file to the staging area

=item B<validate>

validate a metadata file

=item B<delete>

delete a file in the staging area

=item B<submit>

perform a submisson of data to be validated and imported as a specified data type into a workspace

=item B<status>

retrieve the status of a submission

=item B<template>

retrieve the metadata template for a specified data type

=back

=back

Options:

=over 8

=item -h

display this help message

=item -f B<data_file>

path to the data file. Files in the data store must be prefixed with "SHOCK:" followed by the node id.

=item -m B<metadata_file>

path to the metadata file. Files in the data store must be prefixed with "SHOCK:" followed by the node id.

=item -t B<data_type>

the KBase data type of the submission

=item -w B<workspace>

unique identifier of the target workspace

=item -i B<submission_id>

unique identifier of the submission for status retrieval

=item -p B<KB_password>

KBase password to authenticate against the API, requires a username to be set as well

=item -u B<KB_user>

KBase username to authenticate against the API, requires a password to be set as well

=back

Output:

JSON object containing status information about the requested action.

=head1 EXAMPLES

-

=head1 SEE ALSO

-

=head1 AUTHORS

Jared Bischof, Travis Harrison, Folker Meyer, Tobias Paczian, Andreas Wilke

=cut

my %vars = ();

# variables in config file (defaults are hard-coded here)
$vars{aweurl} = "http://localhost:7080";
$vars{shockurl} = "http://localhost:7078";

# read in the options
my $password = "";
$vars{user} = "";
my $help = 0;
my $options = GetOptions ("a=s"  => \$vars{action},
			  "f=s"  => \$vars{data_file},
			  "m=s"  => \$vars{metadata_file},
                          "t=s"  => \$vars{data_type},
			  "w=s"  => \$vars{workspace},
			  "i=s"  => \$vars{submission_id},
			  "p=s"  => \$password,
			  "u=s"  => \$vars{user},
                          "help" => \$help
			 );

# print the help message
if ($help) {
    pod2usage( { -message => "\nDOCUMENTATION:\n",
                 -exitval => 0,
                 -output  => \*STDOUT,
                 -verbose => 2,
                 -noperldoc => 1,
               } );
}

# check if we have an action
if($vars{action} eq "") {
  &error("you are missing the action parameter from your command.\nFor more detailed documentation run '$0 -h'");
}

# read the config
my $cfg = new Config::Simple($CONFIG);
my $p_cfg = $cfg->param(-block=>'uploader');
foreach my $key (keys(%$p_cfg)) {
  $vars{$key} = $p_cfg->{$key};
}

# check authentication
my $token = "";
if(exists $ENV{"KB_AUTH_TOKEN"}) {
    $token = $ENV{"KB_AUTH_TOKEN"};
} elsif($vars{user} ne "" && $password ne "") {
    my $encoded = encode_base64($vars{user}.':'.$password);
    my $json = new JSON();
    my $pre = `curl -s -H "Authorization: Basic $encoded" -X POST "$OAUTH_URL"`;
    eval {
        my $res = $json->decode($pre);
        unless(exists $res->{access_token}) {
            &error("could not authenticate user");
        }
        $token = $res->{access_token};
    };
    if ($@) {
        &error("could not reach auth server: $@");
    }
} else {
  &error("user not authenticated");
}

# check input parameter dependencies
my $deps = { "template" => [ "data_type" ],
	     "submit" => [ "data_type",
			   "data_file",
			   "workspace" ],
	     "validate" => [ "data_type",
			     "metadata_file" ],
	     "delete" => [ "data_file" ],
	     "upload" => [ "data_file" ],
	     "status" => [ "submission_id" ] };

my $dep_missing = [];
if ($deps->{$vars{action}}) {
  foreach my $p (@{$deps->{$vars{action}}}) {
    if (! exists $vars{$p}) {
      push(@$dep_missing, $p);
    }
  }
  if (scalar(@$dep_missing)) {
    &error("you are missing the following parameters required for the ".$vars{action}." action:\n".join(@$dep_missing, ",\n"));
  }
} else {
  &error("invalid action parameter. Valid values are:\ntemplate, submit, validate, delete, upload and status");
}

###
#
# inputs are done, check which action to perform
#
##

my $output = { "action" => $vars{action},
	       "error"  => undef };
if ($vars{action} eq "template") {
  $output->{status} = "ok";
  &output($output);
} elsif ($vars{action} eq "upload") {
  $output->{status} = "ok";
  &output($output);
} elsif ($vars{action} eq "validate") {
  $output->{status} = "ok";
  &output($output);
} elsif ($vars{action} eq "delete") {
  $output->{status} = "ok";
  &output($output);
} elsif ($vars{action} eq "submit") {
  $output->{status} = "ok";
  &output($output);
} elsif ($vars{action} eq "status") {
  $output->{status} = "ok";
  &output($output);
}

sub error {
  my ($error) = @_;

  print STDERR "ERROR\n$error\nexiting.\n\n";
  exit 1;
}

sub output {
  my ($output) = @_;
  
  my $json = new JSON;
  
  print STDOUT $json->encode($output);
  
  exit 0;
}

1;
