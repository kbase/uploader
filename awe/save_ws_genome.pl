#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use JSON;
use Digest::MD5 qw(md5_hex);
use File::Basename;

use Bio::KBase::workspace::Client;
use Bio::KBase::IDServer::Client;

####  Read options
my $fastaFile;
my $workspaceName;
my $authToken;
my $workspaceURL = "https://kbase.us/services/ws"; # production endpoint
#my $workspaceURL = "http://140.221.84.209:7058";    # dev endpoint
my $idserverURL = "https://kbase.us/services/idserver";
my $help;

## meta data options
my $source ='kbase';
my $source_id = '';
my $scientific_name = 'Unknown';
my $taxonomy = 'Unknown';
my $domain = 'Unknown';
my $genetic_code = 11; #probably it is 11, but this could be different
my $metadata;

my $opt = GetOptions (
            "fastafile=s" => \$fastaFile,
            "ws-name=s"   => \$workspaceName,
            "ws-url=s"    => \$workspaceURL,
            "authtoken=s" => \$authToken,
            "source=s"    => \$source,
            "source_id=s" => \$source_id,
            "scientific_name=s" => \$scientific_name,
            "taxonomy=s"  => \$taxonomy,
            "domain=s"    => \$domain,
            "genetic_code=i" => \$genetic_code,
            "othermetadata=s" => \$metadata,
            "help|h"      => \$help
            );

### Define and print usage info if requested
my $DESCRIPTION =
" save_ws_genome.pl
    Create a KBaseGenomes.Genome and related typed objects from a local FASTA file of
    genomic sequence with the parameters given
    
    Required Flags:
      --fastafile [FILENAME]      - specify the name of the input fastafile
      --ws-name [WORKSPACE_NAME]  - the name of the workspace to create the objects
      --authtoken [TOKEN]         - pass the user auth token for the user saving
                                    the genome
      
    Optional Flags
      --ws-url  [URL]             - to set a non-default URL for the workspace service
      --source_id [ID]            - specify source ID of the sequence and genome (default='')
      --source [SOURCE]           - specify source of the data (default='kbase')
      --scientific_name [NAME]    - scientific name of the organism (default='Unknown')
      --taxonomy [TAXONOMY]       - taxonomy of the organism (default='Unknown')
      --doman [DOMAIN]            - domain of the organism (default='Unknown')
      --genetic_code [CODE]       - genetic code of the organism (default=11)
      --othermetadata [JSON]      - key value pairs of extra meta data in JSON, key/values
                                    must be strings
      --help, -h                  - print this usage information.
";

if(defined($help)) {
    print $DESCRIPTION;
    exit 0;
}


# check for mandatory flags
if(!defined($fastaFile)) {
    print STDERR "Error: flag '--fastafile' must be defined. Run with --help for usage.\n";
    exit 0;
}
if(!defined($workspaceName)) {
    print STDERR "Error: flag '--ws-name' must be defined. Run with --help for usage.\n";
    exit 0;
}
if(!defined($authToken)) {
    print STDERR "Error: flag '--authtoken' must be defined. Run with --help for usage.\n";
    exit 0;
}
my $metadataParsed;
if (defined($metadata)) {
    $metadataParsed = decode_json($metadata);
}




# setup WS client
my $ws = Bio::KBase::workspace::Client->new($workspaceURL, token=>$authToken );
# uncomment the command below to at least check that auth token and ws client is operating correctly
#print Dumper($ws->list_objects({workspaces=>[$workspaceName]}));

#setup IDserver client
my $idserver = Bio::KBase::IDServer::Client->new($idserverURL);


# make sure it exists
my $fasta_data = []; my $seq; my $header;
if (-e $fastaFile) {
    # read it to our data structure
    my $FILEHANDLE;
    open($FILEHANDLE,"<$fastaFile") or die "Error: cannot read fasta file ('$fastaFile')\n";
    while (my $line = <$FILEHANDLE>) {
        chomp($line);
        if ($line =~ /^\s*>/) {
            if (defined $seq && defined $header) {
                push @$fasta_data, {header=>$header, seq=>$seq};
                undef $seq; undef $header;
            }
            $line =~ s/^\s*>\s*//;  # remove FASTA header character
            $header = $line;
        } else {
            $line =~ s/^\s*//;  # remove leading and trailing space
            $line =~ s/\s*$//;  # remove leading and trailing space
            if (!defined $seq) { $seq = $line; }
            else { $seq.=$line; }
        }
    }
    if (defined $seq && defined $header) {
        push @$fasta_data, {header=>$header, seq=>$seq};
        undef $seq; undef $header;
    }
    close $FILEHANDLE;
} else {
    print STDERR "Error: fasta file specified ('$fastaFile') does not exist.\n";
    exit 1;
}


# reserve IDs
my $kbase_genome_id_prefix="kb|g";
my $kbase_contig_set_id_prefix="kb|contigset";

my $gNumber = $idserver->allocate_id_range($kbase_genome_id_prefix, 1);
my $genome_id = $kbase_genome_id_prefix.".".$gNumber;
my $kbase_genome_contig_id_prefix = $genome_id.".c";

my $csNumber = $idserver->allocate_id_range($kbase_contig_set_id_prefix, 1);
my $contigset_id = $kbase_contig_set_id_prefix.".".$csNumber;

#set up contig object
my $contigs = []; my $contigLengths = []; my $sumContigLengths = 0;
my $fullseq = ''; #used to compute md5 sum of entire contig set
for my $data (@$fasta_data) {
    my $cLen = length($data->{seq})+0;
    my $cNumber = $idserver->allocate_id_range($kbase_genome_contig_id_prefix, 1);
    my $contig_id = $kbase_genome_contig_id_prefix.".".$cNumber;
    my $contig = {
        id       => $contig_id,
        length   => $cLen+0,
        md5      => md5_hex($data->{seq}),
        sequence => $data->{seq},
        name     => $data->{header}
    };
    push @$contigs, $contig;
    push @$contigLengths, $cLen+0;
    $sumContigLengths += $cLen+0;
    $fullseq .= $data->{seq};
}

# setup the contig set
my $contigsetMD5 = md5_hex($fullseq);
my $contigset = {
    id         => $contigset_id,
    name       => basename($fastaFile),
    md5        => $contigsetMD5,
    type       => 'Organism',
    source_id  => $source_id,
    source     => $source,
    contigs    => $contigs,
};

# save the contigset to the workspace
my $PA = { "service"=>"KBaseUploader"};
my $saveObjectsParams = {
                "workspace"  => $workspaceName,
		"objects" => [
			   {
				"data"       => $contigset,
				"name"       => basename($fastaFile).".contigs",
				"type"       => "KBaseGenomes.ContigSet",
				"meta"       => {},
				"provenance" => [ $PA ]
			   }
			]
	};
if (defined($metadataParsed)) {
    $saveObjectsParams->{objects}[0]->{meta} = $metadataParsed;
}
my $output;
eval { $output = $ws->save_objects($saveObjectsParams); };
if($@) {
    print "Object could not be saved!\n";
    print STDERR $@->{message}."\n";
    if(defined($@->{status_line})) {print STDERR $@->{status_line}."\n" };
    print STDERR "\n";
    exit 1;
}
#print Dumper($contigset)."\n";
#print Dumper($output)."\n";

# if we got here, assume success and take the contigset object id
my $contigset_ref = @{@{$output}[0]}[0];

# create the genome typed object
my $genome = {
    id               => $genome_id,
    scientific_name  => $scientific_name,
    domain           => $domain,
    genetic_code     => $genetic_code,
    dna_size         => $sumContigLengths,
    num_contigs      => scalar(@$contigs),
    contig_lengths   => $contigLengths,
    #contig_ids;   #these are external ids, could be another parameter
    source           => $source,
    source_id        => $source_id,
    md5              => $contigsetMD5,
    taxonomy         => $taxonomy,
    #gc_content       => ; # we should compute this at some point
    #complete;
    #publications;
    features         => [],
    contigset_ref    => $workspaceName."/".$contigset_ref
    #proteinset_ref;
    #transcriptset_ref;
};

$saveObjectsParams = {
                "workspace"  => $workspaceName,
		"objects" => [
			   {
				"data"       => $genome,
				"name"       => basename($fastaFile),
				"type"       => "KBaseGenomes.Genome",
				"meta"       => {},
				"provenance" => [ $PA ]
			   }
			]
	};
if (defined($metadataParsed)) {
    $saveObjectsParams->{objects}[0]->{meta} = $metadataParsed;
}
eval { $output = $ws->save_objects($saveObjectsParams); };
if($@) {
    print "Object could not be saved!\n";
    print STDERR $@->{message}."\n";
    if(defined($@->{status_line})) {print STDERR $@->{status_line}."\n" };
    print STDERR "\n";
    exit 1;
}
# if we got here, we are successful
#print Dumper($genome)."\n";
#print Dumper($output)."\n";
print "it worked.\n";

exit 0;