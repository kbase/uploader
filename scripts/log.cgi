#!/usr/bin/env perl
use CGI;
use JSON;

my $json = new JSON;
my $cgi = new CGI;
my $result;

my %params = ( "application" => $cgi->param('application'),
	       "type" => $cgi->param('type'),
	       "time" => $cgi->param('time'),
	       "action" => $cgi->param('action'),
	       "file" => $cgi->param('file'),
	       "size" => $cgi->param('size'),
	       "user" => $cgi->param('user') );
my $missing = [];
foreach my $key (keys(%params)) {
    unless ($params{$key}) {
	push(@$missing, $key);
    }
}
if (scalar(@$missing)) {
    $result = $json->encode( { "ERROR" => "invalid parameter set passed", "MESSAGE" => "missing parameters: ".join(",", @$missing) } );
} else {
    if (open(FH, ">>/Users/tobiaspaczian/CODE/LOG/log")) {
	print FH $params{'application'}."\t".$params{'type'}."\t".$params{'time'}."\t".$params{'action'}."\t".$params{'file'}."\t".$params{'size'}."\t".$params{'user'}."\n";
	close FH;
	$result = $json->encode( { "ERROR" => undef, "MESSAGE" => "SUCCESS" } );
    } else {
	$result = $json->encode( { "ERROR" => "unable to write log message", "MESSAGE" => "ERROR" } );
	print STDERR $@."\n";
    }
}

print $cgi->header( -type => "application/json",
		    -status => 200,
		    -Access_Control_Allow_Origin => '*',
		    -Content_Length => length($result)
    );
print $result;

exit 0;

1;
