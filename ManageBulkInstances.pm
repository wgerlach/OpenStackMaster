#!/usr/bin/env perl


package ManageBulkInstances;

use strict;
use warnings;

eval "use Parallel::ForkManager 0.7.6; 1"
	or die "module required: sudo apt-get install build-essential ; perl -MCPAN -e \'install Parallel::ForkManager\'";

eval "use File::Flock; 1"
	or die "module required: sudo apt-get install libfile-flock-perl OR perl -MCPAN -e \'install File::Flock\'";

#use Parallel::ForkManager 0.7.6;
#new version: sudo apt-get install build-essential ; perl -MCPAN -e 'install Parallel::ForkManager'
#old version: sudo apt-get install libparallel-forkmanager-perl

use lib $ENV{"HOME"}."/projects/libraries/"; # path to SubmitVM module
use SubmitVM;
use Getopt::Long;

use LWP::UserAgent;
use JSON;
use Data::Dumper;

# purpose of this module: wrapper for nova tools



##############################
# parameters

#my $image = "b24d27d8-146c-4eea-9153-378d2642959d";
#my $image_name = "w_base_snapshot"; # or "Ubuntu Precise 12.04 (Preferred Image)"
#our $key_name = "dmnewmagellanpub";
#our $sshkey = "~/.ssh/dm_new_magellan.pem";


my $os_tenant_id = $ENV{'OS_TENANT_ID'};
my $os_username = $ENV{'OS_USERNAME'};
my $os_password = $ENV{'OS_PASSWORD'};
my $os_auth_url = $ENV{'OS_AUTH_URL'};




my $ssh_options = "-o StrictHostKeyChecking=no"; # StrictHostKeyChecking=no because I am too lazy to check for the question.

my $vm_user = 'ubuntu';

my @hobbitlist = ("Frodo","Samwise","Meriadoc","Peregrin","Gandalf","Aragorn","Legolas","Gimli","Denethor","Boromir","Faramir","Galadriel","Celeborn","Elrond","Bilbo","Theoden","Eomer","Eowyn","Treebeard");

my $default_namelist = \@hobbitlist;


our $nova = "nova --insecure --no-cache ";


my $os_token;


my $nova_endpoint_uri;
my $volume_endpoint_uri;

my $timeout=30;

my $debug=0;

our $options_basicactions = ["Nova actions",
							"create=i"		=> "create i new instances from snapshot/image" ,			\&createAndAddToHash,
							"delete"		=> "use with --ipfile (recommended) or --iplist",			\&deletebulk,
							"info"			=> "list all instances, volumes, flavors...",				\&info,
							"listgroup"		=> "list all instances with prefix --groupname",			\&list_group_print,
							"savegroup"		=> "save group with prefix --groupname in ipfile",			\&saveGroupInIpFile
							] ;

our $options_vmactions = ["VM actions",
							"sshtest"		=> "try to ssh all instances",								undef
							] ;

our $options_create_opts = ["Create options",
							"flavor_name=s"	=> "optional, use with --create",							undef,
							"image=s"		=> "image ID, use with --create",							undef,
							"image_name=s"	=> "image name, use with action --create", 					undef,
							"sshkey=s"		=> "required, path to ssh key file",						undef,
							"key_name=s"	=> "required, key_name as in Openstack",					undef,
							"groupname=s"	=> "optional, Openstack instance prefix name",				undef,
							"nogroupcheck"	=> "optional, disables check for unique groupname",			undef,
							"onlygroupname"	=> "optional, instance names all equal groupname",			undef,
							"owner=s"		=> "optional, metadata information on VM, default os_username",	undef,
							"noownercheck"	=> "optional, disables owner check",						undef,
							"disksize=i"	=> "optional, in GB, creates, attaches and mounts volume",	undef,
							"wantip"		=> "optional, external IP, only with count=1",				undef,
							"user-data=s"	=> "optional, pass user data file to new instances",		undef,
							"saveIpToFile"	=> "optional, saves list of IPs in file (recommended)",		undef
							];


our $options_specify = [	"Specify existing VMs for actions and deletion",
							"ipfile=s"		=> "file containing list of ips with names",				undef,
							"iplist=s@"		=> "list of ips, comma separated, use with --sshkey",		undef
							];

our @options_all = ($options_basicactions, $options_vmactions, $options_create_opts, $options_specify);

##############################
# subroutines


sub runActions { # disable action by overwriting subroutine reference with "undef"
	my $arg_hash_ref = shift(@_);
	my $options_array_ref = shift(@_);
	
	
	foreach my $option_group (@$options_array_ref) {
		print "    ".${$option_group}[0].":\n";
		for (my $i = 1; $i < @$option_group; $i+=3) {
			my $option = ${$option_group}[$i];
			#print "opt: ".$option."\n";
			
			($option) = split('\=', $option);
			#print "opt_prefix: ".$option."\n";
			
			if (defined $arg_hash_ref->{$option}) { # check if the action was requested
			
				if (defined ${$option_group}[$i+2]) { # check if a function is assigned
					print "start action $option\n";
					${$option_group}[$i+2]($arg_hash_ref);
				}
				
			}
			
		}
	}

	
	return;
	
}

sub getOptionsHash {
	
	my $options_array_ref = shift(@_);
	my $arg_hash_ref = shift(@_);
	
	
	my @raw_options;
	# fill raw_options
	foreach my $option_group (@$options_array_ref) {
		#print "    ".${$option_group}[0].":\n";
		for (my $i = 1; $i < @$option_group; $i+=3) {
			my $option = ${$option_group}[$i];
			#print "opt: ".$option."\n";
			push(@raw_options, $option);
		}
	}

	my $result_getopt = GetOptions ($arg_hash_ref, @raw_options);
	
	unless ($result_getopt) {
		die;
	}
	
	return;
}

sub print_usage {
	my $options_array = shift(@_);
	
	foreach my $option_group (@$options_array) {
		print "    ".${$option_group}[0].":\n";
		for (my $i = 1; $i < @$option_group; $i+=3) {
			my $option = ${$option_group}[$i];
			my $text =  ${$option_group}[$i+1];
			print "     --".$option. ' 'x (20-length($option)). $text."\n";
		}
		print "\n";
	}
	print " \n";
	print " Option priorities: 1) command line 2) ipfile 3) ~/.bulkvm ; for 2 and 3 use: sshkey=~/.ssh/dm_new_magellan.pem\n";
	return;
}


sub read_config_file {
	
	my $arg_hash = shift(@_);
	my $config_file = shift(@_);
	
	if ($config_file eq "default") {
		$config_file =  $ENV{"HOME"} . "/.bulkvm";
		unless (-e $config_file) {
			print "config file $config_file not found, continue\n";
			return;
		}
	} else {
		$config_file = glob($config_file);
		unless (-e $config_file) {
			print "error: (read_config_file) \"$config_file\" not found\n";
			exit(1);
		}
	}
	
	open CONFIG_FILE_STREAM, $config_file or die $!;
	
	while (my $line = <CONFIG_FILE_STREAM>) {
		chomp($line);
		if (length($line) < 2) {
			next;
		}
		if (substr($line, 0 ,1) eq "\#") {
			next;
		}
		
		my ($config_key, $config_value) = split('\=', $line);
		
		if (defined($config_key) && defined($config_value) ) {
			#print "$config_key $config_value\n";
			unless (defined $arg_hash->{$config_key}) {
				if ($config_key eq "iplist") { # ugly
					my @iparray = split(/,/ , $config_value);
					$arg_hash->{$config_key} = \@iparray;
				} else {
					$arg_hash->{$config_key} = $config_value;
				}
				print "use configuration: ".$line."\n";
			}
			
		} else {
			print STDERR "error parsing line from config file: ".$line."\n";
			exit(1);
		}
		
		
	}
		
	

}




sub try_load {
	my $mod = shift;
	
	eval("use $mod");
	
	if ($@) {
		#print "\$@ = $@\n";
		return(0);
	} else {
		return(1);
	}
}

sub nova2hash{
	my $command = shift(@_);
	my $printtable = shift(@_);
	
	print $command."\n";
	
	#pipe stderr to stdout !
	$command .= " 2>&1";
	
	my %hash;
	my @header;
	my $linenum = -1;
	open(COM, $command." |") or die "Failed: $!\n";
	while (my $line = <COM> ) {
		$linenum++;
		
		
		
		if ($printtable) {
			print $line;
		}
		
		if (length($line) <=1 ) {
			next;
		}
		
		my $is_data = 0;
		if (substr($line, 0 ,1) eq '|') {
			$is_data = 1;
		}
		
		if ($line =~ /^ERROR/) {
			print $line;
			close (COM);
			$hash{"ERROR"} = 1;
			$hash{"ERRORMESSAGE"} = $line;
			return \%hash; # used to be undef
		}
		
		
		$line = substr($line, 1, length($line)-3);
		
		if ($linenum == 1) {
			@header = split('\|', $line);
			@header = grep(s/\s*$//g, @header);
			@header = grep(s/^\s*//g, @header);
			#print "header: ".join(",", @header)."\n";
			next;
		}
		
		if ($line =~ /^\-\-\-\-/) {
			next;
		}
		
		if ($is_data ==1 ) {
			#my @data = $line =~ /\s+(\S+)\s+\|/g;
			my @data = split('\|', $line);
			@data = grep(s/\s*$//g, @data);
			@data = grep(s/^\s*//g, @data);
			#print "data: ".join(",", @data)."\n";
			for (my $i = 1 ; $i < @data; $i++) {
				#print $data[0]." ".$header[$i]." ".$data[$i]."\n";
				$hash{$data[0]}{$header[$i]}=$data[$i];
			}
		}
		
	}
	close (COM);
	
	return \%hash;
}

sub getIP {
	
	my $newip = undef;
	
	# try to find available IP
	#my $nova_floating_ip_list = nova2hash($nova." floating-ip-list", 0);
	my $floating_ips = openstack_api('GET', 'nova', '/os-floating-ips');
	
	
	foreach my $ip_hash ( @{$floating_ips->{'floating_ips'}} ) {
		unless (defined $ip_hash->{'instance_id'}) {
			$newip = $ip_hash->{'ip'};
			last;
		}
	}
	
	if (defined $newip) {
		return $newip;
	}
	
	# no IP found, trt to request a new one:
	my $nova_newip_hash = nova2hash($nova." floating-ip-create");
	my $post_floating_ips= openstack_api('POST', 'nova', '/os-floating-ips', { 'pool' => 'nova'});
	
	unless (defined $post_floating_ips->{'floating_ip'}->{'ip'} ) {
	#if (defined $nova_newip_hash->{"ERROR"}) {
		return undef;
	}
	
	($newip) = keys(%$nova_newip_hash);
	return $newip;
}

sub systemp {
	print join(' ', @_)."\n";
	return system(@_);
}

sub getHashValue {
	my $hashref = shift(@_);
	my $row = shift(@_);
	my $col = shift(@_);
	
	my $return_value = $hashref->{$row}{$col};
	unless (defined $return_value) {
		print STDERR "error: no value for \"$row\" \"$col\" \n";
		print STDERR "keys in hash: ".join(',', keys %$hashref)."\n";
		exit(1);
	}
	return $return_value;
}


sub waitNovaHashValue {
	my $nova_command = shift(@_);
	my $row = shift(@_);
	my $col = shift(@_);
	my $value = shift(@_);
	my $timestep = shift(@_);
	my $timetotal = shift(@_);
	
	my $mytime = 0;
	my $vol_status;
	while (1) {
		
		my $hash = nova2hash($nova." ".$nova_command, 1);
		unless (defined $hash->{"ERROR"}) {
			$vol_status = getHashValue($hash, $row, $col);
			if ($vol_status eq $value) {
				return 1;
			}
		}
		if ($mytime > $timetotal ) {
			return 0;
			
		}
		
		$mytime+=$timestep;
		sleep $timestep;
	}

	
}

sub volumeAttachWait {
	my $instance_id = shift(@_);
	my $volume_id = shift(@_);
	my $device = shift(@_);

	
	#  attach volume to instance
	#my $volumeattach = nova2hash($nova." volume-attach $instance_id $volume_id $device", 1);
	
	my $attach_request_json =	{	'volumeAttachment' =>	{
																'volumeId' => $volume_id,
																'device' => $device
															}
								};
	
	my $new_attachment = openstack_api('POST', 'nova', '/servers/'.$instance_id.'/os-volume_attachments', $attach_request_json)->{'volumeAttachment'};
	#print Dumper($new_attachment);
	
	
	my $time_out = 0;
	while (1) {
		my $attachment_info = openstack_api('GET', 'volume', '/volumes/'.$volume_id)->{'volume'};
		#print Dumper($attachment_info);
		if (lc($attachment_info->{'status'}) eq 'in-use' ) {
			return 1; # good
		} elsif (lc($attachment_info->{'status'}) eq 'error') {
			print Dumper($attachment_info);
			return 0; # bad
		}
		$time_out += 5;
		if ($time_out > 60) {
			print Dumper($attachment_info);
			return 0; # bad
		}
		sleep(5);
	}
	
	
	return 0;

}

sub volumeCreateWait{
	my $instname = shift(@_);
	my $disksize = shift(@_);
	my $owner = shift(@_);
	
	unless (defined $owner) {
		$owner = $os_username;
	}
		
	my $volume_request_json = { 'volume' => {	'display_name' => $instname,
												'size' => $disksize,
												'display_description' => 'a bulkvm volume',
												'metadata' => {'owner' => $owner}
											}
								};
	
		
	# create volume and wait for it to be ready
	#my $disk_hash = nova2hash($nova." volume-create --display-name ".$instname." ".$disksize, 1);
	
	my $try_create=0;
	my $new_volume_hash=undef;
	
	while (not defined $new_volume_hash) {
		$try_create++;
		$new_volume_hash = openstack_api('POST', 'volume', '/volumes', $volume_request_json);
		
		unless (defined $new_volume_hash) {
			
			if ($try_create >= 5) {
				last;
			}
			print STDERR "warning: (volumeCreateWait) new_volume_hash not defined, retry... \n";
			sleep(5);
		}
	}
	unless (defined $new_volume_hash) {
		print STDERR "error: (volumeCreateWait) new_volume_hash not defined \n";
		return 0;
	}
	
	my $new_volume = $new_volume_hash->{'volume'};
	
	my $volume_id = $new_volume->{'id'};
	
	unless (defined $volume_id) {
		print Dumper($new_volume_hash)."\n";
		print STDERR "error: (volumeCreateWait) volume_id not defined \n";
		return 0;
	}
	
	if ($volume_id==0) {
		print Dumper($new_volume_hash)."\n";
		print STDERR "error: (volumeCreateWait) volume_id==0\n";
		return 0;
	}
	
	sleep 3;

	my $status = "";
	my $wait_sec = 0;
	while (lc($status) ne "available") {
		
		my $volume_info = openstack_api('GET', 'volume', '/volumes/'.$volume_id)->{'volume'};
		$status = $volume_info->{'status'};
		
		if (lc($status) eq "error") {
			# delete volume and try again
			print STDERR "error: (volumeCreateWait) volume in error state\n";
			systemp($nova." volume-delete ".$volume_id);
			return 0;
		}
		
		if (lc($status) eq "available") {
			last;
		}
		
		if ($wait_sec > 30) {
			print STDERR "error: volume creation time out\n";
			return 0;
			
		}
		
		sleep 5;
		$wait_sec += 5;
		
	}
	return $volume_id;
}


#########################################################################


sub json_request {
	
	my $type = shift(@_); # 'POST', 'GET'...
	my $uri = shift(@_);
	
	my $json_query_hash;
	if ($type eq 'POST') {
		$json_query_hash = shift(@_);
	}
	
	
	
	my $json;
	if ($type eq 'POST') {
		$json =  JSON::encode_json($json_query_hash ); #'{"username":"foo","password":"bar"}';
		print "json: ".$json."\n";
	}
	print "uri: $uri\n";
	
	
	my $req = HTTP::Request->new( $type, $uri );
	$req->header( 'Content-Type' => 'application/json' );
	
	if (defined $os_token) {
		$req->header( 'X-Auth-Token' => $os_token );
		
		$req->header( 'X-Auth-Project-Id' => 'MG-RAST-DEV' );
		$req->header( 'User-Agent' => 'wolfgang' );
	}
	
	if ($type eq 'POST') {
		$req->content( $json );
	}
		
	
	my $lwp = LWP::UserAgent->new;
	
	$lwp->ssl_opts( verify_hostname => 0 ) ; # disable SSL  # TODO better use certificate
	
	my $res = $lwp->request( $req );
	
	my $ret_hash;
	if ($res->is_success) {
		#print "decoded_content: ".$res->decoded_content."\n\n";
	} else {
		print STDERR "error: (json_request) \"".$res->status_line, "\"\n\n";
		$ret_hash = JSON::decode_json($res->decoded_content);
		
		if (defined $ret_hash->{'badRequest'}) {
			print STDERR "json badRequest messsage: ".$ret_hash->{'badRequest'}->{'message'}||"NA"."\n";
			print STDERR "json badRequest code: ".$ret_hash->{'badRequest'}->{'code'}||"NA"."\n";
		}
		
		if (defined $ret_hash) {
			print Dumper($ret_hash)."\n";
		}
		
		return undef;
		#return $ret_hash;
	}

	#print json_pretty_print($res->decoded_content)."\n\n";
	
	
	$ret_hash = JSON::decode_json($res->decoded_content);
	
	if ($debug==1) {
		print Dumper($ret_hash);
	}
	
	return $ret_hash;
}


sub os_get_token {
	

	# first get token if not already available  TODO: check if token is still valid
	unless (defined $os_token) {
		
		# API: http://api.openstack.org/api-ref.html
		
				
		
		my ($base_url) = $os_auth_url =~ /(https?\:\/\/.*:\d+)/;
		
		unless (defined $base_url) {
			die;
		}
		
		print "base_url: ".$base_url."\n";
		
		
		my $json_query_hash = {
			"auth"  => {"passwordCredentials" => {	"username" => $os_username,
				"password" => $os_password} ,
				"tenantId" => $os_tenant_id # TODO use tenant name ?
			}
		};
		
		
		my $ret_hash = json_request('POST', $base_url."/v2.0/tokens", $json_query_hash);
		
		
		
		print "token: ".$ret_hash->{"access"}->{"token"}->{"id"}."\n";
		
		$os_token =		$ret_hash->{"access"}->{"token"}->{"id"};
		$os_tenant_id = $ret_hash->{"access"}->{"token"}->{"tenant"}->{"id"};
		
		
		#get service uris
		$volume_endpoint_uri=undef;
		$nova_endpoint_uri = undef;
		
		foreach my $service (@{$ret_hash->{"access"}->{"serviceCatalog"}}) {
			#print "service: " .$service."\n";
			print "service_name: " . $service->{'name'} ."\n";
			
			if ( $service->{'name'} eq "nova" ) {
				$nova_endpoint_uri = @{$service->{'endpoints'}}[0]->{'publicURL'};
			} elsif ( $service->{'name'} eq "volume" ) {
				$volume_endpoint_uri = @{$service->{'endpoints'}}[0]->{'publicURL'};
			}
		}
		unless (defined $nova_endpoint_uri) {
			die;
		}
		
	}

	
		
	
}



sub openstack_api {
	
	my $type = shift(@_); # 'POST', 'GET'...
	my $service = shift(@_); # nova, volume etc
	my $path = shift(@_);
	
	my $json_query_hash;
	
	if ($type eq 'POST') {
		$json_query_hash = shift(@_);
	}
	
	
	# make sure we have a token
	os_get_token();
	
	my $uri;
	if ($service eq 'nova') {
		$uri = $nova_endpoint_uri . $path;
	} elsif ($service eq 'volume') {
		$uri = $volume_endpoint_uri . $path;
	} else {
		die;
	}
	#my $json_req_result;
	
	
	my $json_req_result = json_request($type, $uri, $json_query_hash);
	#if ($type eq 'POST') {
	#	$json_req_result = json_request($type, $json_query_hash, $uri);
	#} else {
	#	$json_req_result = json_request($type, $uri);
	#}
	
	
	return $json_req_result;
}

sub os_server_detail_print {
	
	# ID  | Name | Status  | Networks
	my $servers_details = openstack_api('GET', 'nova', '/servers/detail');
	
	
	require Text::ASCIITable;
	
	my $t = Text::ASCIITable->new({ headingText => 'Servers' });
	
	$t->setCols('id', 'name', 'status', 'networks');
	$t->alignCol('networks','left');
	
	my @table;
	my $simple_hash;
	foreach my $server (@{$servers_details->{'servers'}}) {
		
		my @networks;
		foreach my $address (@{$server->{'addresses'}->{'service'}}) {
			push(@networks, $address->{'addr'});
		}
		
		my $server_id = $server->{'id'};
		$simple_hash->{$server_id}->{'name'}		= $server->{'name'};
		$simple_hash->{$server_id}->{'status'}		= $server->{'status'};
		$simple_hash->{$server_id}->{'networks'}	= join(',',@networks);
		$t->addRow( $server->{'id'} , $server->{'name'}, $server->{'status'}, join(',',@networks) );
	}
	
	print $t;
	
}


sub os_flavor_detail_print {
	
	
	my $flavors_detail = openstack_api('GET', 'nova', '/flavors/detail');
	
	#print json_pretty_print($flavors_detail)."\n";
	#return;
	require Text::ASCIITable;
	
	my $t = Text::ASCIITable->new({ headingText => 'Flavors' , chaining => 1 });
	
	$t->setCols('ID', 'Name', 'RAM', 'Disk', 'VCPUs');
	
	
	my @table;
	foreach my $flavor (@{$flavors_detail->{'flavors'}}) {
		 push(@table, [$flavor->{'id'}, $flavor->{'name'}, $flavor->{'ram'}, $flavor->{'disk'}, $flavor->{'vcpus'}]);
	}
	
	@table = sort {$a->[0] <=> $b->[0]} @table;
	
	foreach my $row (@table) {
		$t->addRow($row);
	}
	print $t;
	
}

sub os_images_detail_print {
	
	
	my $images_detail = openstack_api('GET', 'nova', '/images/detail');
	
	#print json_pretty_print($images_detail)."\n";
	#return;
	require Text::ASCIITable;
	
	my $t = Text::ASCIITable->new({ headingText => 'Images' });
	
	$t->setCols('ID', 'Name', 'Status', 'Server');
	
	
	my @table;
	foreach my $image (@{$images_detail->{'images'}}) {
		
		my $server_id="";
		if (defined $image->{'server'}) {
			$server_id = $image->{'server'}->{'id'} || "" ;
		}
		
		push(@table, [$image->{'id'}, $image->{'name'}, $image->{'status'}, $server_id]);
	}
	
	@table = sort {$a->[1] cmp $b->[1]} @table;
	
	foreach my $row (@table) {
		$t->addRow($row);
	}
	print $t;
	
}


sub os_keypairs_print {
	
	
	my $keypairs = openstack_api('GET', 'nova', '/os-keypairs');
	
	#print json_pretty_print($images_detail)."\n";
	#return;
	require Text::ASCIITable;
	
	my $t = Text::ASCIITable->new({ headingText => 'Keypairs' });
	
	$t->setCols('Name', 'Fingerprint');
	
	
	my @table;
	foreach my $keypair (@{$keypairs->{'keypairs'}}) {
		my $key = $keypair->{"keypair"};
			
		push(@table, [$key->{'name'}, $key->{'fingerprint'}]);
	}
	
	@table = sort {$a->[1] cmp $b->[1]} @table;
	
	foreach my $row (@table) {
		$t->addRow($row);
	}
	print $t;
	
}



sub os_floating_ips_print {
	
	my $floating_ips = openstack_api('GET', 'nova', '/os-floating-ips');
	
	
	#print Dumper($floating_ips);
	#return;
	
	require Text::ASCIITable;
	
	my $t = Text::ASCIITable->new({ headingText => 'Floating IPs' });
	
	$t->setCols('IP', 'Instance ID', 'Fixed IP', 'Pool');
	$t->alignCol('IP','left');
	$t->alignCol('Fixed IP','left');
	
	my @table;
	foreach my $floating_ip (@{$floating_ips->{'floating_ips'}}) {
		
		push(@table, [$floating_ip->{'ip'}, $floating_ip->{'instance_id'}||"None", $floating_ip->{'fixed_ip'}||"None", $floating_ip->{'pool'}||"None"]);
	}
	
	#@table = sort {$a->[1] cmp $b->[1]} @table;
	
	foreach my $row (@table) {
		$t->addRow($row);
	}
	print $t;
	
}

sub json_pretty_print {
	
	my $json_text = shift(@_);
	
	my $json2 = JSON->new->allow_nonref;
	
	my $pretty_printed = $json2->pretty->encode( $json2->decode($json_text) ); # pretty-printing
	
	return $pretty_printed;
	
}




sub info {
	my $printtable = 1;
	
	#my $my_volumes = openstack_api('GET', 'volume', '/volumes');
	#print Dumper($my_volumes);

	
	os_flavor_detail_print();
	#my $nova_flavor_list = nova2hash($nova." flavor-list", $printtable);
	
	os_images_detail_print();
	#my $nova_image_list = nova2hash($nova." image-list", $printtable);
	
	
	os_keypairs_print();
	#my $nova_keypair_list = nova2hash($nova." keypair-list", $printtable);
	
	
	os_floating_ips_print();
	#my $nova_floating_ip_list = nova2hash($nova." floating-ip-list", $printtable);
	
	
	os_server_detail_print();
	#my $nova_list = nova2hash($nova." list", $printtable);

	
		
}

# deprecated !
sub create {
	
	print STDERR "warning: use of deprecated subroutine \"create\"\n";
	exit(1);
	
	my $arg_hash={};
	
	
	$arg_hash->{"flavor_name"} = shift(@_);
	$arg_hash->{"count"} = shift(@_);
	$arg_hash->{"name"} = shift(@_);
	$arg_hash->{"disksize"} = shift(@_);
	$arg_hash->{"wantip"} = shift(@_);
	#$arg_hash->{"flavor_name"} = shift(@_);
	
	
	
	my $iplist = createNew($arg_hash);
	return $iplist;
	
}


sub createAndAddToHash {
	my $arg_hash = shift(@_);
	
	if (defined $arg_hash->{"iplist"}) {
		die;
	}
	
	my $iplist_ref = createNew($arg_hash);
	
	$arg_hash->{"iplist"} = $iplist_ref;
	return;
}


sub createNew {
	my $arg_hash = shift(@_);
	
	
	
	
	
	my $flavor_name = $arg_hash->{"flavor_name"};
	my $count = $arg_hash->{"create"} || die "error: create (count) not defined\n";
	my $groupname = $arg_hash->{"groupname"}|| die "error: groupname not defined\n";
	my $disksize = $arg_hash->{"disksize"} || 0;
	my $wantip = $arg_hash->{"wantip"} || 0;
	
	#$image = $arg_hash->{"image"} || $image;
	
	if (defined $arg_hash->{"image"} && defined $arg_hash->{"image_name"}) {
		print STDERR "error: image and image_name defined, please define only one.\n";
		return undef;
	}
	
	
	if (defined $arg_hash->{"iplist"}) {
		print STDERR "error: cannot combine iplist and create\n";
		return undef;
	}
	
	
	
	my $images_detail = openstack_api('GET', 'nova', '/images/detail');
	
	my $image_id = $arg_hash->{"image"};
	my $image_name;
	unless (defined $image_id) {
		$image_name = $arg_hash->{"image_name"} || $image_name;
		print "searching for image with name \"$image_name\"\n";
		
		
		foreach my $image_object (@{$images_detail->{'images'}}) {
			
			if ($image_object->{'name'} eq $image_name) {
				if (defined $image_id) {
					print "error: image_name \"$image_name\" not unique. Use image ID with --image instead.\n";
					return undef;
				}
				
				$image_id=$image_object->{'id'};
			}
		}

		unless (defined $image_id) {
			print "error: image_id undefined \n";
			return undef;
		}
		
		$arg_hash->{"image"} = $image_id
	}
	
	
	
	#print $image_name."\n";
	print "using image id: ".$image_id."\n";
	#exit(1);
	
	my $key_name = $arg_hash->{"key_name"};
	unless (defined $key_name) {
		print "error: key_name undefined \n";
		return undef;
	}
	my $sshkey = $arg_hash->{"sshkey"};
	unless (defined $sshkey) {
		print "error: sshkey undefined \n";
		return undef;
	}

	
	#$ssh_options = "-o StrictHostKeyChecking=no -i $sshkey";
	my $ssh = "ssh $ssh_options -i $sshkey";
	my $scp = "scp $ssh_options -i $sshkey";
	
	unless (defined $flavor_name) {
		print STDERR "error: flavor_name not defined\n";
		return undef;
	}
	
	
	my $printtable = 0;
	
	
	my $flavors_detail = openstack_api('GET', 'nova', '/flavors/detail');
	
	
	
	
	my $keypairs = openstack_api('GET', 'nova', '/os-keypairs');
		
	my $found_keypair=0;
	foreach my $keypair (@{$keypairs->{'keypairs'}}) {
		if ($keypair->{'keypair'}->{'name'} eq $key_name) {
			$found_keypair=1;
			last;
		}
	}
	
	if ($found_keypair == 0) {
		print STDERR "error: keypair $key_name not found\n";
		return undef;
	}
	
	
	
	
	
	
	
	my $servers_details = openstack_api('GET', 'nova', '/servers/detail');

	
	
	if ($wantip == 1 && $count > 1) {
		print STDERR "will not give external IP for more than one instance\n";
		return undef;
	}
	
	my @nameslist;
	if (defined $arg_hash->{"namelist"}) {
		@nameslist = split(',', $arg_hash->{"namelist"});
		
	} else {
		@nameslist = @{$default_namelist};
		
	}
		
	# shuffle name if module is installed
	my $module = "List::Util";
	if (try_load($module)) {
		print "loaded\n";
		#print join(",", @nameslist)."\n";
		@nameslist = List::Util::shuffle(@nameslist);
		#print join(",", @nameslist)."\n";
	}

	
	
	#$flavorname
	# map flavor_name to flavor_id
	my $flavor_id=undef;
	
	unless (defined $flavor_id) {
		foreach my $flavor (@{$flavors_detail->{'flavors'}}) {
			if ($flavor->{'name'} eq $flavor_name) {
				
				if (defined $flavor_id) {
					print STDERR "error: flavor_name is not unique\n";
					exit(1);
				}
				
				$flavor_id=$flavor->{'id'};
			}
		}
		unless (defined $flavor_id) {
			print STDERR "error: could not find flavour name \"".$flavor_name."\"\n";
			return undef;
		}
		
	}
	$arg_hash->{"flavor_id"} = $flavor_id;
		
	if (length($groupname) <= 4) {
		print STDERR "error: name \"$groupname\" too short\n";
		return undef;
	}
	
	my %names_used;
	
	foreach my $server (@{$servers_details->{'servers'}}) {
		if ($server->{'name'} =~ /^$groupname/ ) {
			if (defined $arg_hash->{"nogroupcheck"}) {
				my ($old_name) = $server->{'name'} =~ /^$groupname\_(\S+)/;
				unless (defined $old_name) {
					print STDERR "group-specific instance name not found:".$server->{'name'}."\n";
					exit(1);
				}
				$names_used{$old_name}=1;
			} else {
				print "error: an instance with that groupname already exists, groupname: $groupname\n";
				print "name: ".$server->{'name'}." ID: ".$server->{'id'}."\n";
				return undef;
			}
		}
	}
	
	# remove names already used from nameslist;
	if (defined $arg_hash->{"nogroupcheck"}) {
		my @tmp_names=();
		if (defined $arg_hash->{"nogroupcheck"}) {
			for (my $i = 0; $i < @nameslist; $i++) {
				unless (defined($names_used{$nameslist[$i]})) {
					push(@tmp_names, $nameslist[$i]);
				} else {
					print STDERR "name already used: ".$nameslist[$i]."\n";
				}
				
			}
		}
		@nameslist=@tmp_names;
	}
	
	my $max_threads = 8;
	
	my $manager = new Parallel::ForkManager( ($max_threads, $count)[$max_threads > $count] ); # min 5 $count
	
	my @children_iplist=();
	
	#$SIG{CHLD} = sub{  Parallel::ForkManager::wait_children($manager) };
	$manager->run_on_finish(
	sub {
		
		my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $data_structure_reference) = @_;
		
		unless (defined $ident) {
			$ident = "undefined";
		}
		
		if ($exit_code != 0 ) {
			print "\n-----------\njob finished\n";
			print "pid: $pid\n";
			print "exit_code: $exit_code\n";
			
			
			print "ident: $ident\n";
			
			if ( $core_dump ) {
				print "core_dump: $core_dump\n";
				print "exit_signal: $exit_signal\n";
				
			}
			
			if (defined $data_structure_reference) {
				print "child $ident returned: \"".$$data_structure_reference."\"\n";
			} else {
				print "child $ident returned nothing\n";
			}
			print "-----------\n\n";
		
			print STDERR "Child exited with exit_code != 0. Stop whole script. Be aware that other VM probably are still running.\n";
			
			die;
		}
		
		if (defined $data_structure_reference) {
			print "child $ident returned: \"".$$data_structure_reference."\"\n";
			push(@children_iplist , $$data_structure_reference) ;
		} else {
			print "child $ident returned nothing\n";
		}
		
		return;
	}
	);
	
	for (my $i=0 ; $i < $count; $i++) {
		
		########## CHILD START ############
		$manager->start($i) and next;
		
		my ($return_value, $return_data_ref) = createSingleServer($arg_hash, $i , $ssh, $scp, \@nameslist);
				
		$manager->finish($return_value, $return_data_ref);
		########## CHILD END ############
	}
	

	
	
	
	my $active = 0;
	my $build = 0;
	while ($active < $count) {
		#$nova_list = nova2hash($nova." list", 0);
		my $servers_details = openstack_api('GET', 'nova', '/servers/detail');
		$active = 0;
		$build = 0;
		#foreach my $id (keys %$nova_list) {
		foreach my $server (@{$servers_details->{'servers'}}) {
			
			if ($server->{'name'} =~ /^$groupname/ ) {
				#print "got: ".$nova_list->{$id}{Status}."\n";
				if ($server->{'status'} eq "ACTIVE") {
					$active++;
				} elsif ($server->{'status'} eq "BUILD") {
					$build++;
				}
			}
		}
		print "requested instances: ".$count.", BUILD: ".$build.", ACTIVE: ".$active."\n";
		if ($active != $count) {
			print "wait few seconds..\n";
			sleep 5;
		}
		
		if (-e "STOPBULKJOBS") {
			print STDERR "error: At least one job requested an emergency stop. See previous error message for details.\n";
			system("rm -f STOPBULKJOBS");
			
			
			exit(1);
		}
		
	}
	
	print "all jobs should have finished by now.\n";
	
	
	print "createVMs: to be sure, wait for the last children to finish...\n";
	$manager->wait_all_children;
	

	
	if (defined $arg_hash->{"saveIpToFile"}) {
		
		saveIpToFile($groupname, $sshkey, \@children_iplist);
	}
	
	return \@children_iplist;
}

sub createSingleServer {
	
	# no tests here anymore
	my $arg_hash = shift(@_);
	my $child_number = shift(@_);
	my $ssh = shift(@_);
	my $scp = shift(@_);
	my @nameslist = @{shift(@_)};
	
	my $groupname = $arg_hash->{"groupname"};
	my $image_id = $arg_hash->{"image"};
	my $flavor_id = $arg_hash->{"flavor_id"};
	my $key_name = $arg_hash->{"key_name"};
	my $count = $arg_hash->{"create"};
	my $disksize = $arg_hash->{"disksize"} || 0;
	my $wantip = $arg_hash->{"wantip"} || 0;
	
	
	
	my $return_value;
	my $return_data;
	
	#major components (delete if fails)
	my $instance_id;
	my $volume_id;
	my $newip;
	
	my $instance_ip;
	
	my $crashed = 0;
	my $crashed_final = 0;
	
	my $try_counter = 0;
	MAINWHILE: while (1) {
		$try_counter++;
		
		# delete stuff from previous crash
		if ($crashed == 1 || $crashed_final==1) {
			print STDERR "delete previous instance since something went wrong...\n";
			if (defined $instance_id) {
				systemp($nova." delete ".$instance_id);
			}
			
			
			
			if (defined $volume_id) {
				if ($volume_id ==0 ) {
					print STDERR "error: volume_id==0 should not happen\n";
					exit(1);
				}
				
				my $volshow = nova2hash($nova." volume-show ".$volume_id, 0);
				while ($volshow->{'status'}{'Value'} ne 'available' ) {
					sleep 5;
					$volshow = nova2hash($nova." volume-show ".$volume_id, 0);
				}
				systemp($nova." volume-delete ".$volume_id);
			}
			
			if (defined $newip) {
				systemp($nova." floating-ip-delete ".$newip);
			}
			$instance_id=undef;
			$volume_id=undef;
			$newip=undef;
			$crashed = 0;
			sleep 20;
		}
		
		if ($try_counter > 3 ) {
			print STDERR "instance creation failed three times. Stop.\n";
			system("touch STOPBULKJOBS");
			return undef;
		}
		
		if ( $crashed_final==1) {
			print STDERR "instance creation stopped with critical error.\n";
			system("touch STOPBULKJOBS");
			return undef;
		}
		
		# create name for new instance
		my $instname=$groupname;
		
		unless (defined ($arg_hash->{"onlygroupname"}) ) {
			$instname .= "_";
			if (defined $nameslist[$child_number]) {
				$instname .= $nameslist[$child_number];
			} else {
				$instname .= $child_number;
			}
		}
		
		#start instance
		#my $servers_details = openstack_api('GET', 'nova', '/servers/detail');
		
		my $owner = $arg_hash->{"owner"} || $os_username;
		
		my $create_parameter_hash = {	'tenant_id' => $os_tenant_id,
										'imageRef' => $image_id,
										'flavorRef' => $flavor_id,
										'key_name' => $key_name,
										'name' => $instname,
										'metadata' => {'owner' => $owner}
										#'max_count' => 1,
										#'min_count' => 1
		};
		
		
		if (defined $arg_hash->{"user-data"}) {
			$create_parameter_hash->{'user-data'} = $arg_hash->{"user-data"};
		}
		
		
		# create server (do not wait here)
		my $create_servers = openstack_api('POST', 'nova', '/servers', { 'server' => $create_parameter_hash});
		
		unless (defined $create_servers) {
			print STDERR "error: server creation failed\n";
			$crashed_final = 1;
			next MAINWHILE;
		}
			
		$instance_id = $create_servers->{'server'}->{'id'};
		unless (defined $instance_id) {
			$crashed_final = 1;
			next MAINWHILE;
		}
		
		#create volume
		if ($disksize > 0) {
			
			$volume_id = volumeCreateWait($instname, $disksize, $arg_hash->{"owner"});
			if ($volume_id == 0 ) {
				print STDERR "error: volume_id==0\n";
				$volume_id=undef;
				$crashed =1;
				next MAINWHILE;
			}
			
			
		}
		
		
		
		# now wait for the new server
		my $new_server = openstack_api('GET', 'nova', '/servers/'.$instance_id);
		my $wait_sec = 0;
		while ($new_server->{'server'}->{'status'} ne "ACTIVE") {
			
			if ($wait_sec > 60) {
				print STDERR "error: ACTIVE wait > 60\n";
				$crashed = 1;
				next MAINWHILE;
			}

			
			if ($new_server->{'server'}->{'status'} eq "ERROR") {
				print Dumper($new_server);
				print STDERR "error: new instance in status ERROR!\n";
				if ($new_server->{'server'}->{'OS-EXT-STS:task_state'} eq 'scheduling') {
					print STDERR "error: new instance is in ERROR state while scheduling\n";
					$crashed_final = 1;
					next MAINWHILE;
				}
				
				
				if (exists $new_server->{'server'}->{'fault'}) {
					foreach my $hashkey (keys(%{$new_server->{'server'}->{'fault'}})) {
						print STDERR "ERRORMESSAGE: $hashkey : ".$new_server->{'server'}->{'fault'}->{$hashkey}."\n";
					}
				}
				$crashed = 1;
				next MAINWHILE;
			}
			
			sleep(5);
			$wait_sec += 5;
			$new_server = openstack_api('GET', 'nova', '/servers/'.$instance_id);
		}
		# new server is ACTIVE now.
		
		
		
		# get local IP of instance
		my $server_address_private = $new_server->{'server'}->{'addresses'}->{'private'};
		
		# not clear to me if 'private' or 'service'
		unless(defined $server_address_private) {
			$server_address_private = $new_server->{'server'}->{'addresses'}->{'service'};
		}
		
		unless(defined $server_address_private) {
			print Dumper($new_server);
			print STDERR "error: server_address_private and server_address_service not defined \n";
			$crashed_final = 1;
			next MAINWHILE;
		}
		
		my @private_addresses = @{$server_address_private};
		
		if (@private_addresses == 0) {
			print STDERR "error: private_addresses == 0 \n";
			$crashed_final = 1;
			next MAINWHILE;
		}
		
		my $instance_ip_hash = $private_addresses[0];
		
		if ($instance_ip_hash->{'version'} ne '4') {
			print STDERR "error: instance_ip_hash->\{version\} ne 4\n";
			$crashed_final = 1;
			next MAINWHILE;
		}
		
		my $instance_ip = $instance_ip_hash->{'addr'};
		
		unless ($instance_ip =~ /^10\.0\.\d+\.\d+$/) {
			print STDERR "error: instance_ip format wrong \"$instance_ip\" \n";
			$crashed_final = 1;
			next MAINWHILE;
		}
		
		
		# remove IP from .ssh/known_hosts file
		my $known_hosts = $ENV{"HOME"}."/.ssh/known_hosts";
		
		if (-e $known_hosts) {
			
			my $lock = new File::Flock $known_hosts;
			systemp('ssh-keygen'." -f \"$known_hosts\"". " -R ".$instance_ip);
			#systemp('ssh-keygen', "-f \"$known_hosts\"", "-R ".$instance_ip); # I do not understand why this does not work.
			
			$lock->unlock();
		} 
		
		
		my $remote = "$vm_user\@$instance_ip";
		
		# wait for real ssh connection
		SubmitVM::connection_wait($ssh, $remote, 400);
		sleep 5;
		
		#my $date = `date \"+\%Y\%m\%d \%T\"`;
		#chop($date);
		#SubmitVM::remote_system($ssh, $remote, "sudo date --set=\\\"".$date."\\\"") || print STDERR "error setting date/time\n";
		SubmitVM::setDate($ssh, $remote);
		
		my $device = "/dev/vdc";
		my $volumeattach;
		
		my $data_dir_exists = SubmitVM::remote_system($ssh, $remote, "test -d /home/$vm_user/data"); # 0 exists , 1 does not exists !
		# warning test command does not allow slash at end of directory!!!!
		print "data_dir_exists : $data_dir_exists\n";
				
		
		
		if ($disksize > 0) {
			
	
			
			my $data_dir_is_symlink = SubmitVM::remote_system($ssh, $remote, "test -L /home/$vm_user/data");
			print "data_dir_is_symlink: $data_dir_is_symlink\n";
					
			if ($data_dir_exists && ! $data_dir_is_symlink ) {
				print STDERR "error: you requested to attach disk, but /home/$vm_user/data/ already exists and is not symlink!\n";
				# as long as data/ is empty simply do rmdir and continue !?
				
				exit(1);
			}
			
			if ($data_dir_exists && $data_dir_is_symlink) {
				SubmitVM::remote_system($ssh, $remote, "rm -f /home/$vm_user/data");
			}
			
			$data_dir_exists = SubmitVM::remote_system($ssh, $remote, "test -d /home/$vm_user/data");
			
			if ($data_dir_exists) {
				print STDERR "error: B you requested to attach disk, but /home/$vm_user/data/ already exists!\n";
				# as long as data/ is empty simply do rmdir and continue !?
				exit(1);
			}

			
			
			#  attach volume to instance
			if (volumeAttachWait($instance_id, $volume_id, $device) == 0 ){
				print STDERR "error: vol-attach-wait\n";
				$crashed = 1;
				next MAINWHILE;
			}
			
			
			# create partition and mount volume
			my $partmount = SubmitVM::remote_perl_function(	$ssh , $scp, $remote,
			sub {
				my $data_hash_ref = shift(@_);
				my $remoteDataDir = $data_hash_ref->{"remoteDataDir"};
				my $disksize = $data_hash_ref->{"disksize"};
				my $vm_user = $data_hash_ref->{"vm_user"};
				
				#print "remoteDataDir: $remoteDataDir\n";
				
				my $systemp = sub {
					print join(' ', @_)."\n";
					return system(@_);
				};
				
				# create partion, make filesystem, mount etc. and check afterwards
				my $ret;
				my $crashed = 0;
				my $mytime=0;
				my $device = undef;
				while (1) {
					
					my $partitions = `cat /proc/partitions`;
					
					my @partition_array = split('\n', $partitions);
					
					foreach my $line (@partition_array) {
						my ($major,$minor,$blocks, $devicename) = $line =~ /(\d+)\s+(\d+)\s+(\d+)\s+(\S+)/;
						
						
						
						if (defined $major) {
							unless (defined $devicename) {
								print STDERR "devicename not defined\n";
								print STDERR "$line\n";
								return "error";
							}
							
							print "$devicename $blocks $disksize ".($disksize * 1000000)."\n";
							if ($blocks > ($disksize * 1000000)) {
								$device = "/dev/".$devicename;
								last;
							}
							
						}
						
					}
					
					if (defined $device) {
						print STDERR "device found: $device\n";
						last;
					}
					
					
					print STDERR "device not found...\n";
					
					
					if ($mytime > 180) {
						print STDERR "error: device not found\n";
						$crashed = 1;
						last;
					}
					
					$mytime+=5;
					sleep 5;
				}
								#"/dev/vdc\t/mnt2\tauto\tdefaults,nobootwait,comment=cloudconfig\t0\t2"
				while (1) {
					
					if ($crashed == 1) {
						last;
					}
					#prepare volume
					$systemp->("echo -e \"o\\nn\\np\\n1\\n\\n\\nt\\n83\\nw\" | sudo fdisk $device")==0 or do {print STDERR "error: fdisk\n"; $crashed = 1;};
					$systemp->("sudo mkfs.ext3 $device")==0 or do {print STDERR "error: mkfs\n";$crashed = 1; next;};
					
					#mount volume
					$systemp->("sudo mkdir /mnt2/")==0 or do {print STDERR "error: mkdir mnt2\n";$crashed = 1; next;};
					my $count_fstab  = `grep -c \"\^$device\" /etc/fstab`;
					
					if ($count_fstab == 0) {
						$systemp->("sudo su -c \"echo \'/dev/vdc\t/mnt2\tauto\tdefaults,nobootwait,comment=cloudconfig\t0\t2\' >> /etc/fstab\"");
					}
					#$systemp->("sudo mount $device /mnt2/")==0 or do {print STDERR "error: mount\n";$crashed = 1; next;};
					system("sudo mount -a")==0 or do {print STDERR "error: mount\n";$crashed = 1; next;};
					$systemp->("sudo chmod 777 /mnt2")==0 or do {print STDERR "error: chmod \n";$crashed = 1; next;};
					$systemp->("ln -s /mnt2 /home/$vm_user/data")==0 or do {print STDERR "error: ln\n";$crashed = 1; next;};
					
					sleep 2;
					my ($mountlines) = `df -h | grep $device | wc -l` =~ /(\d+)/;
					unless (defined $mountlines) {
						print STDERR "error: undefined mountlines\n";
						$crashed = 1;
						next;
					}
					if ($mountlines != 1) {
						print STDERR "error: disk not mounted: $ssh $remote\n";
						$crashed = 1;
						next;
					}
					
					last;
				}
				if ($crashed == 1 ) {
					return "error";
				}
			}
			,
			{	"remoteDataDir" => '/home/$vm_user/',
				"disksize" => $disksize,
				"vm_user" => $vm_user}
			);
			
			if ($partmount =~ /error/) {
				print "partmount:\n \"$partmount\" \n partmount end\n";
				print STDERR "error: partmount reported error\n";
				$crashed = 1;
				next;
			}
			
			
			
		} else {
			# create data directory
			
			unless ($data_dir_exists) {
				SubmitVM::remote_system($ssh, $remote, "ln -s /mnt/ /home/$vm_user/data") or do {print STDERR "error: ln\n"; $crashed = 1; next;};
			}
			SubmitVM::remote_system($ssh, $remote, "sudo chmod 777 /home/$vm_user/data") or do {print STDERR "error: chmod\n"; $crashed = 1; next;};
			
		}
		
		
		
		if ($wantip == 1) {
			
			my $totaltime=0;
			while (! defined $newip) {
				$newip = getIP();
				if (! defined $newip) {
					if ($totaltime >= $timeout ) {
						print STDERR "error: IP request timeout!\n";
						$crashed = 1;
						last;
					}
					print "IP request failed, try again in a few seconds...\n";
					$totaltime += 5;
					sleep 5;
				}
			}
			if ($crashed ==1) {
				next;
			}
			print "newip: $newip\n";
			if ($count > 1) {
				systemp($nova."  add-floating-ip ".$groupname.$child_number." $newip");
			} else {
				systemp($nova."  add-floating-ip ".$groupname." $newip");
			}
		}
		
		
		$return_value = 0;
		$return_data = $instance_ip;
		last;
	} # end while
	
	return ($return_value, \$return_data)
}

sub saveGroupInIpFile {
	my $arg_hash = shift(@_);
	
	my $groupname = $arg_hash->{'groupname'} || die;
	my $sshkey = $arg_hash->{'sshkey'} || die;
	
	my $group_iplist = list_group($groupname);
	
		
	saveIpToFile($groupname, $sshkey, $group_iplist);
}

sub saveIpToFile {
	my ($groupname, $sshkey , $ip_ref) = @_;
	
	
	my @total_ip_list = @$ip_ref;
	my $iplistfile = $groupname."_iplist.txt";
	
	my $arg_hash={};
	if (-e $iplistfile) {
		print "found previous ipfile $iplistfile, will add iplist to that file\n";
		read_config_file($arg_hash, $iplistfile);
		if ($arg_hash->{"groupname"} eq $groupname) {
			push(@total_ip_list, split(',', $arg_hash->{"iplist"}));
		} else {
			print STDERR "warning: groupname in previous ipfile not the same as current groupname!\n";
		}
	}
	
	
	open (MYFILE, '>'.$iplistfile);
	print MYFILE "groupname=$groupname\n";
	print MYFILE "sshkey=$sshkey\n";
	print MYFILE "iplist=".join(',',@total_ip_list)."\n";
	close (MYFILE);
	
	print "##########################\n";
	print "your new instances are: ".join(',',@$ip_ref)."\n";
	print "This list has been saved in file \"$iplistfile\".\n";
	
}

#verify that all IPs have correct groupname, use option nogroupcheck to diable check
sub deletebulk {
	
	my $arg_hash = shift(@_);
	
	my $owner = $arg_hash->{"owner"} || $os_username;
	
	unless(defined $arg_hash->{"iplist"}) {
		print STDERR "error: (deletebulk) iplist not defined\n";
		exit(1);
	}
	
	
	my $groupname = $arg_hash->{"groupname"};
	
	unless (defined $groupname) {
		print STDERR "error: groupname not defined, refuse to delete only based on IP\n";
		exit(1);
	}
	
	if (length($groupname) < 4) {
		print STDERR "error: groupname too short, at least 4 characters\n";
		exit(1);
	}

	print "groupname: $groupname\n";
	
	
	
	
	
	my $nova_floating_ip_list = nova2hash($nova." floating-ip-list", 1);
	my $volumelist = nova2hash($nova." volume-list", 1);
	
	my $instanceId_to_volumeId;
	foreach my $vol_id (keys %$volumelist) {
		my $instid = $volumelist->{$vol_id}{"Attached to"};
		
		unless (defined $instid) {
			#print "found undefined\n";
			next;
		}
		$instanceId_to_volumeId->{$instid}=$vol_id;
		
	}
	
	
	
	my $servers_detail = openstack_api('GET', 'nova', '/servers/detail');
	if (defined $servers_detail->{'servers'}) {
		$servers_detail = $servers_detail->{'servers'};
	} else {
		die;
	}
	
	my $ip_to_server_hash;
	my $id_to_server_hash;
	
	foreach my $server (@{$servers_detail}) {
		my $id = $server->{'id'};
		unless (defined $id) {
			print STDERR "warning: id not defined for server\n";
			next;
		}
	
		if (lc($server->{'status'}) eq "error") {
			print STDERR "warning: server is in error status, name=".$server->{'name'}." id=$id\n";
			next;
		}
		
		my $instancename = $server->{'name'};
		
		
		# get local IP of instance
		my $server_address_private = $server->{'addresses'}->{'private'};
		
		# not clear to me if 'private' or 'service'
		unless(defined $server_address_private) {
			$server_address_private = $server->{'addresses'}->{'service'};
		}
		
		
		unless(defined $server_address_private) {
			print STDERR "warning: server_address_private not defined, name=".$server->{'name'}."\n";
			next;
		}
		
		my @private_addresses = @{$server_address_private};
		
		if (@private_addresses == 0) {
			print STDERR "warning: private_addresses == 0 \n";
			next;
		}
		
		my $instance_ip_hash = $private_addresses[0];
		
		if ($instance_ip_hash->{'version'} ne '4') {
			print STDERR "warning: instance_ip_hash->\{version\} ne 4\n";
			next;
		}
		
		my $ip = $instance_ip_hash->{'addr'};
		
		unless ($ip =~ /^10\.0\.\d+\.\d+$/) {
			print STDERR "warning: ip format not ok \"$ip\"\n";
			next;
		}
		
		if (defined $ip) {
			$ip_to_server_hash->{$ip} = $server;
			$id_to_server_hash->{$id} = $server;
		} else {
			print STDERR "warning: ip not defined\n";
			next;
		}
	}
	
	my $delcount =0;
	
	my @ip_array = split(',',join(',', @{$arg_hash->{"iplist"}}));
	
		
	my @id_list=();
	foreach my $ip (@ip_array) {
		
		unless (defined $ip_to_server_hash->{$ip}) {
			print STDERR "error: ip $ip is unknown\n";
			exit(1);
		}
		
		
		unless(defined $arg_hash->{"nogroupcheck"}) {	
			if (substr($ip_to_server_hash->{$ip}->{'name'}, 0, length($groupname)) ne $groupname) {
				print STDERR "error: groupname is not a prefix of instance name:\n";
				print STDERR "groupname: " .$groupname."\n";
				print STDERR "instance name: " .$ip_to_server_hash->{$ip}->{'name'}."\n";
				print STDERR "instance ip: " .$ip."\n";
				exit(1);
			}
		}
		
		unless (defined $arg_hash->{"noownercheck"} ) {
			my $vm_owner = $ip_to_server_hash->{$ip}->{'metadata'}->{'owner'};
			unless (defined $vm_owner) {
				print STDERR "error: ".$ip_to_server_hash->{$ip}->{'name'}." has no owner\n";
				print STDERR "use option --noownercheck only if you know what you do.\n";
				exit(1);
			}
			if ($vm_owner ne $owner) {
				print STDERR "error: ".$ip_to_server_hash->{$ip}->{'name'}." , you do not seem to be owner of this vm. owner: $owner vm_owner: $vm_owner\n";
				print STDERR "use option --noownercheck only if you know what you do.\n";
				exit(1);
			}
		}
		
		push(@id_list, $ip_to_server_hash->{$ip}->{'id'});
	}
	
	if (@id_list != @ip_array) {
		print STDERR "error: \@id_list != \@ip_array: ".@id_list." ".@ip_array."\n";
		exit(1);
	}
	
	foreach my $id (@id_list) {
	
		
		my $instancename = $id_to_server_hash->{$id}->{'name'};
		
		if ($instancename =~ /^$groupname/ ) {
			
			print "delete ".$instancename." (".$id.")\n";
			
			#search IP
			my $oldip = undef;
			foreach my $ip (keys %$nova_floating_ip_list) {
				my $instid = $nova_floating_ip_list->{$ip}{"Instance Id"};
				unless (defined $instid) {
					#print "\"Instance Id\" not found for $ip !?\n";
					next;
				}
				if ($instid eq $id) {
					$oldip = $ip;
					last;
				}
				
			}
			
			
			#print STDERR "keys in hash: ".join(',', keys %$volumelist)."\n";
			#search volume
			my $volume_id = $instanceId_to_volumeId->{$id};
			
			
			
			# delete instance
			systemp($nova." delete ".$id);
			$delcount++;
			
			# delete ip
			if (defined $oldip) {
				systemp($nova." floating-ip-delete ".$oldip);
			}
			
			#delete volume
			if (defined $volume_id) {
				#my $volshow = nova2hash($nova." volume-show ".$volume_id, 0);
				if (waitNovaHashValue("volume-show $volume_id", "status", "Value", "available", 5, 30) == 1){
					systemp($nova." volume-delete ".$volume_id);
				} else {
					print STDERR "error: could not delete vol $volume_id\n";
				}
			} 
			
			
				
			
		}
		
		
	}
	

	return $delcount;
}

sub list_group_print {
	my $arg_hash = shift(@_);
	my $iplist_ref = ManageBulkInstances::list_group($arg_hash->{"groupname"});
	print "iplist=".join(',', @{$iplist_ref})."\n";
	
	return;
}

sub list_group {
	my $groupname = shift(@_);
	
	unless (defined $groupname) {
		print STDERR "error: groupname not defined\n";
		exit(1);
	}
	
	my $nova_list = nova2hash($nova." list", 1);
	
	my @iplist=();
	
	foreach my $id (keys %$nova_list) {
		my $instancename = $nova_list->{$id}{Name};
		
		if ($instancename =~ /^$groupname/ ) {
			
			#print "found ".$instancename." (".$id.")\n";
			
			#print $nova_list->{$id}{Networks}."\n";
			
			my ($ip) = $nova_list->{$id}{Networks} =~ /10\.0\.(\d+\.\d+)/;
			unless (defined $ip) {
				print STDERR "warning: no internal IP found for instance $id ($instancename)...\n";
				next;
			}
			push(@iplist, "10.0.".$ip);
			print "10.0.".$ip." ".$instancename."\n";
			
			
		}
		
	}
	
	
	return \@iplist;
} 


