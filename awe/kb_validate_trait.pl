#!/usr/bin/env perl

# this script validates a file type and generates a workspace
# object document for uploading into a workspace.

use strict;
use warnings;
no warnings('once');

use POSIX;
use JSON;

use Bio::KBase::workspace::Client;
use Data::Dumper;
use  Bio::KBase::AuthToken;


############################################
my $otoken = Bio::KBase::AuthToken->new(
   user_id => 'kbgwasuser2', password => ''
);
my $token = $otoken->token();
#############################################




umask 000;


#if(@ARGV != 4) {
#  print_usage();
#  exit __LINE__;
#}

my $ws_url              = $ARGV[0];
my $ws1                 = $ARGV[1];
my $metadata_json_file  = $ARGV[2];
my $uploaded_trait_file = $ARGV[3];
#########################################################
$ws_url                 = 'http://140.221.84.209:7058';
$ws1                    = 'kbgwasuser2:home';
$metadata_json_file     = 'json_excel_info.txt';
$uploaded_trait_file    = 'FLC.txt';
###########################################################


my $wsc = Bio::KBase::workspace::Client->new($ws_url);


open (FILE, $metadata_json_file) || &return_error("Could not open file '$metadata_json_file' for reading.");
my $metadata_json = join ("", <FILE>);
close (FILE);




my $hash_metadata = from_json($metadata_json);

my $population_obj=$hash_metadata->{'GwasPopulation_obj_id'};


my $type = "KBaseGwasData.GwasPopulation";
my $object_data = $wsc->get_object({id => $population_obj,
                  type => $type,
                  workspace => $ws1,
                  auth => $token});


my $ecotype_details  = $object_data->{'data'}{'ecotype_details'};
my $genome  = $object_data->{'data'}{'genome'};
my %hash_germplasms = ();

foreach my $ecotype (@$ecotype_details){
   my $germplasm = $ecotype->{'ecotype_id'};
   $hash_germplasms{$germplasm}++;
}




open (FILETRAIT, $uploaded_trait_file)|| &return_error("Could not open file '$uploaded_trait_file' for reading.");


my @filetrait = <FILETRAIT>;
shift @filetrait; #skip header line

my @list_germplasm_not_found = ();
my @trait_data = ();
foreach my $line (@filetrait){

  next if ($line=~/^\s*$/);
  $line=~s/\s*$//;
  my ($germplasm, $value) = split ("\t", $line);
  push (@list_germplasm_not_found, $germplasm) if (!$hash_germplasms{$germplasm}); 
   my @data = ($germplasm, $value);
   push (@trait_data, \@data);
}

my $list_germplasm_not_found = join (",", @list_germplasm_not_found);

if ($list_germplasm_not_found){
  &return_error ("List of germplasms that were not found in the population: $list_germplasm_not_found");
}


my $ws_doc;
$ws_doc->{'protocol'}=$hash_metadata->{'protocol'};
$ws_doc->{'GwasPopulation_obj_id'}= $hash_metadata->{'GwasPopulation_obj_id'};
$ws_doc->{'originator'}= $hash_metadata->{'originator'};
$ws_doc->{'trait_ontology_id'}= $hash_metadata->{'trait_ontology_id'};
$ws_doc->{'trait_name'}= $hash_metadata->{'trait_name'};
$ws_doc->{'genome'}= $genome;
$ws_doc->{'comment'}= $hash_metadata->{'comment'};
$ws_doc->{'unit_of_measure'}= $hash_metadata->{'unit_of_measure'};
$ws_doc->{'trait_measurements'}= \@trait_data;

open OUT, ">document.json" || &return_error("Cannot open document.json for writing.");
print OUT to_json($ws_doc, { ascii => 1, pretty => 1 });
close OUT;

exit(0);



sub print_usage {
    &return_error("USAGE: kb_validate_trait.pl population_data_workspace_url population_data_workspace metadata_json_file uploaded_trait_file shockid shockurl");
}

sub return_error {
    my ($str) = @_;
    print STDERR "$str\n";
    exit(1);
}

