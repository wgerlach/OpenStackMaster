#!/usr/bin/env perl


package ManageBulkInstances;

use strict;
use warnings;

eval "use Parallel::ForkManager 0.7.6; 1"
	or die "module required: sudo apt-get install build-essential ; perl -MCPAN -e \'install Parallel::ForkManager\'";

eval "use File::Flock; 1"
	or die "module required: sudo apt-get install libfile-flock-perl ; perl -MCPAN -e \'install File::Flock\'";

#use Parallel::ForkManager 0.7.6;
#new version: sudo apt-get install build-essential ; perl -MCPAN -e 'install Parallel::ForkManager'
#old version: sudo apt-get install libparallel-forkmanager-perl

use lib $ENV{"HOME"}."/projects/libraries/"; # path to SubmitVM module
use SubmitVM;
use Getopt::Long;



# purpose of this module: wrapper for nova tools



##############################
# parameters

#my $image = "b24d27d8-146c-4eea-9153-378d2642959d";
#my $image_name = "w_base_snapshot"; # or "Ubuntu Precise 12.04 (Preferred Image)"
#our $key_name = "dmnewmagellanpub";
#our $sshkey = "~/.ssh/dm_new_magellan.pem";


#my $ssh_options = "-o StrictHostKeyChecking=no -i $sshkey"; # StrictHostKeyChecking=no because I am too lazy to check for the question.
my $ssh_options = "-o StrictHostKeyChecking=no"; # StrictHostKeyChecking=no because I am too lazy to check for the question.
#my $ssh = "ssh ".$ssh_options;
my $vm_user = "ubuntu";

my @hobbitlist = ("Frodo","Samwise","Meriadoc","Peregrin","Gandalf","Aragorn","Legolas","Gimli","Denethor","Boromir","Faramir","Galadriel","Celeborn","Elrond","Bilbo","Theoden","Eomer","Eowyn","Treebeard");

my $default_namelist = \@hobbitlist;


our $nova = "nova --insecure --no-cache ";


my $timeout=30;


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
							"disksize=i"	=> "optional, in GB, default 300GB",						undef,
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
	my $nova_floating_ip_list = nova2hash($nova." floating-ip-list", 0);
	
	foreach my $ip (keys %$nova_floating_ip_list) {
		if ($nova_floating_ip_list->{$ip}{"Instance Id"} eq "None" ) {
			$newip = $ip;
			last;
		}
	}
	
	if (defined $newip) {
		return $newip;
	}
	
	# no IP found, trt to request a new one:
	my $nova_newip_hash = nova2hash($nova." floating-ip-create");
	
	if (defined $nova_newip_hash->{"ERROR"}) {
		return undef;
	}
	
	($newip) = keys(%$nova_newip_hash);
	return $newip;
}

sub systemp {
	#my $command = shift(@_);
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
	my $volumeattach = nova2hash($nova." volume-attach $instance_id $volume_id $device", 1);
	if (defined $volumeattach->{"ERROR"}) {
		return 0;
	}
	
	
	return waitNovaHashValue("volume-show $volume_id", "status", "Value", "in-use", 10, 60);
	

}

sub volumeCreateWait{
	my $instname = shift(@_);
	my $disksize = shift(@_);
	
	# create volume and wait for it to be ready
	my $disk_hash = nova2hash($nova." volume-create --display-name ".$instname." ".$disksize, 1);
	if (defined $disk_hash->{"ERROR"}) {
		return 0;
	}
	my $volume_id = getHashValue($disk_hash, "id", "Value");
	
	sleep 3;
	
	my $disk_show = nova2hash($nova." volume-show ".$volume_id, 1);
	if (defined $disk_show->{"ERROR"}) {
		return 0;
	}
	my $status = getHashValue($disk_show, "status", "Value");
	

	
	my $wait_sec = 0;
	while ($status ne "available") {
		
		if ($status eq "error") {
			# delete volume and try again
			systemp($nova." volume-delete ".$volume_id);
			return 0;
		}
		
		
		if ($wait_sec > 30) {
			print STDERR "error: disk allocation time out\n";
			return 0;
			
		}
		
		sleep 5;
		$wait_sec += 5;
		$disk_show = nova2hash($nova." volume-show ".$volume_id, 1);
		if (defined $disk_show->{"ERROR"}) {
			return 0;
		}
		$status = getHashValue($disk_show, "status", "Value");
		
	}
	return $volume_id;
}


#########################################################################



sub info {
	my $printtable = 1;
	
	my $nova_flavor_list = nova2hash($nova." flavor-list", $printtable);
	
	my $nova_image_list = nova2hash($nova." image-list", $printtable);
	#if (defined $image) {
	#	unless (defined $nova_image_list->{$image}) {
	#		print STDERR "error: image not found: \"$image\"\n";
	#		exit(1);
	#	}
	#}
	
	my $nova_keypair_list = nova2hash($nova." keypair-list", $printtable);
	#unless (defined $nova_keypair_list->{$key_name}) {
	#	print STDERR "error: keypair not found\n";
	#	exit(1);
	#}
	
	my $nova_floating_ip_list = nova2hash($nova." floating-ip-list", $printtable);
	
	my $nova_list = nova2hash($nova." list", $printtable);

	
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
	
	
	my $nova_image_list = nova2hash($nova." image-list", 0);
	
	my $image = $arg_hash->{"image"};
	my $image_name;
	unless (defined $image) {
		$image_name = $arg_hash->{"image_name"} || $image_name;
		print "searching for image with name \"$image_name\"\n";
		
		
		foreach my $id (keys %$nova_image_list) {
			if ($nova_image_list->{$id}{Name} eq $image_name) {
				if (defined $image) {
					print "error: image_name \"$image_name\" not unique. Use image ID with --image instead.\n";
					return undef;
				}
				
				$image=$id;
			}
		}

	}
	unless (defined $image) {
		print "error: image undefined \n";
		return undef;
	}
	
	
	#print $image_name."\n";
	print "using image id: ".$image."\n";
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
	
	unless (defined $flavor_name) {
		print STDERR "error: flavor_name not defined\n";
		return undef;
	}
	
	
	my $printtable = 0;
	
	my $nova_flavor_list = nova2hash($nova." flavor-list", $printtable);
	
	#my $nova_image_list = nova2hash($nova." image-list", $printtable);
	#if (defined $image) {
	#	unless (defined $nova_image_list->{$image}) {
	#		print STDERR "error: image not found: \"$image\"\n";
	#		return undef;
	#	}
	#}
	
	my $nova_keypair_list = nova2hash($nova." keypair-list", $printtable);
	unless (defined $nova_keypair_list->{$key_name}) {
		print STDERR "error: keypair \"$key_name\" not found\n";
		return undef;
	}
	
	my $nova_floating_ip_list = nova2hash($nova." floating-ip-list", $printtable);
	
	my $nova_list = nova2hash($nova." list", $printtable);
	

	
	
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
	foreach my $id (keys %$nova_flavor_list) {
		if ($nova_flavor_list->{$id}{Name} eq $flavor_name) {
			$flavor_id=$id;
		}
	}
	unless (defined $flavor_id) {
		print STDERR "error: could not find flavour name \"".$flavor_name."\"\n";
		return undef;
	}
	
	
	unless (defined $nova_flavor_list->{$flavor_id}) {
		print STDERR "error: flavorid $flavor_id not found\n";
		return undef;
	}
	
	#unless (defined($groupname)) {
	#	print STDERR "error: groupname not defined\n";
	#	return undef;
	#}
	
	if (length($groupname) <= 4) {
		print STDERR "error: name \"$groupname\" too short\n";
		return undef;
	}
	
	my %names_used;
	foreach my $id (keys %$nova_list) {
		if ($nova_list->{$id}{Name} =~ /^$groupname/ ) {
			if (defined $arg_hash->{"nogroupcheck"}) {
				my ($old_name) = $nova_list->{$id}{Name} =~ /^$groupname\_(\S+)/;
				unless (defined $old_name) {
					print STDERR "group-specific instance name not found:".$nova_list->{$id}{Name}."\n";
					exit(1);
				}
				$names_used{$old_name}=1;
			} else {
				print "error: an instance with that groupname already exists, groupname: $groupname\n";
				print "name: ".$nova_list->{$id}{Name}." ID: ".$id."\n";
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
	
	my $manager = new Parallel::ForkManager( (8, $count)[8 > $count] ); # min 5 $count
	
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
		
		my $return_value;
		my $return_data;
		
		#major components (delete if fails)
		my $instance_id;
		my $volume_id;
		my $newip;
		
		my $instance_ip;
		
		my $crashed = 0;
		my $try_counter = 0;
		MAINWHILE: while (1) {
			$try_counter++;
			
			# delete stuff from previous crash
			if ($crashed == 1) {
				print STDERR "delete previous instance since something went wrong...\n";
				if (defined $instance_id) {
					systemp($nova." delete ".$instance_id);
				}
				
				if (defined $volume_id) {
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
				return undef;
			}
			
			# create name for new instance
			my $instname=$groupname;
			
			unless (defined ($arg_hash->{"onlygroupname"}) ) {
				$instname .= "_";
				if (defined $nameslist[$i]) {
					$instname .= $nameslist[$i];
				} else {
					$instname .= $i;
				}
			}
			
			#start instance
			my $new_instance_command = $nova." boot --poll --flavor $flavor_id --image $image --key_name $key_name ".$instname;
			
			if (defined $arg_hash->{"user-data"}) {
				$new_instance_command .= " --user-data ".$arg_hash->{"user-data"};
			}
			
			my $new_instance = nova2hash($new_instance_command, 1);
			if (defined $new_instance->{"ERROR"}) {
				print STDERR "error: new_instance\n";
				print STDERR "ERRORMESSAGE: ".$new_instance->{"ERRORMESSAGE"}."\n";
				if (index($new_instance->{"ERRORMESSAGE"}, "Quota exceeded") > -1) {
					print STDERR "error: Quota exceeded, makes no sense to continue.\n";
					
					system("touch STOPBULKJOBS");
					exit(1);
				}
				$crashed = 1;
				next;
			}
			$instance_id = getHashValue($new_instance, "id", "Value");
			
			my $disk_hash;
			
			my $status;
			
			#create volume
			if ($disksize > 0) {
				
				$volume_id = volumeCreateWait($instname, $disksize);
				if ($volume_id == 0 ) {
					print STDERR "error: volid ==0\n";
					$crashed =1;
					next MAINWHILE;
				}
					
				
			}
			
			# wait for instance to be "ACTIVE"
			my $instance_show = nova2hash($nova." show ".$instance_id, 1);
			if (defined $instance_show->{"ERROR"}) {
				print STDERR "error: undefined instance_show\n";
				$crashed = 1;
				next MAINWHILE;
			}
			$status = getHashValue($instance_show, "status", "Value");
			
				
			while ($status ne "ACTIVE") {
				my $wait_sec = 0;
				if ($wait_sec > 60) {
					print STDERR "error: ACTIVE wait > 60\n";
					$crashed = 1;
					next MAINWHILE;
				}
				
				if ($status eq "ERROR") {
					print STDERR "error: status = ERROR\n";
					$crashed = 1;
					next MAINWHILE;
				}
				
				sleep 5;
				$wait_sec += 5;
				$instance_show = nova2hash($nova." show ".$instance_id, 1);
				if (defined $instance_show->{"ERROR"}) {
					print STDERR "error: undefined instanceshow\n";
					$crashed = 1;
					next MAINWHILE;
				}
				$status = getHashValue($instance_show, "status", "Value");
			}
			
				
				
			# get local IP of instance
			my $instance_ip_line = getHashValue($instance_show, "service network", "Value");
			($instance_ip) = $instance_ip_line =~ /10\.0\.(\d+\.\d+)/;
			unless (defined $instance_ip) {
				print STDERR "error: undefined instanceip \n";
				$crashed = 1;
				next MAINWHILE;
			}
			$instance_ip = "10.0.".$instance_ip;
			
			
			my $known_hosts = $ENV{"HOME"}."/.ssh/known_hosts";
			my $lock = new File::Flock $known_hosts;
			systemp('ssh-keygen', "-f $known_hosts", "-R ".$instance_ip);
			$lock->unlock();
			
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
			my $data_dir_exists = SubmitVM::remote_system($ssh, $remote, "test -d /home/ubuntu/data/");
			if ($disksize > 0) {
				
				if ($data_dir_exists == 1) {
					print STDERR "error: you requested to attach disk, but /home/ubuntu/data/ already exists!\n";
					# as long as data/ is empty simply do rmdir and continue !?
					
					exit(1);
				}
				
				#  attach volume to instance
				if (volumeAttachWait($instance_id, $volume_id, $device) == 0 ){
					print STDERR "error: vol-attach-wait\n";
					$crashed = 1;
					next MAINWHILE;
				}
				
				
			
				# create partion, make filesystem, mount etc. and check afterwards
				my $ret;
				
				my $mytime=0;
				while (1) {
					$device = undef;
					my $partitions = SubmitVM::execute_remote_command_backtick($ssh, $remote, "cat /proc/partitions");
					
					my @partitiion_array = split('\n', $partitions);
					
					foreach my $line (@partitiion_array) {
						my ($major,$minor,$blocks, $devicename) = $line =~ /(\d+)\s+(\d+)\s+(\d+)\s+(\S+)/;
						
						if (defined $major) {
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
				if ($crashed == 1) {
					next;
				}
				
				SubmitVM::remote_system($ssh, $remote, "echo -e \\\"n\\np\\n1\\n\\n\\nt\\n83\\nw\\\" | sudo fdisk $device") or do {print STDERR "error: fdisk\n"; $crashed = 1; next;};
				SubmitVM::remote_system($ssh, $remote, "sudo mkfs.ext3 $device") or do {print STDERR "error: mkfs\n";$crashed = 1; next;};
				SubmitVM::remote_system($ssh, $remote, "sudo mkdir /mnt2/") or do {print STDERR "error: mkdir mnt2\n";$crashed = 1; next;};
				SubmitVM::remote_system($ssh, $remote, "sudo mount $device /mnt2/") or do {print STDERR "error: mount\n";$crashed = 1; next;};
				SubmitVM::remote_system($ssh, $remote, "sudo chmod 777 /mnt2") or do {print STDERR "error: chmod \n";$crashed = 1; next;};
				SubmitVM::remote_system($ssh, $remote, "ln -s /mnt2 /home/ubuntu/data") or do {print STDERR "error: ln\n";$crashed = 1; next;};
				
				sleep 2;
				my ($mountlines) = SubmitVM::execute_remote_command_backtick($ssh, $remote, "df -h | grep $device | wc -l") =~ /(\d+)/;
				unless (defined $mountlines) {
					print STDERR "error: undefined mountlines\n";
					$crashed = 1;
					next MAINWHILE;
				}
				if ($mountlines != 1) {
					print STDERR "error: disk not mounted: $ssh $remote\n";
					$crashed = 1;
					next MAINWHILE;
				}
			} else {
				# create data directory
				
				if ($data_dir_exists != 1) {
					SubmitVM::remote_system($ssh, $remote, "ln -s /mnt/ /home/ubuntu/data") or do {print STDERR "error: ln\n"; $crashed = 1; next;};
				}
				SubmitVM::remote_system($ssh, $remote, "sudo chmod 777 /home/ubuntu/data") or do {print STDERR "error: chmod\n"; $crashed = 1; next;};
				
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
					systemp($nova."  add-floating-ip ".$groupname.$i." $newip");
				} else {
					systemp($nova."  add-floating-ip ".$groupname." $newip");
				}
			}
			
			
			$return_value = 0;
			$return_data = $instance_ip;
			last;
		} # end while
		
		$manager->finish($return_value, \$return_data);
		########## CHILD END ############
	}
	

	
	
	
	my $active = 0;
	my $build = 0;
	while ($active < $count) {
		$nova_list = nova2hash($nova." list", 0);
		$active = 0;
		$build = 0;
		foreach my $id (keys %$nova_list) {
			if ($nova_list->{$id}{Name} =~ /^$groupname/ ) {
				#print "got: ".$nova_list->{$id}{Status}."\n";
				if ($nova_list->{$id}{Status} eq "ACTIVE") {
					$active++;
				} elsif ($nova_list->{$id}{Status} eq "BUILD") {
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
	
	# get list of IPs
	
	
	
	
#	my @list_of_ips=();
#	
#	foreach my $id (keys %$nova_list) {
#		if ($nova_list->{$id}{Name} =~ /^$groupname/ ) {
#			#print "got: ".$nova_list->{$id}{Status}."\n";
#			
#			my $networks = $nova_list->{$id}{Networks};
#			
#			my ($ip) = $networks =~ /(10\.0\.\d+\.\d+)/;
#			
#			unless (defined $ip) {
#				print STDERR "error: local IP for $id not found\n";
#				print STDERR "nova_list->{id}{Name}: ".$nova_list->{$id}{Name}."\n";
#			}
#			push(@list_of_ips, $ip);
#		}
#	}
	
	if (defined $arg_hash->{"saveIpToFile"}) {
		#saveIpToFile($groupname, $sshkey, \@list_of_ips);
		saveIpToFile($groupname, $sshkey, \@children_iplist);
	}
	#return \@list_of_ips;
	return \@children_iplist;
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

#verify that all IPs have correct groupname, use groupname=force to diable check
sub deletebulk {
	
	my $arg_hash = shift(@_);
	
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

	
	my $volumelist = nova2hash($nova." volume-list", 1);
	my $nova_list = nova2hash($nova." list", 1);
	my $nova_floating_ip_list = nova2hash($nova." floating-ip-list", 1);
	
	my $instanceId_to_volumeId;
	foreach my $vol_id (keys %$volumelist) {
		my $instid = $volumelist->{$vol_id}{"Attached to"};
		
		unless (defined $instid) {
			#print "found undefined\n";
			next;
		}
		$instanceId_to_volumeId->{$instid}=$vol_id;
		
	}
	
	my %ip_to_name_hash;
	foreach my $id (keys %$nova_list) {
		
		if ($nova_list->{$id}{Status} eq "ERROR") {
			next;
		}
		
		my $instancename = $nova_list->{$id}{Name};
		
		my ($ip) = $nova_list->{$id}{Networks} =~ /10\.0\.(\d+\.\d+)/;
		#unless (defined $ip) {
		#	print STDERR "error: ip not defined\n";
		#	print STDERR $nova_list->{$id}{Networks}."\n";
		#	print STDERR "instancename: ".$instancename."\n";
		#	exit(1);
		#}
		if (defined $ip) {
			$ip_to_name_hash{"10.0.".$ip}{"name"} = $instancename;
			$ip_to_name_hash{"10.0.".$ip}{"id"} = $id;
		} 
	}
	
	my $delcount =0;
	
	my @ip_array = split(',',join(',', @{$arg_hash->{"iplist"}}));
	
		
	my @id_list=();
	foreach my $ip (@ip_array) {
		
		unless (defined $ip_to_name_hash{"10.0.".$ip}) {
			print STDERR "error: ip $ip is unknown\n";
			exit(1);
		}
		
		if ($groupname ne "force") {
			if (substr($ip_to_name_hash{$ip}{"name"}, 0, length($groupname)) ne $groupname) {
				print STDERR "error: groupname is not a prefix of instance name:\n";
				print STDERR "groupname: " .$groupname."\n";
				print STDERR "instance name: " .$ip_to_name_hash{$ip}{"name"}."\n";
				print STDERR "instance ip: " .$ip."\n";
				exit(1);
			}
		}
		push(@id_list, $ip_to_name_hash{$ip}{"id"});
	}
	
	if (@id_list != @ip_array) {
		print STDERR "error: \@id_list != \@ip_array: ".@id_list." ".@ip_array."\n";
		exit(1);
	}
	
	foreach my $id (@id_list) {
	#foreach my $id (keys %$nova_list) {
		my $instancename = $nova_list->{$id}{Name};
		
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


