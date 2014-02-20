#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long;
use JSON;
use File::Basename;

use Bio::KBase::workspace::Client;

#  read default options
my $workspaceName;
my $authToken;
my $workspaceURL = "https://kbase.us/services/ws";

# read custom options
my $metadatafile;
my $inputFile;
my $inputParam;

my $opt = GetOptions (
		      "ws-name=s"      => \$workspaceName,
		      "ws-url=s"       => \$workspaceURL,
		      "authtoken=s"    => \$authToken,

		      "inputfile=s"    => \$inputFile,
		      "metadatafile=s" => \$metadatafile,
		      "inputparam=s"   => \$inputParam

		     );

# check for mandatory parameters
if(!defined($workspaceName)) {
    print STDERR "Error: flag '--ws-name' must be defined.\n";
    exit 1;
}
if(!defined($authToken)) {
    print STDERR "Error: flag '--authtoken' must be defined.\n";
    exit 1;
}
if(!defined($metadatafile)) {
    print STDERR "Error: flag '--metadatafile' must be defined.\n";
    exit 1;
}
if(!defined($inputFile)) {
    print STDERR "Error: flag '--inputfile' must be defined.\n";
    exit 1;
}
if(!defined($inputParam)) {
    print STDERR "Error: flag '--inputparam' must be defined.\n";
    exit 1;
}

# setup WS client
my $ws = Bio::KBase::workspace::Client->new($workspaceURL, token=>$authToken );

# check if the input file exists
if (-e $inputFile) {

  # open the passed file
  my $FILEHANDLE;
  open($FILEHANDLE,"<$inputFile") or die "Error: cannot read input file ('$inputFile')\n";
  while (my $line = <$FILEHANDLE>) {
    chomp($line);
    
    # check file contents here
  }
  close $FILEHANDLE;
} else {
  # the input file does not exist, exit with an error
  print STDERR "Error: input file specified ('$inputFile') does not exist.\n";
  exit 1;
}

# read in the metadata file
my $metadatastring = "";

# check if the metadata file exists
if (-e $metadatafile) {

  # open the metadata file
  my $FILEHANDLE;
  open($FILEHANDLE,"<$metadatafile") or die "Error: cannot read metadata file ('$metadatafile')\n";
  while (my $line = <$FILEHANDLE>) {
    chomp($line);
    $metadatastring .= $line;
  }
  close $FILEHANDLE;
} else {

  # the metadata file does not exist, exit with an error
  print STDERR "Error: metadata file specified ('$metadatafile') does not exist.\n";
  exit 1;
}

# the metadata has been read in, parse the JSON
my $metadata = decode_json($metadatastring);

# you can access the metadata here
# assume your metadata looks like this:
# { "main": { "field a": "value a",
#             "field b": "value b" } }
# you would access the value of field b:
my $field_b_value = $metadata->{"main"}->{"field b"};

# access other input parameters
print "input param is '".$inputParam."'\n";

# create the data for the typed object
my $data = { "field_a" => "value_a",
	     "field_b" => "value_b" };

# set the data type
my $type = "KBaseGroup.KBaseTypeName";

# save the data to the workspace
my $PA = { "service"=>"KBaseUploader"};
my $saveObjectsParams = {
                "workspace"  => $workspaceName,
		"objects" => [
			   {
				"data"       => $data,
				"name"       => basename($inputFile),
				"type"       => $type,
				"meta"       => {},
				"provenance" => [ $PA ]
			   }
			]
	};

# perform the submission to the workspace
my $output;
eval { $output = $ws->save_objects($saveObjectsParams); };

# check if the submission was successful
if($@) {
    print "Object could not be saved!\n";
    print STDERR $@->{message}."\n";
    if(defined($@->{status_line})) {print STDERR $@->{status_line}."\n" };
    print STDERR "\n";
    exit 1;
}

# if we reach here, the data import was successful
print "data import complete.\n";

exit 0;
