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

uploader [-h] [-p KB_password] [-u KB_user] [-t data_type] [-w workspace] [-m metadata_file] [-f data_file] [-i id] [-o options] -a action

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

=item B<fileList>

list all files in the staging area

=item B<submit>

perform a submisson of data to be validated and imported as a specified data type into a workspace

=item B<status>

retrieve the status of a submission

=item B<statusList>

list all submission stati

=item B<template>

retrieve the metadata template for a specified data type

=item B<templateList>

list all available templates

=back

=back

Options:

=over 8

=item -h

display this help message

=item -f B<data_file>

path to the data file.

=item -m B<metadata_file>

path to the metadata file. Files in the data store must be prefixed with "SHOCK:" followed by the node id. For a submission the metadata file must be in the staging area in JSON format and the value of this option must be the node id.

=item -t B<data_type>

the KBase data type of the submission

=item -w B<workspace>

unique identifier of the target workspace

=item -i B<id>

unique identifier of the submission for status retrieval or of the node for file deletion or submission

=item -o B<options>

option key=value pairs to be passed into the workflow document

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
$vars{templatedir} = "/kb/dev_container/modules/uploader/data";
$vars{pipeline} = "kb-upload";
$vars{project} = "data-importer";
$vars{clientgroups} = "kb_upload";
$vars{workspaceurl} = "https://kbase.us/services/ws/";

# read in the options
my $password = "";
$vars{user} = "";
my $help = 0;
my $options = GetOptions ("a=s"  => \$vars{action},
			  "f=s"  => \$vars{data_file},
			  "m=s"  => \$vars{metadata_file},
                          "t=s"  => \$vars{data_type},
			  "w=s"  => \$vars{workspace},
			  "i=s"  => \$vars{id},
			  "p=s"  => \$password,
			  "u=s"  => \$vars{user},
			  "o=s"  => \@{$vars{options}},
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
if(! defined $vars{action}) {
  &error("You are missing the action parameter from your command.\nFor more detailed documentation run '$0 -h'");
}

# check input parameter dependencies
my $deps = { "template" => [ "data_type" ],
	     "templateList" => [],
	     "submit" => [ "data_type",
			   "id",
			   "workspace" ],
	     "validate" => [ "data_type",
			     "metadata_file" ],
	     "delete" => [ "id" ],
	     "upload" => [ "data_file" ],
	     "fileList" => [],
	     "status" => [ "id" ],
	     "statusList" => [] };
my $dep_missing = [];
if ($deps->{$vars{action}}) {
  foreach my $p (@{$deps->{$vars{action}}}) {
    if (! defined $vars{$p}) {
      push(@$dep_missing, $p);
    }
  }
  if (scalar(@$dep_missing)) {
    &error("You are missing the following parameters required for the ".$vars{action}." action:\n".join(",\n", @$dep_missing));
  }
} else {
  &error("Invalid action parameter. Valid values are:\ntemplate, templateList, submit, validate, delete, fileList upload, status and statusList");
}

# read the config
my $cfg = new Config::Simple($CONFIG);
my $p_cfg = $cfg->param(-block=>'uploader');
foreach my $key (keys(%$p_cfg)) {
  $vars{$key} = $p_cfg->{$key};
}

# check if authentication is required
my $req_auth = { "template" => 0,
		 "templateList" => 0,
		 "submit" => 1,
		 "validate" => 0,
		 "delete" => 1,
		 "upload" => 1,
		 "fileList" => 1,
		 "status" => 1,
		 "statusList" => 1};

# initialize the output data structure
# from here on out the errors are high level and all results will be in JSON format (including errors)
my $output = { "status" => "ok", 
	       "action" => $vars{action},
	       "error"  => undef };

my $status = [];

# perform authentication if needed
my $token = "";
if ($req_auth->{$vars{action}}) {
  if(exists $ENV{"KB_AUTH_TOKEN"}) {
    $token = $ENV{"KB_AUTH_TOKEN"};
  } elsif($vars{user} ne "" && $password ne "") {
    my $encoded = encode_base64($vars{user}.':'.$password);
    my $json = new JSON();
    my $pre = `curl -s -H "Authorization: Basic $encoded" -X POST "$OAUTH_URL"`;
    eval {
      my $res = $json->decode($pre);
      unless(exists $res->{access_token}) {
	$output->{error} = "could not authenticate user";
	$output->{status} = "error";
	&output($output);
      }
      $token = $res->{access_token};
    };
    if ($@) {
      $output->{error} = "could not reach auth server: $@";
      $output->{status} = "error";
      &output($output);
    }
  } else {
    $output->{error} = "action ".$vars{action}." requires authentication, but a user could not be authenticated";
    $output->{status} = "error";
    &output($output);
  }
}

# check which action to perform
if ($vars{action} eq "template") {
  if (-f $vars{templatedir}."/".$vars{data_type}.".json") {
    if (open(FH, "<".$vars{templatedir}."/".$vars{data_type}.".json")) {
      my $data = "";
      while (<FH>) {
	$data .= $_;
      }
      close FH;
      my $json = JSON->new();
      eval {
	$data = $json->decode($data);
      };
      if ($@) {
	$output->{status} = "error";
	$output->{error} = "the metadata file could not be parsed: $@";
      } else {
	if (exists $data->{metadata}) {
	  $output->{data} = $data->{metadata};
	}
      }      
    } else {
      $output->{status} = "error";
      $output->{error} = "the metadata file could not be opened: $@";
    }
  } else {
    $output->{status} = "error";
    $output->{error} = "the requested data type does not exist";
  }

  &output($output);
} elsif ($vars{action} eq "templateList") {
  if (-d $vars{templatedir}) {
    if (opendir(my $dh, $vars{templatedir})) {
      my @templates = grep { /\.json$/ && -f $vars{templatedir}."/$_" } readdir($dh);
      closedir $dh;
      my $data = [];
      foreach my $t (@templates) {
	$t =~ s/\.json$//;
	push(@$data, $t);
      }
      $output->{data} = $data;
    } else {
      $output->{status} = "error";
      $output->{error} = "the metadata directory could not be read: $@";
    }
  } else {
    $output->{status} = "error";
    $output->{error} = "the metadata directory does not exist";
  }
  &output($output);
} elsif ($vars{action} eq "upload") {
  my $json = JSON->new();
  my $attr_str = $self->json->encode({ "type" => "inbox", "user" => $vars{user} });
  if (-f $vars{data_file} ) {
    my $content  = [ attributes => [ undef, "attributes.json", Content => $attr_str ], upload => [ $vars{data_file} ] ];
    &request($output, $vars{shockurl}."/node", 1, "post", $content);
  } else {
    $output->{status} = "error";
    $output->{error} = "The upload file does not exist: $@";
    &output($output);
  }
} elsif ($vars{action} eq "validate") {
  &validate($output, 1);
} elsif ($vars{action} eq "delete") {
  &request($output, $vars{shockurl}."/node/".$vars{id}, 1, "delete");
} elsif ($vars{action} eq "fileList") {
  &request($output, $vars{shockurl}."/node?query&limit=9999&type=inbox&user=".$vars{user}, 1);
} elsif ($vars{action} eq "submit") {
  my $validation = &validate($output);
  my $shocknode = &request($output, $vars{shockurl}."/node/".$vars{id}, 1, undef, undef, 1);
  &fillAWETemplateAndSubmit($validation, $shocknode);
} elsif ($vars{action} eq "status") {
  &request($output, $vars{aweurl}."/job/".$vars{id}, 1);
} elsif ($vars{action] eq "statusList") {
  &request($output, $vars{aweurl}."/job?query&info.user=".$vars{user}."&info.project=data-importer", 1);
}

###
#
# helper functions
#
###

# print out a low level error and exit with error status
sub error {
  my ($error) = @_;

  print STDERR "ERROR:\n$error\nexiting.\n\n";
  exit 1;
}

# print out the output in JSON format and exit with status 0
sub output {
  my ($output) = @_;
  
  my $json = new JSON;
  
  print STDOUT $json->encode($output);
  
  exit 0;
}

# handle an LWP request, outputs the result or returns it to the calling function if $doReturn is true
sub request {
  my ($output, $url, $auth, $method, $content, $doReturn) = @_;

  my $json = JSON->new();
  my $ua = LWP::UserAgent->new();

  my $get;
  if ($auth) {
    if ($method && $method eq "delete") {
      $get = $ua->delete($url, Authorization => "OAuth $token");
    } elsif ($method && $method eq "post") {
      $get = $ua->post($url, $content, Content_Type => 'form-data', Authorization => "OAuth $token");
    } else {
      $get = $ua->get($url, Authorization => "OAuth $token");
    }
  } else {
    $get = $ua->get($url);
  }
  if ($get->is_success) {
    if ($output) {
      my $json = new JSON();
      my $res = $json->decode( $get->content );
      if ($res->{error}) {
	$output->{status} = "error";
	$output->{error} = $res->{error};
      } else {
	$output->{data} = $res->{data};
      }
    } else {
      return $get->content;
    }
  } else {
    my $res;
    eval {
      $res = $json->decode( $get->content );
    };
    if ($res) {
      $output->{status} = "error";
      $output->{error} = $res->{error};
    } else {
      $output->{status} = "error";
      $output->{error} = "the server could not be reached";
    }
  }

  if ($doReturn) {
    return $output;
  } else {
    &output($output);
  }
}

# fill out an AWE template and submit it to the AWE server
# outputs the result of the submission and exits with status 0
sub fillAWETemplateAndSubmit {
  my ($validation, $shocknode) = @_;

  my $output = { "action" => "submit",
		 "status" => "ok" };

  my $json = JSON->new();

  # load the template
  if (-f $vars{templatedir}."/".$vars{data_type}.".json") {
    if (open(FH, "<".$vars{templatedir}."/".$vars{data_type}.".json")) {
      my $data = "";
      while (<FH>) {
	$data .= $_;
      }
      close FH;
      eval {
	$data = $json->decode($data);
      };
      if ($@) {
	$output->{status} = "error";
	$output->{error} = "the awe template file could not be parsed: $@";
	&output($output);
      } else {
	if (exists $data->{awe}) {
	  $output->{template} = $data->{awe};
	}
      }      
    } else {
      $output->{status} = "error";
      $output->{error} = "the awe template file could not be opened: $@";
      &output($output);
    }
  } else {
    $output->{status} = "error";
    $output->{error} = "the requested data type does not exist";
    &output($output);
  }

  # fill in info section
  $output->{template}->{info} = { "pipeline" => $vars{pipeline},
				  "name" => $vars{data_type},
				  "project" => $vars{project},
				  "user" => $vars{user},
				  "clientgroups" => $vars{clientgroups},
				  "noretry" => true };

  # retrieve variables to replace
  # default variables
  my $replacements = { "SHOCK" => $vars{shockurl},
		       "WORKSPACE" => $vars{workspace},
		       "WORKSPACEURL" => $vars{workspaceurl},
		       "METADATA" => $vars{metadata_file},
		       "INPUTFILE" => $vars{id},
		       "INPUTFILEFileName" => $shocknode->{data}->{file}->{name} };

  # variables passed in the options
  if (exists $vars{options}) {
    foreach my $option (@{$vars{options}}) {
      my ($key, $val) = split(/=/, $option);
      $replacements->{$key} = $val;
    }
  }

  # replace variables in the AWE workflow
  my $aweString = $json->encode($output->{template});
  foreach my $key (keys(%$replacements)) {
    my $val = $replacements->{$key};
    $aweString =~ s/\#\#$key\#\#/$val/g;
  }
  $output->{workflow} = $json->decode($aweString);

  # perform the submission
  my $content  = [ upload => [ undef, "attributes.json", Content => $aweString ] ];
  &request($output, $vars{aweurl}."/job", 1, "post", $content);
}

# validate data against the current template
# will return ok if no metadata is required
sub validate {
  my ($output, $direct_output) = @_;
  
  # load the template
  if (-f $vars{templatedir}."/".$vars{data_type}.".json") {
    if (open(FH, "<".$vars{templatedir}."/".$vars{data_type}.".json")) {
      my $data = "";
      while (<FH>) {
	$data .= $_;
      }
      close FH;
      my $json = JSON->new();
      eval {
	$data = $json->decode($data);
      };
      if ($@) {
	$output->{status} = "error";
	$output->{error} = "the metadata file could not be parsed: $@";
	&output($output);
      } else {
	if (exists $data->{metadata}) {
	  $output->{template} = $data->{metadata};
	}
      }      
    } else {
      $output->{status} = "error";
      $output->{error} = "the metadata file could not be opened: $@";
      &output($output);
    }
  } else {
    $output->{status} = "error";
    $output->{error} = "the requested data type does not exist";
    &output($output);
  }

  # check if metadata is required
  if (exists $output->{template}) {

    # load the metadata
    if (my ($id) = $vars{metadata_file} =~ /^SHOCK\:(.+)$/) {
      my $data = &request(undef, $vars{shockurl}."/node/".$id."?download", 1);
      my $json = JSON->new();
      eval {
	$data = $json->decode($data);
      };
      if ($@) {
	$output->{status} = "error";
	$output->{error} = "the metadata file could not be parsed: $@";
	&output($output);
      } else {
	$output->{metadata} = $data;
      }
    } else {
      if (-f $vars{metadata_file}) {
	if (open(FH, "<".$vars{metadata_file})) {
	  my $data = "";
	  while (<FH>) {
	    $data .= $_;
	  }
	  close FH;
	  my $json = JSON->new();
	  eval {
	    $data = $json->decode($data);
	  };
	  if ($@) {
	    $output->{status} = "error";
	    $output->{error} = "the metadata file could not be parsed: $@";
	    &output($output);
	  } else {
	    $output->{metadata} = $data;
	  }
	} else {
	  $output->{status} = "error";
	  $output->{error} = "the metadata file not be read: $@";
	  &output($output);      
	}
      } else {
	$output->{status} = "error";
	$output->{error} = "the metadata file does not exist";
	&output($output);      
      }
    }
    
    # perform the validation
    if (ref($output->{metadata}) eq "HASH") {
      my $num = 0;
      foreach my $i (keys(%{$output->{metadata}})) {
	$num++;
	if (exists $output->{template}->{groups}->{$i}) {
	  my $item = $output->{metadata}->{$i};
	  my $group = $output->{template}->{groups}->{$i};
	  if (ref($item) eq 'HASH') {
	    &check_group($item, $group);
	  } else {
	    push(@$status, 'data item '.$i.' is not an object');
	  }
	} else {
	  push(@$status, 'group '.$i.' does not exist in template');
	}
      }
      
      if ($num == 0) {
	push(@$status, 'no data to validate');
      }
    } else {
      push(@$status, 'the data is not an object');
    }
    if (scalar(@$status)) {
      $output->{status} = "error";
      $output->{error} = join("\n", @$status);
    } else {
      $output->{data} = "the metadata is valid";
    }
  } else {
    $output->{data} = "no metadata required";
  }

  if ($direct_ouput) {
    &output($output);
  } else {
    return $output;
  }
}

sub check_group {
  my ($item, $group) = @_;

  if (ref($item) eq 'ARRAY') {
    my $h_count = 0;
    foreach my $h (@$item) {
      if (ref($h) eq 'HASH') {
	foreach my $j (keys(%$h)) {
	    if (exists $group->{fields}->{$j}) {
	      &check_field($h->{$j}, $j, $group, $h_count);
	    } elsif (exists $group->{subgroups}->{$j}) {
	      &check_group($h->{$j}, $output->{template}->{groups}->{$j});
	    } else {
	      push(@$status, 'field '.$j.' in does not exist in template');
	    }
	}
	foreach my $j (keys(%{$group->{fields}})) {
	  if ($group->{fields}->{$j}->{mandatory} && ! exists $h->{$j}) {
	    push(@$status, 'mandatory field '.$j.' missing in group '.$group->{name}.' instance '.$h_count);
	  }
	}
      } else {
	push(@$status, 'instance '.$h_count.' of group '.$group->{name}.' is not an object');
      }
      $h_count++;
    }

  } else {
    foreach my $h (keys(%$item)) {
      if (exists $group->{fields}->{$h}) {
	&check_field($item->{$h}, $h, $group);
      } elsif (exists $group->{subgroups}->{$h}) {
	&check_group($item->{$h}, $output->{template}->{groups}->{$h});
      }
    }
    foreach my $h (keys(%{$group->{fields}})) {
      if ($group->{fields}->{$h}->{mandatory} && ! exists $item->{$h}) {
	push(@$status, 'mandatory field '.$h.' missing in group '.$group->{name});
      }
    }
  }
  
  return;
}
    
sub check_field {
  my ($value, $fieldname, $group, $location) = @_;
  
  my $error = "field ".$fieldname." of group ".$group->{name};
  if (defined $location) {
    $error .= " instance ".$location;
  }
  
  if (exists $group->{fields}->{$fieldname}) {
    my $field = $group->{$fields}->{$fieldname};
    if ($field->{validation} && $field->{validation}->{type} ne 'none') {
      if ($field->{validation}->{type} eq 'cv') {
	if (! $output->{template}->{cvs}->{$field->{validation}->{value}}->{$value}) {
	  push(@$status, 'value "'.$value.'" of field '.$fieldname.' was not found in the controlled vocabulary.');
	}
	return;
      } elsif ($field->{validation}->{type} eq 'expression') {
	if ($field->{validation}->{value} !~ $value) {
	  push(@$status, 'field '.$fieldname.' has an invalid value');
	}
	return;
      }
    } else {
      if ($field->{mandatory}) {
	if (! defined $value) {
	 push(@$status, 'mandatory field '.$fieldname.' missing');
	}
      }
      return;
    }
  } else {
    push(@$status, 'field '.$fieldname.' does not exist in template');
    return;
  }
}

1;
