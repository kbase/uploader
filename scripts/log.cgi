#!/kb/runtime/bin/perl
use strict;
use warnings;
BEGIN {
    push @INC, '/kb/deployment/lib';
}
use CGI;
use JSON;

use Bio::KBase::Log;

# initialize objects and vars
my $json = new JSON;
my $cgi = new CGI;
my $result;

# set vars
my $level = 6; # loglevel
my $client_ip = $ENV{REMOTE_ADDR};
my $call_id = time();

# read the incoming parameters
my %params = ( "application" => $cgi->param('application'),
	       "type" => $cgi->param('type'),
	       "time" => $cgi->param('time'),
	       "action" => $cgi->param('action'),
	       "file" => $cgi->param('file'),
	       "size" => $cgi->param('size'),
	       "user" => $cgi->param('user') );

# check if all required params are available
my $missing = [];
foreach my $key (keys(%params)) {
  unless ($params{$key}) {
    push(@$missing, $key);
  }
}

# some params are missing, throw an error
if (scalar(@$missing)) {
  $result = $json->encode( { "ERROR" => "invalid parameter set passed", "MESSAGE" => "missing parameters: ".join(",", @$missing) } );
}

# all required parameters are available, write a log entry
else {
  
  # initialize a logger object
  my $logger = Bio::KBase::Log->new( $params{'application'},
				     {},
				     { ip_address => 1, authuser => 1, module => 1, method => 1, call_id => 1 } );
  
  # check if the logger creation worked
  if ($logger) {

    # create the logmessage
    my $logmessage = $params{'application'}."\t".$params{'type'}."\t".$params{'time'}."\t".$params{'action'}."\t".$params{'file'}."\t".$params{'size'}."\t".$params{'user'}."\n";
    
    # send the logmessage to the logger
    $logger->log_message($level, $logmessage, $params{'user'},
			 $params{'application'}, $params{'type'}, $call_id,
			 $client_ip);
    
    # create the success message
    $result = $json->encode( { "ERROR" => undef, "MESSAGE" => "SUCCESS" } );
    
  }
  
  # the logger could not be created, set the error message
  else {
    
    $result = $json->encode( { "ERROR" => "unable to initialize logger", "MESSAGE" => "ERROR" } );
    print STDERR $@."\n";
  }

}

# return the result to the requestor
print $cgi->header(
		   -type => "application/json",
		   -status => 200,
		   -Access_Control_Allow_Origin => '*',
		   -Content_Length => length($result)
		  );
print $result;

exit 0;

1;
