
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

# Call to &verify_file_type()
# Good ASCII files return:      file_type = 'ASCII text', err_msg = "", fix_str = ""
# Fixable ASCII files return:   file_type = 'ASCII text', err_msg = "", fix_str = "command to fix file"
# Bad files return:             file_type = bad file type, err_msg = error message, fix_str = ""

my ($file_type, $err_msg, $fix_str) = &verify_file_type($filename);
if ($err_msg ne "") {
    &return_error("$err_msg");
} elsif($fix_str ne "") {
    &return_error("ERROR: File is not usable.  Try running the following to fix this file: $fix_str");
}

my $line = "";
open IN, "<$filename" || &return_error("Could not open file '$filename' for reading.");
while ( defined($line = <IN>) and chomp $line and $line =~ /^\s*$/ ) {
    # ignore blank lines at beginning of file
}

if ( $line !~ /^>/ && $line !~ /^@/ ) {
    &return_error("Not a valid fasta or fastq file.");
}

my $ws_doc;
$ws_doc->{name} = $filename;
$ws_doc->{created} = POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime);
$ws_doc->{type} = $filetype;
$ws_doc->{ref}{ID} = $s_id;
$ws_doc->{ref}{URL} = $s_url;

open OUT, ">document.json" || &return_error("Cannot open document.json for writing.");
print OUT to_json($ws_doc, { ascii => 1, pretty => 1 });
close OUT;

exit(0);

sub print_usage {
    &return_error("USAGE: kb_create_mgm_ws_doc.pl filetype filename shockid shockurl");
}

sub return_error {
    my ($str) = @_;
    print STDERR "$str\n";
    exit(1);
}

####################################

# Good ASCII files return:      file_type = 'ASCII text', err_msg = "", fix_str = ""
# Fixable ASCII files return:   file_type = 'ASCII text', err_msg = "", fix_str = "command to fix file"
# Bad files return:             file_type = bad file type, err_msg = error message, fix_str = ""

sub verify_file_type {
    my ($file) = @_;

    # Need to do the 'safe-open' trick here since for now, file names might
    # be hard to escape in the shell.    
    open(P, "-|", "file", "-b", "$file") or &return_error("cannot run file command on file '$file': $!");
    my $file_type = <P>;
    close(P);

    chomp $file_type;

    if ( $file_type =~ m/\S/ ) {
        $file_type =~ s/^\s+//;   #...trim leading whitespace
        $file_type =~ s/\s+$//;   #...trim trailing whitespace
    } else {
        # file does not work for fastq -- craps out for lines beginning with '@' on mg-rast machine!
        # check first 4 lines for fastq like format
        my @lines = `cat -A '$file' 2>/dev/null | head -n4`;
        chomp @lines;

        if ( ($lines[0] =~ /^\@/) && ($lines[0] =~ /\$$/) && ($lines[1] =~ /\$$/) &&
             ($lines[2] =~ /^\+/) && ($lines[2] =~ /\$$/) && ($lines[3] =~ /\$$/) ) {
            $file_type = 'ASCII text';
        } else {
            $file_type = 'unknown file type, check end-of-line characters and (if fastq) fastq formatting';
        }
    }

    if ($file_type =~ /^ASCII/) {
        # ignore some useless information and stuff that gets in when the file command guesses wrong
        $file_type =~ s/, with very long lines//;
        $file_type =~ s/C\+\+ program //;
        $file_type =~ s/Java program //;
        $file_type =~ s/English //;
    } else {
        $file_type = "binary or non-ASCII file";
    }
    if ($file_type eq 'ASCII text, with CR line terminators') {
        return ('ASCII text', "", "sed -i 's/\\r/\\n/g' '$file'");
    } elsif($file_type eq 'ASCII text, with CRLF line terminators') {
        return ('ASCII text', "", "sed -i 's/\\r//g' '$file'");
    } elsif($file_type eq 'ASCII text') {
        return ($file_type, "", "");
    } elsif((-s "$file") == 0) {
        return ("empty file", "ERROR: File '$file' is empty.", "");
    }

    return ("binary or non-ASCII or invalid end of line characters", "ERROR: File '$file' is of unsupported file type '$file_type'.", "");
}

