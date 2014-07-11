#!/usr/bin/env perl

# this script takes gwas population metadata json file and data text file as input
# and creates a GwasPopulation type workspace object

use strict;
#use warnings;
#no warnings('once');
use POSIX;
use JSON;

use Bio::KBase::workspace::Client;
use Data::Dumper;
use  Bio::KBase::AuthToken;

use Data::Dumper;
use Bio::KBase::CDMI::CDMIClient;
use Bio::KBase::Utilities::ScriptThing;
my $cdmie = Bio::KBase::CDMI::Client->new("http://bio-data-1.mcs.anl.gov/services/cdmi_api");



umask 000;

#TODO: Fix usage
if(@ARGV != 8) {
  print_usage();
  exit __LINE__;
}

my $ws_url                   = $ARGV[0];
my $ws1                      = $ARGV[1];
my $outid                    = $ARGV[2];
my $metadata_file            = $ARGV[3];
my $uploaded_variation_file  = $ARGV[4]; #file in vcf format
my $shock_url                = $ARGV[5]; #shock url
my $s_id                     = $ARGV[6]; #shock_id. should be NA in case of local upload 
my $environment              = $ARGV[7]; #local or web
my $token                    = $ENV{KB_AUTH_TOKEN};

my $to = Bio::KBase::AuthToken->new();
$token = $to->{token};
my $wsc = Bio::KBase::workspace::Client->new($ws_url, token=>$token );


my $metadata_json;
if ($environment eq "local"){

  open (FILE, $metadata_file) || &return_error("Could not open file '$metadata_file' for reading. ");
  my @data = <FILE>;
  shift @data; #remove header line

    my @datax = split ("\t", $data[0]);

  if (@datax != 5){
    &return_error("Please double check your metadata file and make sure they are tab delimited");
  }


  my ($population_obj_id, $assay, $originator, $pubmed_id, $comment) = @datax;
  chomp($comment);

  my $meta = {};
  $population_obj_id=~s/\s*$//;
  $population_obj_id=~s/^\s*//;

  $meta->{BasicPopulationVariationInfo}->{GwasPopulation_obj_id}= $population_obj_id;
  $meta->{BasicPopulationVariationInfo}->{assay}= $assay;
  $meta->{BasicPopulationVariationInfo}->{originator}= $originator;
  $meta->{BasicPopulationVariationInfo}->{pubmed_id}= $pubmed_id;
  $meta->{BasicPopulationVariationInfo}->{comments}= $comment;
  $metadata_json = to_json($meta);

  $s_id=upload2shock ($uploaded_variation_file);
#$s_id = "75c7de2b-6c2e-4952-9a2b-a679dcfd8c78";
}

elsif ($environment eq "web"){
  open (FILE, $metadata_file) || &return_error("Could not open file '$metadata_file' for reading. ");
  $metadata_json = join ("", <FILE>);
  close (FILE);
}

else {
  &return_error("\$environment variable is required and should be set to local or web");
}

my $hash_metadata = from_json($metadata_json);
$hash_metadata = $hash_metadata->{'BasicPopulationVariationInfo'};

my $population_obj=$hash_metadata->{'GwasPopulation_obj_id'};
$population_obj=~s/\s*$//;
$population_obj=~s/^\s*//;


my $type = "KBaseGwasData.GwasPopulation";


my $object_data = $wsc->get_object({id => $population_obj,

    type => $type,
    workspace => $ws1,
    auth => $token});

my $ecotype_details  = $object_data->{'data'}{'observation_unit_details'};
my $genome  = $object_data->{'data'}{'genome'};
my %hash_germplasms = ();

foreach my $ecotype (@$ecotype_details){
  my $germplasm = $ecotype->{'source_id'};
  $hash_germplasms{$germplasm}++;
}


##TODO: write validator code. Read first few lines of vcf file and check
#Support both .vcf and .vcf.gz
#Check if vcftools gives an error

my $obs_units_string = `head -100 $uploaded_variation_file|grep ^#CHROM`;
chomp ($obs_units_string);
my @obs_units1 = split ("\t", $obs_units_string);

my $length=@obs_units1;
@obs_units1 = @obs_units1[9..$length-1];

#TODO:Fix registering of the observation units
my @obs_units = ();
foreach my $line (@obs_units1){
  my @data = ($line, 'kb|..');
  push (@obs_units, \@data);
}


my $ws_doc;

my $population_obj_ref = $ws1 . "/" .$hash_metadata->{'GwasPopulation_obj_id'}; 
$ws_doc->{'GwasPopulation_obj_id'}= $population_obj_ref;
#$ws_doc->{'GwasPopulation_obj_id'}= $hash_metadata->{'GwasPopulation_obj_id'};
$ws_doc->{'assay'}= $hash_metadata->{'assay'};
$ws_doc->{'originator'}= $hash_metadata->{'originator'};
$ws_doc->{'genome'}= $genome;
#$ws_doc->{'parent_variation_obj_id'}= "NA";
#$ws_doc->{'minor_allele_frequency'}= "NA";
$ws_doc->{'obs_units'}= \@obs_units;


my %files = ();
$files{'shock_url'}=$shock_url;
$files{'vcf_shock_id'}=$s_id;
$files{'emmax_format_hapmap_shock_id'}="";
$files{'tassel_format_hapmap_shock_id'}="";


$ws_doc->{'files'}= \%files;

my $comment = $hash_metadata->{'comment'}; 
$comment = "NA" if (!$comment);
$ws_doc->{'comment'}= $comment;
$ws_doc->{"pubmed_id"}=$hash_metadata->{'pubmed_id'}; ;


#my $outid = $hash_metadata->{'variation_output_name'}; 

#open OUT, ">document.json" || &return_error("Cannot open document.json for writing");
#print OUT to_json($ws_doc, { ascii => 1, pretty => 1 });
#close OUT;

my $metadata = $wsc->save_object({id =>"$outid", type =>"KBaseGwasData.GwasPopulationVariation" , auth => $token,  data => $ws_doc, workspace => $ws1});
#print to_json($ws_doc);


exit(0);

#TODO: Fix usage
sub print_usage {
  &return_error("USAGE: gwas_validate_population.pl ws_url ws_id metadata data");
}

sub return_error {
  my ($str) = @_;
  print STDERR "$str\n";
  exit(1);
}


sub upload2shock {
  my $fn = shift;

#print $token;
  my $cmd = "curl -s -H \"Authorization: OAuth $token\" -X POST -F upload=\@$fn $shock_url/node";

  my $out_shock_meta = from_json(`$cmd`);
  return $out_shock_meta->{data}->{id};


}

