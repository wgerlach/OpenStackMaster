#!/usr/bin/env perl


package ManageBulkInstances;

use strict;
use warnings;

eval "use Parallel::ForkManager 0.7.6; 1"
	or die "module required: sudo apt-get install build-essential ; perl -MCPAN -e \'install Parallel::ForkManager\'";

eval "use File::Flock; 1"
	or die "module required: sudo apt-get install libfile-flock-perl \n OR perl -MCPAN -e \'install File::Flock\'";

#use Parallel::ForkManager 0.7.6;
#new version: sudo apt-get install build-essential ; perl -MCPAN -e 'install Parallel::ForkManager'
#old version: sudo apt-get install libparallel-forkmanager-perl

use lib $ENV{"HOME"}."/projects/libraries/"; # path to SubmitVM module
use SubmitVM;
use Getopt::Long;
use List::Util qw(first);

eval "use LWP::UserAgent; 1"
or die "module required: cpan install LWP::UserAgent";

eval "use JSON; 1"
	or die "module required: cpan install JSON";
use Data::Dumper;

eval "use Text::ASCIITable; 1"
or die "module required: cpan install Text::ASCIITable";


# purpose of this module: wrapper for nova tools



##############################
# parameters

#my $image = "b24d27d8-146c-4eea-9153-378d2642959d";
#my $image_name = "w_base_snapshot"; # or "Ubuntu Precise 12.04 (Preferred Image)"
#our $key_name = "dmnewmagellanpub";
#our $sshkey = "~/.ssh/dm_new_magellan.pem";


my $os_tenant_name = $ENV{'OS_TENANT_NAME'}; # tenant name or tenant ID needs to defined.	
my $os_tenant_id = $ENV{'OS_TENANT_ID'};
my $os_username = $ENV{'OS_USERNAME'};
my $os_password = $ENV{'OS_PASSWORD'};
my $os_auth_url = $ENV{'OS_AUTH_URL'};




my $ssh_options = "-o StrictHostKeyChecking=no"; # StrictHostKeyChecking=no because I am too lazy to check for the question.

my $vm_user = 'ubuntu';

my @hobbitlist = ("Frodo","Samwise","Meriadoc","Peregrin","Gandalf","Aragorn","Legolas","Gimli","Denethor","Boromir","Faramir","Galadriel","Celeborn","Elrond","Bilbo","Theoden","Eomer","Eowyn","Treebeard");

my $default_namelist = \@hobbitlist;


#deprecated
our $nova = "nova --insecure --no-cache ";


my $os_token;


my $nova_endpoint_uri;
my $volume_endpoint_uri;

my $timeout=30;

my $debug=0;

our $options_basicactions = ["Nova actions",
							"create=i"		=> "create i new instances from snapshot/image" ,			\&createAndAddToHash,
#TODO "createtemp=i"		=> "create i new instances from snapshot/image" ,			\&createAndAddToHashAndDelete, # perl object with destroyer
							"delete"		=> "use with --group,ipfile or iplist",						\&deletebulk,
							"reboot=s"		=> "reboot all instances, \"soft\" or \"hard\"",				\&reboot,
							"info"			=> "list all instances, volumes, flavors...",				\&info,
							"listgroup=s"	=> "list all instances in this group (must be owner)",		\&list_group_print,
							"list"		=> "list all instances by group or instance_names/ip/id",			\&list_ips_print,
							"savegroup=s"	=> "save group in ipfile",									\&saveGroupInIpFile,
							"newgroupname=s" => "rename group (will not change hostname!)",				\&renameGroup
							] ;

our $options_vmactions = ["VM actions",
							"sshtest"		=> "try to ssh all instances",								undef
							] ;

our $options_create_opts = ["Create options",
							"flavor_name=s"	=> "flavor name for hardware selection",					undef,
							"image=s"		=> "image identifier",										undef,
							"image_name=s"	=> "image name, as alternative to image identifer", 		undef,
							#"sshkey=s"		=> "required, path to ssh key file",						undef,
							"key_name=s"	=> "ssh key_name as in Openstack",							undef,
							"groupname=s"	=> "required, name of the new group",						undef,
							"nogroupcheck"	=> "use this to add VMs to existing group",					undef,
							"onlygroupname"	=> "instance names all equal groupname",					undef,
							"namelist=s"	=> "comma-separated list of names to choose from",			undef,
							"owner=s"		=> "optional, metadata information on VM, default os_username",	undef,
							"disksize=i"	=> "in GB, creates, attaches, partitions and mounts volume",undef,
							"wantip"		=> "external IP, only with count=1",						undef,
							"user-data=s"	=> "pass user data file to new instances",					undef,
							"saveIpToFile"	=> "saves list of IPs in file",								undef,
							"greedy"		=> "continue with VM creation, even if some fail",			undef,
							"to_srv_create=s" => "timeout server create",			undef
							];



our $options_specify = [	"Specify existing VMs for actions and deletion",
							#"ipfile=s"		=> "file containing list of ips with names",				undef,
							"group=s"		=> "use VMs with this groupname (metadata-field)",			undef,
							"instance_names=s" => "VMs with these names, requires --groupname",			undef,
							"instance_ids=s" => "VMs with these IDs, requires --groupname",			undef,
							"instance_ips=s"	=> "list of IPs, comma separated, use with --groupname",		undef
							];

our $options_other_opts = ["Other options",
							"noownercheck"	=> "disables owner check",									undef
];

our @options_all = ($options_basicactions, $options_vmactions, $options_create_opts, $options_other_opts, $options_specify);

##############################
# subroutines

sub deploy {
	SubmitVM::deploy(@_);
}

sub renameGroup {
	my $arg_hash = shift(@_);
	
	unless (defined $arg_hash->{'newgroupname'} ) {
		die;
	}
	my $newgroupname = $arg_hash->{'newgroupname'};
	
	
	
	my $server_hash = ManageBulkInstances::get_instances_by_hash( $arg_hash , {'return_hash' => 1} );
	
	
	
	my $groupname;
	if (defined $arg_hash->{"group"}) {
		$groupname = $arg_hash->{"group"};
	}
	
	if (defined $arg_hash->{"groupname"}) {
		$groupname = $arg_hash->{"groupname"};
	}
	
	print "would rename these guys=".join(',', keys(%$server_hash))."\n";
	
	#my $servers_details = openstack_api('GET', 'nova', '/servers/detail');
	
	my %names_used;
	# get list of used names and complain if groupname is already beeing used
	
	foreach my $server_id (keys(%$server_hash)) {
		
		my $old_name = $server_hash->{$server_id}->{'name'};
		unless (defined $old_name) {
			print STDERR "error: old name not found\n";
			exit(1);
		}
		
		unless ($old_name =~ /^$groupname/i) {
			print STDERR "error: old groupname $groupname do not match ($old_name)\n";
			exit(1);
		}
		
		my ($name_suffix) = $old_name =~ /^$groupname\_(\S+)$/i;
		
		
		unless (defined $name_suffix) {
			print STDERR "error: name suffix not found\n";
			exit(1);
		}
		
		$names_used{lc($name_suffix)}=1;
		
	}
	
	my @nameslist;
	if (defined $arg_hash->{"namelist"}) {
		@nameslist = split(',', $arg_hash->{"namelist"});
	} else {
		@nameslist = @{$default_namelist};
	}
	
	# remove names already used from nameslist;
	my @tmp_names=();
	for (my $i = 0; $i < @nameslist; $i++) {
		unless (defined($names_used{lc($nameslist[$i])})) {
			push(@tmp_names, $nameslist[$i]);
		} 
	}
	@nameslist=@tmp_names;
	
	
	
	
	my $suffix_name_counter = 1;
	foreach my $server_id (keys(%$server_hash)) {
		
		
		my $server = $server_hash->{$server_id};
		
		my $old_name = $server->{'name'};
		unless (defined $old_name) {
			print STDERR "error: old name not found\n";
			exit(1);
		}
		
		unless ($old_name =~ /^$groupname/i) {
			print STDERR "error: old groupname $groupname do not match ($old_name)\n";
			exit(1);
		}
		
		my ($name_suffix) = $old_name =~ /^$groupname\_(\S+)$/i;
		
		
		my $new_instance_name = $newgroupname;
		
		
		unless (defined $arg_hash->{'onlygroupname'}) {
			unless (defined $name_suffix) {
				die;
			}
			
			if (defined($names_used{lc($name_suffix)}) || 1) {
				#change name !
				my $new_suffix_name;
				if (@nameslist > 0) {
					$new_suffix_name = shift(@nameslist);
				} else {
					$new_suffix_name = $suffix_name_counter;
					while (defined($names_used{$new_suffix_name})) {
						$suffix_name_counter++;
						$new_suffix_name = $suffix_name_counter;
					}
				}
				print STDERR "info: rename instance from $name_suffix to $new_suffix_name\n";
				
				$name_suffix = $new_suffix_name;
			}
			
			$new_instance_name .= '_'.$name_suffix;
		}
					
		
		
		print "new instance name: $new_instance_name and new group: $newgroupname\n";
		
		# chnage instance name
		my $new_name_json = {	'server' => {'name'  => $new_instance_name}};
		my $ret_hash = openstack_api('PUT', 'nova', '/servers/'.$server_id, $new_name_json);
		#print Dumper($ret_hash);
	
		# confirm change
		unless (defined($ret_hash->{'server'}->{'name'}) && lc($ret_hash->{'server'}->{'name'}) eq lc($new_instance_name)) {
			print Dumper($ret_hash);
			print STDERR "error: instance name not changed\n";
			exit(1);
		}
		
				
		#change metadata field group
		my $new_metadata_json ={'metadata' => {'group' => $newgroupname } } ;
		$ret_hash = openstack_api('POST', 'nova', '/servers/'.$server_id.'/metadata', $new_metadata_json);
		#print Dumper($ret_hash);
		
		
		unless (defined($ret_hash->{'metadata'}->{'group'}) && lc($ret_hash->{'metadata'}->{'group'}) eq lc($newgroupname)) {
			print Dumper($ret_hash);
			print STDERR "error: metadata field not changed\n";
			exit(1);
		}
		
				
		if (0) { # ugly
			
			my $key_name = $server->{'key_name'};
			
			unless (defined $key_name) {
				print Dumper($server);
				exit(1);
			}
			
			my $sshkey = get_ssh_key_file($key_name);
			
			my $ssh = "ssh $ssh_options -i $sshkey";
			my $scp = "scp $ssh_options -i $sshkey";
			
			my $server_address_private = $server->{'ip'};
			
			my $remote = "$vm_user\@$server_address_private";
			
			
			my $newhostname = $new_instance_name;
			$newhostname =~ s/[^0-9a-zA-Z]/-/g;
			
			
			SubmitVM::remote_system($ssh, $remote, "cat /etc/hostname");
			
			#change hostname
			SubmitVM::remote_system($ssh, $remote, "sudo echo $newhostname > /etc/hostname");
			
			
			SubmitVM::remote_system($ssh, $remote, "cat /etc/hostname");
			
			SubmitVM::remote_system($ssh, $remote, "sudo service hostname start");
			
		}
		
	}
	
	
	
	
}

sub get_ssh_key_file {
	my $key_name = shift(@_);
	
	my $key_file = $ENV{HOME}."/.ssh/".$key_name ; #.".pem";
	#print "A $key_file\n";

	if ( -e $key_file ) {
		print "key_name: $key_name , file: $key_file\n";
		return $key_file;
	}
	# try .pem-file
	my $pemkey_file = $key_file.'.pem';
	
	if ( -e $pemkey_file ) {
		print "key_name: $key_name , file: $pemkey_file\n";
	} else {
		print "error: did not find the private ssh keyfile $key_file (or $pemkey_file) for key_name $key_name\n";
		print "either rename your private key or create a symlink in ~/.ssh/\n";
		exit(1);
	}
	return $pemkey_file;
}

sub parallell_job_new {
	my $arg_hash = shift(@_);
	
	print "parallell_job_new: ".join(',', keys(%$arg_hash))."\n";
	
	my $server_hash = ManageBulkInstances::get_instances_by_hash( $arg_hash , {'return_hash' => 1} );
	
	
	unless (defined $arg_hash->{"username"}) {
		$arg_hash->{"username"} = $vm_user;
	}
	
	
	#my $owner=$arg_hash->{"os_username"}||$os_username;
	#my $group = $arg_hash->{"group"} || $arg_hash->{"groupname"};
	
	#unless(defined($arg_hash->{"vmips_ref"})) { # TODO find a solution for vmips_ref. then remove the IP-to-key_name mapping
		
	#	my $group_iplist = ManageBulkInstances::get_instances( $arg_hash );
		
	#	$arg_hash->{"vmips_ref"} = $group_iplist;
	#}
	
	

	my @iplist = ();
	
	#get IP-to-key_name mapping:
	my $ip_to_key_mapping={};
	my $key_name_to_key_file={};
	#my $servers_details = openstack_api('GET', 'nova', '/servers/detail');
	#foreach my $server (@{$servers_details->{'servers'}}) {
	foreach my $server_id (keys(%$server_hash)) {
		my $server = $server_hash->{$server_id};
		my $key_name = $server->{'key_name'};
		unless (defined $key_name) {
			die;
		}
		my $ip = $server->{'ip'};
		unless (defined $ip) {
			die;
		}
		push(@iplist, $ip);
		#my $vm_owner = $server->{'metadata'}->{'owner'};
		#my $vm_group = $server->{'metadata'}->{'group'};
		
		#unless (defined $vm_owner) {
		#	next;
		#}
		
		#unless (defined $vm_group) {
		#	next;
		#}
		
		#unless (lc($vm_owner) eq lc($owner)) {
		#	next;
		#}
		#if (defined $group) {
		#	unless (lc($vm_group) eq lc($group)) {
		#		next;
		#	}
		#}
		
		$key_name_to_key_file->{$key_name}=1;
		
		#my @networks;
		#foreach my $address (@{$server->{'addresses'}->{'service'}}) {
		#	$ip_to_key_mapping->{$address->{'addr'}} = $key_name;
		#}
		$ip_to_key_mapping->{$ip} = $key_name;
		
	}
	
	foreach my $key_name (keys($key_name_to_key_file)) {
		#print "got key: $key_name\n";
	
		$key_name_to_key_file->{$key_name} = get_ssh_key_file($key_name);
		#print "B\n";
	}
	
	my $ip_to_keyfile={};
	foreach my $ip (keys(%$ip_to_key_mapping)) {
		my $key_name = $ip_to_key_mapping->{$ip};
		my $keyfile = $key_name_to_key_file->{$key_name};
		$ip_to_keyfile->{$ip} = $keyfile;
	}
	
	
	#exit(0);
	
	if (@iplist == 0 ) {
		print STDERR "error: (parallell_job_new) iplist empty\n";
		exit(1);
	}
	
	my $result = SubmitVM::parallell_job_new(
		{	"vmips_ref" => \@iplist, #$arg_hash->{"vmips_ref"},
			"vmargs_ref" => $arg_hash->{"vmargs_ref"},
			"function_ref" => $arg_hash->{"function_ref"},
			"ip_to_keyfile" => $ip_to_keyfile,
			"username" => $arg_hash->{"username"}
		}
	);
	
	
	if (defined $arg_hash->{"delete"}) { # this will not be set by command line but by script.
		deletebulk($arg_hash);
	}
	
	return $result;
}

#example my $value = get_nested_hash_value($hash, 'name', '1', [key,value] or {($_->{$key}||"") eq $val});
# returns value, if last step is [key,value], it returns array
sub get_nested_hash_value {
	my $hash_ref = shift(@_);
	
	my @route = @_;
	
	my $h = $hash_ref;
	
	#foreach my $value (@route) {
	for ( my $i = 0 ; $i < @route ; ++$i) {
		my $value = $route[$i];
		#print "operation $i \n";
		if (ref($h) eq "HASH") {
			#print "operation_hash\n";
			$h = $h->{$value};
			unless (defined $h) {
				return undef;
			}
		} elsif (ref($h) eq "ARRAY") {
			#print "operation_array\n";
			if (ref($value)) {
				# value is reference to tuple
				
				my @matches;
				if (ref($value) eq "ARRAY") {
					my ($key, $val) = @{$value};
					#print "operation_array type array\n";
					@matches = grep( ($_->{$key}||"") eq $val , @{$h});
				} elsif (ref($value) eq "CODE") {
					#print "operation_array type code\n";
					@matches = grep( $value , @{$h});
				} else {
					print STDERR "ref: ".ref($value)."\n";
					die;
				}
					
					
					
				if ($i == @route-1) {
					return @matches;
				} else {
					if (@matches == 0) {
						print STDERR "error: no matching array element with (i=$i)\n";
						return undef;
					} elsif (@matches == 1) {
						$h = shift(@matches);
					} else {
						print Dumper($hash_ref);
						print STDERR "error: array element is not unique (i=$i)\n";
						print STDERR "count: ".@matches."\n";
						
						return undef;
					}
				}

				
			} else {
				# value (scalar) is a position in array
				$h = @{$h}[$value];
			}
			
			unless (defined $h) {
				return undef;
			}
			
		} else {
			die;
		}
		
	}
	
	return $h;
	
}


sub runActions { # disable action by overwriting subroutine reference with "undef"
	my $arg_hash_ref = shift(@_);
	my $options_array_ref = shift(@_);
	
	my $action_results = {};
	
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
					my $result = ${$option_group}[$i+2]($arg_hash_ref);
					
					if (defined $result) {
						$action_results->{$option} = $result;
					}
				}
				
			}
			
		}
	}

	
	return $action_results;
	
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
	
	print Dumper($arg_hash_ref)."\n";
	
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
	print "read configuration from ".$config_file."\n"; 
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
			#unless (defined $arg_hash->{$config_key}) {
				if ($config_key eq "iplist") { # ugly
					my @iparray = split(/,/ , $config_value);
					$arg_hash->{$config_key} = \@iparray;
				} else {
					unless (defined $arg_hash->{$config_key}) {
						print "write configuration: ".$config_key." ".$config_value."\n";
						$arg_hash->{$config_key} = $config_value;
					}
				}
				print "use configuration: ".$line."\n";
			#}
			
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

#deprecated
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
	
	# if no IP found, try to request a new one:
	my $post_floating_ips= openstack_api('POST', 'nova', '/os-floating-ips', { 'pool' => 'nova'});
	
	$newip = $post_floating_ips->{'floating_ip'}->{'ip'};
	
	unless (defined $newip) {
		print STDERR "warning: IP allocation failed\n";
	}
	
	return $newip;
}

sub delete_IP {
	
	my $ip = shift(@_);
	
	
	my $floating_ips_hash = openstack_api('GET', 'nova', '/os-floating-ips');
	
	my @ip_ids = get_nested_hash_value($floating_ips_hash, ['ip',$ip]);
	
	if (@ip_ids == 0) {
		print STDERR "warning: did not find ID for ip $ip\n";
	} elsif (@ip_ids > 1) {
		print STDERR "warning: found mulitple IDs for ip $ip\n";
	} else {
		my $ip_id = shift(@ip_ids);
		my $ip_del = openstack_api('DELETE', 'nova', '/os-floating-ips/'.$ip_id);
	}
}

sub systemp {
	print join(' ', @_)."\n";
	return system(@_);
}

#depecated
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

#depecated
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

sub delete_volume {
	my $volume_id = shift(@_);
	
	my $vol_timeout = 0;
	# wait until available before deleting it
	while ( 1) {
		
		
		my $vol_info = openstack_api('GET', 'volume', '/volumes/'.$volume_id);
		unless (defined $vol_info) {
			print STDERR "error: no vol info returned\n";
			return undef;
		}
		my $vol_status = $vol_info->{'volume'}->{'status'};
		
		unless (defined $vol_status) {
			print STDERR "error: not volume status returned\n";
			return undef;
		}
		
		if ($vol_status eq 'available') {
			last;
		} else {
			print "volume status: $vol_status (volume id: $volume_id)\n";
		}
		
		if ($vol_timeout > 60) {
			print STDERR "error: A) delete volume timeout\n";
			return undef;
		}
		sleep 5;
		$vol_timeout+=5;
		
	}
	
	#delete volume
	my $vol_del = openstack_api('DELETE', 'volume', '/volumes/'.$volume_id, {'volume_id'=>$volume_id} );
	
	# wait until volume is gone
	$vol_timeout = 0;
	while(1) {
		my $volumes = openstack_api('GET', 'volume', '/volumes/detail');
		 
		if (defined $volumes) {
			my @vol = get_nested_hash_value($volumes, 'volumes', ['id', $volume_id]);
			
			if (@vol == 0) {
				last;
			} else {
				my $volume = shift(@vol);
				
				my $vol_status =  $volume->{'status'} || "NA";
				
				print STDERR "volume still exists.. wait... (status: $vol_status)\n";
				
			}
		} else {
			print STDERR "warning: /volumes/detail was not returned\n";
			
		}
		if ($vol_timeout > 60) {
			print STDERR "error: B) delete volume timeout\n";
			return undef;
		}
		
		sleep 5;
		$vol_timeout+=5;
	}
	
	
	return $vol_del;
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
			
			
			my $volume_delete = openstack_api('DELETE', 'volume', '/os-volumes/'.$volume_id); #TODO wait for success
			
			
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
	if ($type eq 'POST' || $type eq 'PUT') {
		$json_query_hash = shift(@_);
	}
	
	
	
	my $json;
	if ($type eq 'POST' || $type eq 'PUT') {
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
	
	if ($type eq 'POST' || $type eq 'PUT') {
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
		
		eval {
			$ret_hash = JSON::decode_json($res->decoded_content);
			1;
		} or do {
			my $e = $@;
			print STDERR "$e\n";
		};
		
		if ( defined($ret_hash) ) {
		
			if ( defined($ret_hash->{'badRequest'}) ) {
				print STDERR "json badRequest messsage: ".$ret_hash->{'badRequest'}->{'message'}||"NA"."\n";
				print STDERR "json badRequest code: ".$ret_hash->{'badRequest'}->{'code'}||"NA"."\n";
			}
		
		
			print Dumper($ret_hash)."\n";
		}
		
		return undef;
		#return $ret_hash;
	}

	#print json_pretty_print($res->decoded_content)."\n\n";
	
	
	
	
	if ($type eq 'DELETE') {
		return 1;
	}
	
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
		
		unless (defined $os_auth_url) {
			print STDERR "error: os_auth_url not defined.\n";
			exit(1);
		}
		
		my ($base_url) = $os_auth_url =~ /(https?\:\/\/.*:\d+)/;
		
		unless (defined $base_url) {
			die;
		}
		
		print "base_url: ".$base_url."\n";
		
		
		my $json_query_hash = {
			"auth"  => {"passwordCredentials" => {	"username" => $os_username,
													"password" => $os_password } }
		};
		
		if (defined $os_tenant_name) {
			$json_query_hash->{'auth'}->{'tenantName'} = $os_tenant_name;
		} elsif (defined $os_tenant_id) {
			$json_query_hash->{'auth'}->{'tenantId'} = $os_tenant_id;
		} else {
			print STDERR "error: os_tenant_name or os_tenant_id needs to be defined.\n";
			exit(1);
		}
		
		my $ret_hash = json_request('POST', $base_url."/v2.0/tokens", $json_query_hash);
		
		
		
		#print "token: ".$ret_hash->{"access"}->{"token"}->{"id"}."\n";
		
		$os_token =	$ret_hash->{"access"}->{"token"}->{"id"};
		
		unless (defined $os_token) {
			print Dumper($ret_hash)."\n";
			print STDERR "error: did not get openstack API token.\n";
			exit(1);
		}
		
		$os_tenant_id = $ret_hash->{"access"}->{"token"}->{"tenant"}->{"id"};
		$os_tenant_name = $ret_hash->{"access"}->{"token"}->{"tenant"}->{"name"};
		
		#get service uris
				
		
		$nova_endpoint_uri   = get_nested_hash_value($ret_hash, 'access' , 'serviceCatalog' , ['name','nova'  ], 'endpoints' , '0', 'publicURL');
		unless (defined $nova_endpoint_uri) {
			die;
		}
		$volume_endpoint_uri = get_nested_hash_value($ret_hash, 'access' , 'serviceCatalog' , ['name','volume'], 'endpoints' , '0', 'publicURL');

		unless (defined $volume_endpoint_uri) {
			die;
		}
		
	}

	
		
	
}



sub openstack_api {
	
	my $type = shift(@_); # 'POST', 'GET'...
	my $service = shift(@_); # nova, volume etc
	my $path = shift(@_);
	
	my $json_query_hash;
	
	if ($type eq 'POST' || $type eq 'PUT') {
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
	
	my ($flavor_id_to_size) = shift(@_);
	
	unless (defined $flavor_id_to_size) {
		die;
	}
	
	# ID  | Name | Status  | Networks
	my $servers_details = openstack_api('GET', 'nova', '/servers/detail');
	
	
	#require Text::ASCIITable;
	
	my $t = Text::ASCIITable->new({ headingText => 'Servers' });
	
	$t->setCols('id', 'name', 'status', 'networks', 'owner', 'group');
	$t->alignCol('networks','left');
	
	my $ram_used = 0;
	my $cpu_used = 0;
	my $instances_used=0;
	
	my @table;
	#my $simple_hash;
	foreach my $server (@{$servers_details->{'servers'}}) {
		$instances_used++;
		
		#print Dumper($server);
		#exit(0);
		
		my @networks;
		foreach my $address (@{$server->{'addresses'}->{'service'}}) {
			push(@networks, $address->{'addr'});
		}
		
		my $server_id = $server->{'id'};
		my $owner = $server->{'metadata'}->{'owner'} || "";
		my $group = $server->{'metadata'}->{'group'} || "";
		
		if (defined $flavor_id_to_size) {
			my $f_id = $server->{'flavor'}->{'id'};
			if (defined $f_id) {
				$ram_used += $flavor_id_to_size->{$f_id}->{'ram'};
				$cpu_used += $flavor_id_to_size->{$f_id}->{'vcpus'};
			}
		} else {
			die;
		}
		
		
		#$simple_hash->{$server_id}->{'name'}		= $server->{'name'};
		#$simple_hash->{$server_id}->{'status'}		= $server->{'status'};
		#$simple_hash->{$server_id}->{'networks'}	= join(',',@networks);
		$t->addRow( $server->{'id'} , $server->{'name'}, $server->{'status'}, join(',',@networks), $owner , $group);
	}
	
	print $t;
	
	if (defined $flavor_id_to_size) {
		
		
		my $tenant_quota = openstack_api('GET', 'nova', '/os-quota-sets/'.$os_tenant_id);
		#print Dumper($tenant_quota);
		my $tenant_quota_ram =			get_nested_hash_value($tenant_quota, 'quota_set', 'ram');
		my $tenant_quota_cores =		get_nested_hash_value($tenant_quota, 'quota_set', 'cores');
		my $tenant_quota_instances =	get_nested_hash_value($tenant_quota, 'quota_set', 'instances');
		
		my $t2 = Text::ASCIITable->new({ headingText => "Resources ($os_tenant_name)" });
		
		$t2->setCols('resource', 'quota', 'used', 'available');
		
		$t2->addRow( 'instances' ,$tenant_quota_instances, $instances_used, ($tenant_quota_instances-$instances_used));
		$t2->addRow( 'CPU' , $tenant_quota_cores, $cpu_used, ($tenant_quota_cores-$cpu_used));
		$t2->addRow( 'RAM (GB)' , int($tenant_quota_ram/1024), int($ram_used/1024), int((($tenant_quota_ram-$ram_used)/1024)) );
		
		
		#print "RAM        -- quota: $tenant_quota_ram used: $ram_used available: ".($tenant_quota_ram-$ram_used)."\n";
		#print "CPU        -- quota: $tenant_quota_cores used: $cpu_used available: ".($tenant_quota_cores-$cpu_used)."\n";
		#print "instances  -- quota: $tenant_quota_instances used: $instances_used available: ".($tenant_quota_instances-$instances_used )."\n";
		#exit(0);
		print $t2;
		
	}
	
}


sub os_flavor_detail_print {
	
	
	my $flavors_detail = openstack_api('GET', 'nova', '/flavors/detail');
	
	#print json_pretty_print($flavors_detail)."\n";
	#return;
	#require Text::ASCIITable;
	
	my $t = Text::ASCIITable->new({ headingText => 'Flavors' , chaining => 1 });
	
	$t->setCols('ID', 'Name', 'RAM', 'Disk', 'VCPUs');
	
	
	my $flavor_id_to_size={};
	
	my @table;
	foreach my $flavor (@{$flavors_detail->{'flavors'}}) {
		 push(@table, [$flavor->{'id'}, $flavor->{'name'}, $flavor->{'ram'}, $flavor->{'disk'}, $flavor->{'vcpus'}]);
		$flavor_id_to_size->{$flavor->{'id'}} = {'ram' => $flavor->{'ram'}, 'vcpus' => $flavor->{'vcpus'}};
	}
	
	@table = sort {$a->[0] <=> $b->[0]} @table;
	
	foreach my $row (@table) {
		$t->addRow($row);
	}
	print $t;
	unless (defined $flavor_id_to_size) {
		die;
	}
	
	return $flavor_id_to_size;
}

sub os_images_detail_print {
	
	
	my $images_detail = openstack_api('GET', 'nova', '/images/detail');
	
	#print json_pretty_print($images_detail)."\n";
	#return;
	#require Text::ASCIITable;
	
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
	#require Text::ASCIITable;
	
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
	
	#require Text::ASCIITable;
	
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
	
	my $flavor_id_to_size = os_flavor_detail_print();
	
	unless (defined $flavor_id_to_size) {
		die;
	}
	
	os_images_detail_print();
	
	os_keypairs_print();
	
	os_server_detail_print($flavor_id_to_size);
	
	#print "List of floating IPs is always a bit slow, sorry...\n";
	#os_floating_ips_print();
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
	
	unless (defined $iplist_ref) {
		print STDERR "error: create failed.\n";
		exit(1);
	}
	
	$arg_hash->{"iplist"} = $iplist_ref;
	unless (defined $arg_hash->{"group"}) {
		$arg_hash->{"group"} = $arg_hash->{"groupname"};
	}
	return;
}

#example:
#my $ip_list = createNew({	'flavor_name'	=> 'idp.06',
#							'image_name'	=> 'Ubuntu Precise 12.04 (Preferred Image)',
#							'count'			=> 2,
#							'sshkey'		=> 'your_ssh_key_file.pem',
#							'key_name'		=> 'name of your ssh key stored in OpenStack',
#							'groupname'		=> 'myinstances',
#							'disksize'		=> 500				# 500GB, in case you need nore than the default 10 or 300GB
#						})
sub createNew {
	my $arg_hash = shift(@_);
	
	print "createNew\n";
	
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
		
		my @image_objects = get_nested_hash_value($images_detail, 'images', ['name', $image_name]);
		
		if (@image_objects == 0) {
			print "error: image_id undefined \n";
			return undef;
		} elsif (@image_objects == 1) {
			my $image_object = $image_objects[0];
			$image_id=$image_object->{'id'};
		} else {
			print "error: image_name \"$image_name\" not unique. Use image ID with --image instead.\n";
			return undef;
		}

		
		
		$arg_hash->{"image"} = $image_id;
	}
	
	
	
	#print $image_name."\n";
	print "using image id: ".$image_id."\n";
	#exit(1);
	
	my $key_name = $arg_hash->{"key_name"};
	unless (defined $key_name) {
		print "error: (createNew) key_name undefined \n";
		return undef;
	}
	
	my $sshkey = get_ssh_key_file($key_name);
	
	my $ssh = "ssh $ssh_options -i $sshkey";
	my $scp = "scp $ssh_options -i $sshkey";
	
	unless (defined $flavor_name) {
		print STDERR "error: flavor_name not defined\n";
		return undef;
	}
	
	
	my $printtable = 0;
	
	
	my $flavors_detail = openstack_api('GET', 'nova', '/flavors/detail');
	
	
	
	# check keypair
	my $keypairs = openstack_api('GET', 'nova', '/os-keypairs');
	
	my ($this_keypair) = get_nested_hash_value($keypairs, 'keypairs', sub {($_->{'keypair'}->{'name'}||"") eq $key_name});
		
	unless (defined $this_keypair) {
		print Dumper($keypairs);
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
		#print "loaded\n";
		#print join(",", @nameslist)."\n";
		@nameslist = List::Util::shuffle(@nameslist);
		#print join(",", @nameslist)."\n";
	}

	
	
	#$flavorname
	# map flavor_name to flavor_id
	my $flavor_id=undef;
	
	unless (defined $flavor_id) {
		
		my @flavor_objects = get_nested_hash_value($flavors_detail, 'flavors', ['name', $flavor_name]);
		
		
		if (@flavor_objects ==0) {
			print STDERR "error: could not find flavour name \"".$flavor_name."\"\n";
			return undef;
		} elsif (@flavor_objects ==1) {
			my $flavor_obj = shift(@flavor_objects);
			$flavor_id=$flavor_obj->{'id'};
		} else {
			print STDERR "error: flavor_name \"".$flavor_name."\" is not unique\n";
			return undef;
		}
		
		unless (defined $flavor_id) {
			print STDERR "error: could not find flavour name \"".$flavor_name."\"\n";
			return undef;
		}
		
	}
	$arg_hash->{"flavor_id"} = $flavor_id;
	
	print "flavor_id: $flavor_id\n";
	
	if (length($groupname) <= 4) {
		print STDERR "error: name \"$groupname\" too short\n";
		return undef;
	}
	
	my %names_used;
	# get list of used names and complain if groupname is already beeing used
	foreach my $server (@{$servers_details->{'servers'}}) {
		if ($server->{'name'} =~ /^$groupname/i ) {
			unless (defined $arg_hash->{"nogroupcheck"}) {
				print "error: an instance with that groupname already exists, groupname: $groupname\n";
				print "disable this error message with --nogroupcheck\n";
				print "name: ".$server->{'name'}." ID: ".$server->{'id'}."\n";
				return undef;
			}
			
			my ($old_name) = $server->{'name'} =~ /^$groupname\_(\S+)/i;
			if (defined $old_name) {
				$names_used{$old_name}=1;
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
	print "create Parallel::ForkManager object\n";
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
	
	print "start $count thread".($count==1)?'':'s'."\n";
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
		
		my $servers_details = openstack_api('GET', 'nova', '/servers/detail');
		$active = 0;
		$build = 0;
		
		foreach my $server (@{$servers_details->{'servers'}}) {
			
			if ($server->{'name'} =~ /^$groupname/i ) {
				
				if ($server->{'status'} eq "ACTIVE") {
					$active++;
				} elsif ($server->{'status'} eq "BUILD") {
					$build++;
				}
			}
		}
		print "requested instances: ".$count.", BUILD: ".$build.", ACTIVE: ".$active."\n";
		if ($active != $count) {
			print "waiting for all VMs to be in ACTIVE status...\n";
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
		saveIpToFile($arg_hash, \@children_iplist);
	}
	
	return \@children_iplist;
}


sub getServerIP {
	
	my $server = shift(@_);
	# get local IP of instance
	my $server_address_private = $server->{'addresses'}->{'private'};

	# not clear to me if 'private' or 'service'
	unless(defined $server_address_private) {
		$server_address_private = $server->{'addresses'}->{'service'};
	}
	
	return $server_address_private;
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
				
				my $delete_result = openstack_api('DELETE', 'nova', '/servers/'.$instance_id, { 'server_id' => $instance_id});
				
			}
			
			
			
			if (defined $volume_id) {
				if ($volume_id ==0 ) {
					print STDERR "error: volume_id==0 should not happen\n";
					exit(1);
				}
				
				delete_volume($volume_id);
				
			}
			
			if (defined $newip) {
				delete_IP($newip);
			}
			
			$instance_id=undef;
			$volume_id=undef;
			$newip=undef;
			$crashed = 0;
			sleep 20;
		}
		
		if ($try_counter > 3 ) {
			print STDERR "instance creation failed three times. Stop.\n";
			unless (defined $arg_hash->{'greedy'}) {
				system("touch STOPBULKJOBS");
			}
			return undef;
		}
		
		if ( $crashed_final==1) {
			print STDERR "instance creation stopped with critical error.\n";
			unless (defined $arg_hash->{'greedy'}) {
				system("touch STOPBULKJOBS");
			}
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
										'metadata' => {'owner' => $owner, 'group' => $groupname}
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
			if (defined $arg_hash->{"greedy"}) {
				return (0);
			}
			$crashed_final = 1;
			next MAINWHILE;
		}
			
		$instance_id = $create_servers->{'server'}->{'id'};
		unless (defined $instance_id) {
			print STDERR "error: server creation failed, no id found\n";
			if (defined $arg_hash->{"greedy"}) {
				return (0);
			}
			
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
		
		
		my $timeout_server_create = $arg_hash->{"to_srv_create"} || 180;
		
		# now wait for the new server
		my $new_server = openstack_api('GET', 'nova', '/servers/'.$instance_id);
		my $wait_sec = 0;
		while ($new_server->{'server'}->{'status'} ne "ACTIVE") {
			
			if ($wait_sec > $timeout_server_create) {
				print STDERR "error: ACTIVE wait > $timeout_server_create\n";
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
		
		
		my $server_address_private = getServerIP($new_server->{'server'});
		
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
		my $wait_result = SubmitVM::connection_wait($ssh, $remote, 400, 0);
		
		if ($wait_result == 0) {
			$crashed_final = 1;
			next MAINWHILE;
		}
		
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
				my $mountpoint = '/mnt2';
								#"/dev/vdc\t/mnt2\tauto\tdefaults,nobootwait,comment=cloudconfig\t0\t2"
				while (1) {
					
					if ($crashed == 1) {
						last;
					}
					#prepare volume
					$systemp->("echo -e \"o\\nn\\np\\n1\\n\\n\\nt\\n83\\nw\" | sudo fdisk $device")==0 or do {print STDERR "error: fdisk\n"; $crashed = 1;};
					$systemp->("sudo mkfs.ext3 $device")==0 or do {print STDERR "error: mkfs\n";$crashed = 1; next;};
					
					#mount volume
					$systemp->("sudo mkdir ".$mountpoint."/")==0 or do {print STDERR "error: mkdir ".$mountpoint."\n";$crashed = 1; next;};
					my $count_fstab  = `grep -c \"\^$device\" /etc/fstab`;
					
					if ($count_fstab == 0) {
						$systemp->("sudo su -c \"echo \'/dev/vdc\t".$mountpoint."\tauto\tdefaults,nobootwait,comment=cloudconfig\t0\t2\' >> /etc/fstab\"");
					}
					#$systemp->("sudo mount $device ".$mountpoint."/")==0 or do {print STDERR "error: mount\n";$crashed = 1; next;};
					system("sudo mount -a")==0 or do {print STDERR "error: mount\n";$crashed = 1; next;};
					$systemp->("sudo chmod 777 ".$mountpoint)==0 or do {print STDERR "error: chmod \n";$crashed = 1; next;};
					$systemp->("ln -s ".$mountpoint." /home/$vm_user/data")==0 or do {print STDERR "error: ln\n";$crashed = 1; next;};
					
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
				unless(defined $newip) {
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
			print "newip: $newip\n"; # $instance_ip
			my $add_ip = openstack_api('POST', 'nova', '/servers/'.$instance_ip.'/action', {'addFloatingIp' => {'address' => $newip}});
			
		}
		
		
		$return_value = 0;
		$return_data = $instance_ip;
		last;
	} # end while
	
	return ($return_value, \$return_data);
}

sub saveGroupInIpFile {
	my $arg_hash = shift(@_);
	
	my $group = $arg_hash->{'savegroup'} || die;
	$arg_hash->{'groupname'} = $group; # TODO ugly! group vs groupname
	
	my $owner = $arg_hash->{'owner'} || die;
	
	#my $group_iplist = list_group($owner, $group);
	my $group_iplist = ManageBulkInstances::get_instances( {	'owner' => $owner, 'group' => $arg_hash->{"group"}} );
	
	saveIpToFile($arg_hash, $group_iplist);
}

sub saveIpToFile {
	#my ($groupname, $sshkey, $key_name, $ip_ref) = @_;
	
	my ($arg_hash, $ip_ref) = @_;
	
	
	my $groupname = $arg_hash->{'groupname'} || die;
	my $sshkey = $arg_hash->{'sshkey'} || die;
	my $key_name = $arg_hash->{'key_name'} || die;
	
	my $owner = $arg_hash->{"owner"} || $os_username;
	my $tenant = $arg_hash->{"tenant"} || $os_tenant_name;
	
	my @total_ip_list = @$ip_ref;
	my $iplistfile = $groupname."_iplist.txt";
	
	#my $arg_hash={};
	if (-e $iplistfile) {
		print "found previous ipfile $iplistfile, will add iplist to that file\n";
		read_config_file($arg_hash, $iplistfile);
		if ($arg_hash->{"groupname"} eq $groupname) {
			push(@total_ip_list, split(',', $arg_hash->{"iplist"}));
		} else {
			print STDERR "warning: groupname in previous ipfile not the same as current groupname!\n";
		}
	}
	
	### write ipfile
	open (MYFILE, '>'.$iplistfile);
	print MYFILE "groupname=$groupname\n";
	print MYFILE "sshkey=$sshkey\n";
	print MYFILE "key_name=$key_name\n";
	
	if (defined $arg_hash->{"flavor_name"}) {
		print MYFILE "flavor_name=".$arg_hash->{"flavor_name"}."\n";
	} elsif (defined $arg_hash->{"flavor_id"}) {
		print MYFILE "flavor_id=".$arg_hash->{"flavor_id"}."\n";
	}
	
	if (defined $tenant) {
		print MYFILE "tenant=$tenant\n";
	}
	
	print MYFILE "iplist=".join(',',@total_ip_list)."\n";
	close (MYFILE);
	
	print "##########################\n";
	print "your new instances are: ".join(',',@$ip_ref)."\n";
	print "This list has been saved in file \"$iplistfile\".\n";
	
}


sub transferSubHash {
	my $old_hash = shift (@_);
	my $new_hash = shift (@_);
	
	my @keys = @_;
	
	
	foreach my $key (@keys) {
		#print "key: $key\n";
		if (defined $old_hash->{$key}) {
			#print "copy key\n";
			$new_hash->{$key} = $old_hash->{$key};
		}
	}
	

}


sub get_instances_by_hash {
	
	my ($arg_hash, $options) = @_;
	
	print "get_instances_by_hash: ".join(',', keys(%$arg_hash))."\n";
	
	
	my @instance_names = ();
	if (defined $arg_hash->{'instance_names'}) {
		@instance_names = split(',', $arg_hash->{'instance_names'} );
	}
	
	my @instance_ips = ();
	if (defined $arg_hash->{'instance_ips'}) {
		@instance_ips = split(',', $arg_hash->{'instance_ips'} );
	}
	
	my @instance_ids = ();
	if (defined $arg_hash->{'instance_ids'}) {
		@instance_ids = split(',', $arg_hash->{'instance_ids'} );
	}
	
	my @ip_array = ();
	if (defined($arg_hash->{"iplist"})) {
		@ip_array = split(',',join(',', @{$arg_hash->{"iplist"}}));
	}
		
	my $own_hash = {
		'owner' => $arg_hash->{"owner"}||$os_username,
		'username' => $arg_hash->{"username"} || $vm_user
	};
	
	
	transferSubHash($arg_hash, $own_hash, 'group', 'groupname');
	
	
	if (@instance_names > 0) {
		$own_hash->{'instance_names'} =  \@instance_names ;
	}
	
	if (@instance_ips > 0) {
		$own_hash->{'instance_ips'} =  \@instance_ips ;
	}
	
	if (@instance_ids > 0) {
		$own_hash->{'instance_ids'} =  \@instance_ids ;
	}
	
	
	if (defined $options) {
		transferSubHash($options, $own_hash, 'return_hash');
	}
	
	
	# this also performs the group membership tests
	my $server_hash = ManageBulkInstances::get_instances( $own_hash );
	
	
	return $server_hash;
}



# delete by owner/group !
sub deletebulk {
	
	my $arg_hash = shift(@_);
	
		
	# this also performs the group membership tests
	my $server_hash = ManageBulkInstances::get_instances_by_hash( $arg_hash, {'return_hash' => 1} );
	
	
	
	# get mapping instanceId_to_volumeId
	my $volumes_detail = openstack_api('GET', 'volume', '/volumes/detail')->{'volumes'};
	#print Dumper($volumes_detail)."\n";
		
	my $instanceId_to_volumeId;
	foreach my $vol_obj (@{$volumes_detail}) {
		my $vol_id = $vol_obj->{'id'};
		#my $instid = #$volumelist->{$vol_id}{"Attached to"};
		my $instid = get_nested_hash_value($vol_obj, 'attachments', 0, 'server_id');
		
		unless (defined $instid) {
			#print Dumper($volumes_detail)."\n";
			next;
		}
		$instanceId_to_volumeId->{$instid}=$vol_id;
		#print "add $instid $vol_id\n";
	}
	
	
	# delete instances with volumes and IPs , TODO: testing
	my $delcount =0;
	foreach my $id (keys(%$server_hash)) {
		
		my $server = $server_hash->{$id};
		my $instancename = $server->{'name'};
		if (lc($server->{'status'}) eq "error") {
			print STDERR "warning: server is in error status, name=".$server->{'name'}." id=$id\n";
			next;
		}
		unless (defined $instancename) {
			print "warning: name of server with id $id not defined\n";
			next;
		}
		
		
			
		print "delete ".$instancename." (".$id.")\n";
		
		#search IP
		my $oldip = get_nested_hash_value($server, 'addresses', 'services', 0 , 'addr');
		
		
		#search volume
		my $volume_id = $instanceId_to_volumeId->{$id};
		
		
		
		# delete instance
		my $delete_result = openstack_api('DELETE', 'nova', '/servers/'.$id, { 'server_id' => $id});
		$delcount++;
		
		# delete ip
		if (defined $oldip) {
			print "delete ip $oldip of instance ".$instancename." (".$id.")\n";
			delete_IP($oldip);
		}
		
		#delete volume
		if (defined $volume_id) {
			print "delete volume $volume_id of instance ".$instancename." (".$id.")\n";
			delete_volume($volume_id);
		}
		
		
	}
	
	
	return $delcount;
	
	
}

sub reboot {
	
	my $arg_hash = shift(@_);
	
	
	my $reboot_type = $arg_hash->{"reboot"};
	
	unless (defined $reboot_type) {
		die "error: reboot type not defined. soft/hard";
	}
	
	unless ($reboot_type eq "soft" || $reboot_type eq "hard") {
			die "reboot type should be \"soft\" or \"hard\", got: $reboot_type";
	}
	
	
	# this also performs the group membership tests
	my $server_hash = ManageBulkInstances::get_instances_by_hash( $arg_hash, {'return_hash' => 1} );
	
	
	
	foreach my $id (keys(%$server_hash)) {
		
		my $server = $server_hash->{$id};
		my $instancename = $server->{'name'};
		#if (lc($server->{'status'}) eq "error") {
		#	print STDERR "warning: server is in error status, name=".$server->{'name'}." id=$id\n";
		#	next;
		#}
		unless (defined $instancename) {
			print "warning: name of server with id $id not defined\n";
			next;
		}
		
		
		
		#print "delete ".$instancename." (".$id.")\n";
		
		
		
		# reboot instance
		my $reboot_result = openstack_api('POST', 'nova', '/servers/'.$id.'/action', { 'reboot' => {"type" => $reboot_type } } );
		
				
		
	}
	
	
}

#verify that all IPs have correct groupname, use option nogroupcheck to disable check
sub deletebulk_old {
	
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
	
	
	my $volumes_detail = openstack_api('GET', 'volume', '/volumes/detail')->{'volumes'};
	#print Dumper($volumes_detail)."\n";
	
	# get mapping instanceId_to_volumeId
	my $instanceId_to_volumeId;
	foreach my $vol_obj (@{$volumes_detail}) {
		my $vol_id = $vol_obj->{'id'};
		#my $instid = #$volumelist->{$vol_id}{"Attached to"};
		my $instid = get_nested_hash_value($vol_obj, 'attachments', 0, 'server_id');
		
		unless (defined $instid) {
			#print Dumper($volumes_detail)."\n";
			next;
		}
		$instanceId_to_volumeId->{$instid}=$vol_id;
		#print "add $instid $vol_id\n";
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
	
		my $server = $id_to_server_hash->{$id};
		my $instancename = $server->{'name'};
		
		if ($instancename =~ /^$groupname/i ) {
			
			print "delete ".$instancename." (".$id.")\n";
			
			#search IP
			my $oldip = get_nested_hash_value($server, 'addresses', 'services', 0 , 'addr');

		
			#search volume
			my $volume_id = $instanceId_to_volumeId->{$id};
			
			
			
			# delete instance
			my $delete_result = openstack_api('DELETE', 'nova', '/servers/'.$id, { 'server_id' => $id});
			$delcount++;
			
			# delete ip
			if (defined $oldip) {
				print "delete ip $oldip of instance ".$instancename." (".$id.")\n";
				delete_IP($oldip);
			}
			
			#delete volume
			if (defined $volume_id) {
				print "delete volume $volume_id of instance ".$instancename." (".$id.")\n";
				delete_volume($volume_id);
			} 
			
			
				
			
		}
		
		
	}
	

	return $delcount;
}



sub list_group_print {
	my $arg_hash = shift(@_);
	
	my $iplist_ref = ManageBulkInstances::get_instances( {
		'owner' => $arg_hash->{"owner"}||$os_username,
		'group' => $arg_hash->{"listgroup"}
	} );
	
}

sub list_ips_print {
	my $arg_hash = shift(@_);
			
	my $iplist_ref = ManageBulkInstances::get_instances_by_hash( $arg_hash );
				

	
	print "iplist=".join(',', @{$iplist_ref})."\n";
	
	return;
}

#deprecated !!
sub list_group_old {
	my ($owner, $group) = @_;
	die "deprecated list_group";
	
	unless (defined $owner) {
		$owner = $os_username;
	}
	
	
	unless (defined $group) {
		print STDERR "error: (list_group) groupname not defined\n";
		exit(1);
	}
	
	
	my $servers_detail = openstack_api('GET', 'nova', '/servers/detail');
	
	if (defined $servers_detail->{'servers'}) {
		$servers_detail = $servers_detail->{'servers'};
	} else {
		die;
	}
	
	my @iplist=();
	my @instance_name_list=();
	my @instance_id_list=();
	
	foreach my $server (@{$servers_detail}) {
		
		my $instancename = $server->{'name'};
		my $instance_id = $server->{'id'};
		
		my $server_owner = $server->{'metadata'}->{'owner'} || "";
		my $server_group = $server->{'metadata'}->{'group'} || "";
		
		#if ($instancename =~ /^$groupname/ ) {
		if ( (lc($owner) eq lc($server_owner)) && lc($group) eq lc($server_group) ) {
			
						
			
			my $addr_string = get_nested_hash_value($server, 'addresses', 'service', 0, 'addr');
			unless (defined $addr_string) {
				print Dumper($server)."\n";
				print STDERR "warning: addr_string not defined !\n";
				next;
			}
			
			
			my $ip;
			($ip) = $addr_string =~ /10\.0\.(\d+\.\d+)/;
			unless (defined $ip) {
				print STDERR "warning: no internal IP found for instance  ($instancename)...\n";
				next;
			}
			push(@iplist, "10.0.".$ip);
			push(@instance_name_list, $instancename);
			push(@instance_id_list, $instance_id);
			print "10.0.".$ip." ".$instancename."\n";
			
			
		}
		
	}
	
	print "instance names:\n".join(',',@instance_name_list)."\n";
	print "instance ids:\n".join(',',@instance_id_list)."\n";
	
	
	if (@iplist ==0) {
		print STDERR "warning: no group \"$group\" for owner \"$owner\" found\n";
	}
	
	return \@iplist;
}

#get instance IP(or id!) by instance_name, group or whatever
sub get_instances {
	my $arg_hash = shift(@_); # should not be command line hash
	
	my $debug = 0;
	
	print "get_instances: ".join(',', keys(%$arg_hash))."\n";
	
	my $instance_names = $arg_hash->{'instance_names'} || []; # array reference !
	my $instance_ips = $arg_hash->{'instance_ips'} || []; # array reference !
	my $instance_ids = $arg_hash->{'instance_ids'} || []; # array reference !
	
	if ($debug) {
		print "instance_ips size: ".@{$instance_ips}."\n";
	}
	
	my $groupname = $arg_hash->{'groupname'}; # only verification when using instance names
	
	my $group = $arg_hash->{'group'};
	
	if ((@{$instance_names} > 0) || (@{$instance_ips} > 0)) {
		unless (defined $groupname) {
			print STDERR "error: --groupname should be provided with --instance_names and --instance_ips!\n";
			print join(',',keys(%$arg_hash))."\n";
			exit(1);
		}
	}
	
	my $owner = $arg_hash->{'owner'};
	unless (defined $owner) {
		$owner = $os_username;
	}
	
	# make hash for fast look-up
	my $instance_names_hash={};
	my $instance_ips_hash={};
	my $instance_ids_hash={};
	
	my $instance_names_duplicates ={};

	foreach my $instance_name (@{$instance_names}) {
		$instance_names_hash->{lc($instance_name)} = 1;
	}
	foreach my $instance_ip (@{$instance_ips}) {
		$instance_ips_hash->{$instance_ip} = 1;
		if ($debug) {
			print "add \"$instance_ip\" to hash\n";
		}
	}
	
	foreach my $instance_id (@{$instance_ids}) {
		$instance_ids_hash->{$instance_id} = 1;
	}
	
	
	
	my $servers_detail = openstack_api('GET', 'nova', '/servers/detail');
	
	if (defined $servers_detail->{'servers'}) {
		$servers_detail = $servers_detail->{'servers'};
	} else {
		die;
	}
	
	my @iplist=();
	
	my @instance_name_list=();
	my @instance_ip_list=();
	my @instance_id_list=();
	
	my $server_hash={};
	
	foreach my $server (@{$servers_detail}) {
		
		my $vm_instancename = $server->{'name'};
		my $vm_instanceid = $server->{'id'};
		
		my $server_owner = $server->{'metadata'}->{'owner'} || "";
		my $server_group = $server->{'metadata'}->{'group'} || "";
		
		
		if ((lc($owner) ne lc($server_owner)) && !defined $arg_hash->{"noownercheck"}) {
			if ($debug) {
				print "$vm_instancename : wrong owner\n";
			}
			next; # wrong owner
		}
		
		
		my $addr_string = get_nested_hash_value($server, 'addresses', 'service', 0, 'addr');
		unless (defined $addr_string) {
			print Dumper($server)."\n";
			print STDERR "warning: $vm_instancename : addr_string not defined !\n";
			next;
		}
		
		my $vm_instanceip;
		($vm_instanceip) = $addr_string =~ /10\.0\.(\d+\.\d+)/;
		
		if (defined $vm_instanceip) {
			$vm_instanceip = '10.0.'.$vm_instanceip;
		} else {
			print STDERR "warning: no internal IP found for instance  ($vm_instancename)...\n";
			$vm_instanceip=undef;
		}
		
		if ($debug) {
			print "$vm_instancename IP : $vm_instanceip\n";
		}
		
		
		#if ($instancename =~ /^$groupname/ ) {
		
		my $match = 0;
		
		
		
		
		if (defined($instance_names_hash->{lc($vm_instancename)})  ) {
			if (defined $instance_names_duplicates->{lc($vm_instancename)}) {
				print STDERR "error: instance name $vm_instancename is not uniqe!!!\n";
				exit(1);
			}
			$instance_names_duplicates->{lc($vm_instancename)}=1;
			
			$match=1; # name matches and is not duplicate
		}
		
		if (defined($vm_instanceip)) {
		
			if ( defined($instance_ips_hash->{$vm_instanceip})  ) {
				$match=1; # IP matches
			} else {
				if ($debug) {
					print "vm_instanceip \"$vm_instanceip\" not in hash\n";
				}
			}
		} else {
			if ($debug) {
				print "vm_instanceip not defined\n";
			}
		}
	
		
		if (defined($instance_ids_hash->{$vm_instanceid})  ) {
			$match=1; # id matches (no group-check, only owner check here)
		}
		
		
		if (defined $group) {
			if(lc($group) eq lc($server_group)) {
				$match=1; # group matches
			}
		}
		
		if ($match==0) {
			if ($debug) {
				print "$vm_instancename : no match\n";
			}
			next; # no match at all
		}
		
		
		
		unless (defined $vm_instanceip) {
			next;
		}
		
		push(@iplist, $vm_instanceip);
		print $vm_instanceip." ".$vm_instancename."\n";
		
		push(@instance_name_list, $vm_instancename);
		push(@instance_ip_list, $vm_instanceip);
		push(@instance_id_list, $vm_instanceid);
		$server_hash->{$vm_instanceid} = $server;
		#$server_hash->{$vm_instanceid}->{'name'} = $vm_instancename;
		$server_hash->{$vm_instanceid}->{'ip'} = $vm_instanceip;
		#$server_hash->{$vm_instanceid}->{'key_name'} = get_nested_hash_value($server, 'key_name');
		#$server_hash->{$vm_instanceid}->{'status'} = get_nested_hash_value($server, 'status');
		
	}
	
	print "\ninstance_names=".join(',',@instance_name_list)."\n\n";
	print "instance_ips=".join(',',@instance_ip_list)."\n\n";
	print "instance_ids=".join(',',@instance_id_list)."\n\n";
	
	if (@iplist ==0) {
		print STDERR "error: no instance found that matches your criteria for owner \"$owner\"\n";
		exit(1);
	}
	
	if (defined $arg_hash->{'return_hash'} ) {
		return $server_hash;
	}
		
	return \@iplist;
}
