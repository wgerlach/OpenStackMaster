package SubmitVM;


eval "use Parallel::ForkManager 0.7.6; 1"
	or die "module required: sudo apt-get install build-essential ; perl -MCPAN -e \'install Parallel::ForkManager\'\n";
#use Parallel::ForkManager 0.7.6;
#new version: sudo apt-get install build-essential ; perl -MCPAN -e 'install Parallel::ForkManager'
#old version: sudo apt-get install libparallel-forkmanager-perl

use File::Temp qw/ tempfile tempdir /;
use Storable 2.05 qw(nstore);
use File::Basename;
#eval "use Try::Tiny qw( try catch ); 1"
#	or die "module required: sudo apt-get install libtry-tiny-perl \n or perl -MCPAN -e \'install Try::Tiny\'\n";

#use Try::Tiny; # for porper try catch;  sudo apt-get install libtry-tiny-perl

1;


# purpose of thei module: basic ssh communication with VMs and multithreading of tasks

#1. single job subs
#2. main sub


##########################
# 1. single job subs


sub ubuntu_aptget_update {
	my $ssh = shift(@_);
	my $scp = shift(@_);
	my $remote = shift(@_);
	
	my $rpf = SubmitVM::remote_perl_function(	$ssh , $scp, $remote,
	sub {
		if (-M "/var/lib/apt/periodic/update-success-stamp" > 2) {
			system("sudo apt-get -y -q update");
		} else {
			print "ubuntu repo should be up-to-date\n";
		}
	}
	);
	print $rpf."\n";
	return;
}


sub setDate {
	my $ssh = shift(@_);
	my $remote = shift(@_);
	
	my $date = `date \"+\%Y\%m\%d \%T\"`;
	chop($date);
	remote_system($ssh, $remote, "sudo date --set=\\\"".$date."\\\"") || print STDERR "error setting date/time\n";
	
	return;
}

sub remote_perl_function {
	my $ssh = shift(@_);
	my $scp = shift(@_);
	my $remote = shift(@_);
	my $func_ref = shift(@_);
	my $data_ref = shift(@_);
	
	
	my ($fh, $tempfilename) = tempfile( 'submitVMXXXXXXXXX' , UNLINK => 1);
	
	#open (TMP, "> $tempfilename")
	#or die "Error opening $tempfilename: $!";
	
	
	{
		
		no warnings;
		$Storable::Deparse = 1;
		$Storable::Eval = 1;
	}
	
	nstore ({"CODE" => $func_ref, "DATA" => $data_ref}, $tempfilename);
	
	my $tempbase = 'tempfile.dat';
	
	unless (-e $tempfilename) {
		sleep 3;
		unless (-e $tempfilename) { # try it once again
			print STDERR "error: $tempfilename not found on local system\n";
			exit(1);
		}
	}
	
	myscp($scp, $tempfilename, $remote.':'.$tempbase);
	
	#my $ret = execute_remote_command_backtick($ssh, $remote, "perl -e \'print \\\"hello world \\\"\'");
	my $ret = execute_remote_command_backtick($ssh, $remote,
		"perl -e \'".
			"use Storable 2.05 qw(retrieve);".
			" \\\$Storable::Eval = 1;".
			" my \\\$retrieved = retrieve\(\\\"".$tempbase."\\\"\);".
			" \\\$retrieved->\{\\\"CODE\\\"\}\(\\\$retrieved->\{\\\"DATA\\\"\}\);".
		" \' ;".
		" rm -f $tempbase");
	
	system("rm -f ".$tempfilename);
	return $ret;
}

sub execute_remote_command_backtick {
	my $ssh = shift(@_);
	my $remote = shift(@_);
	my $remote_command = shift(@_);
	
	my $command = "$ssh $remote \"$remote_command\"";
	print $command."\n";
	my $return_value = `$command`;
	
	return $return_value;
}

sub remote_system { # was execute_remote_command_simple
	my $ssh = shift(@_);
	my $remote = shift(@_);
	my $remote_command = shift(@_);
	
	my $command = "$ssh $remote \"$remote_command\"";
	
	print $command."\n";
	my $ret = system($command); #returns remote exit code, only 255 if something is wrong with ssh
	print "ret: \"$ret\"\n";
	if ($ret == 0 ) {
		return 1;  #good
	}
	return 0;#error
}


sub getCPUCount {
	my $ssh = shift(@_);
	my $remote = shift(@_);
	my $cpus = execute_remote_command_backtick($ssh, $remote, "cat /proc/cpuinfo | grep processor | wc -l");
	
	#print "cpus before: \"$cpus\"\n";
	($cpus) = $cpus =~ /(\d+)/;
	
	unless (defined $cpus) {
		print STDERR "number of cpus not valid: undefined\n";
		die;
	}
	
	if (($cpus eq "") || ( $cpus eq "0" )) {
		print STDERR "number of cpus not valid: \"$cpus\"\n";
		die;
	}
	
	#print "found $cpus CPUs\n";
	return $cpus;
}

sub program_needed {
	my $ssh = shift(@_);
	my $remote = shift(@_);
	my $bin_name = shift(@_);
	my $package_name = shift(@_);
	
	my $blastall = execute_remote_command_backtick($ssh, $remote, "which $bin_name");
	
	if ($blastall eq "") {
		print "$bin_name not found, try to install...\n";
		remote_system($ssh, $remote, "sudo apt-get --force-yes -y -q install $package_name") || return 0;
		
		sleep 3;
	} else {
		return 1;
	}
	
	$blastall = execute_remote_command_backtick($ssh, $remote, "which $bin_name");
	if ($blastall eq "") {
		print STDERR "could not find/install $bin_name on VM...";
		return 0;
	}
	return 1;
}

sub lib_needed {
	my $ssh = shift(@_);
	my $remote = shift(@_);
	my $package_name = shift(@_);
	
	
	remote_system($ssh, $remote, "sudo apt-get -y -q install $package_name") || return 0;
	
	return 1;
}


sub myscp {
	my $scp = shift(@_);
	my $source = shift(@_);
	my $target = shift(@_);
	
	my $command = "$scp ".$source." ".$target;
	print $command."\n";
	my $ret = system($command);
	
	if ($ret == 0 ) {
		return 1;
	}
	return 0; #error
}



sub execute_remote_command_in_screen_and_wait {
	my $ssh = shift(@_);
	my $remote = shift(@_);
	my $screen_name = shift(@_);
	my $poll_time = shift(@_);
	my $remote_command = shift(@_);
	
	my $command = "$ssh $remote screen -d -m -S $screen_name \"bash -c \\\"$remote_command ; echo \$?\\\"\"";
	
	print $command."\n";
	system($command) == 0
	or die "system $command failed: $?";
	sleep 2;
	while (1) {
		my $screen = execute_remote_command_backtick($ssh, $remote, "screen -list | grep $screen_name");
		print "$ip: ".$screen."\n";
		if ($screen eq "") {
			last;
		}
		sleep $poll_time;
	}
	#print "$screen_name seems to have finished\n";
	sleep 5;
	return;
}



sub connection_test {
	my $ssh = shift(@_);
	my $remote = shift(@_);
	
	my $command3 = "$ssh -q -o \"BatchMode=yes\" $remote \"echo 2>&1\" && echo \"SUCCESS\" || echo \"no ssh connection\"";
	my $connectiontest = `$command3`;
	print "command: $command3\n";
	print "connectiontest: $connectiontest\n";
	if (index($connectiontest, "SUCCESS") == -1) {
		#print "error: connection test for $remote failed\n";
		#print "command: $command3\n";
		#print "connectiontest: $connectiontest\n";
		return 0;
	}
	return 1;
}


sub connection_wait {
	my $ssh = shift(@_);
	my $remote = shift(@_);
	my $timeout = shift(@_);
	
	
	my $con_test = connection_test($ssh, $remote);
	my $time = 0;
	while ($con_test == 0) {
		
		print "$remote waiting for ssh connection ... $time \n";
		
		if ($time > $timeout) {
			print STDERR "error: connection test for $remote failed finally...\n";
			print STDERR "command was: $command3\n";
			print STDERR "returned: $connectiontest\n";
			exit(1);
		}
		sleep 10;
		$time += 10;
		
		$con_test = connection_test($ssh, $remote);
		
	}
	print "$remote ssh SUCCESS ...\n";
	
	return;
}

sub check_screen {
	my $ssh = shift(@_);
	my $remote = shift(@_);
	
	my $screenlist = execute_remote_command_backtick($ssh, $remote, "screen -list");
	
	unless ( ($screenlist =~ tr/\n//) == 2 ) {
		print STDERR "screen running on remote VM !?\n";
		print STDERR "screenlist: \"$screenlist\"\n";
		
		print STDERR "will try to kill...\n";
		
		system("$ssh $remote \"sudo killall screen\"");
		sleep 3;
		
		system("$ssh $remote \"sudo screen -wipe\"");
		sleep 3;
		
		my $screenlist2 = execute_remote_command_backtick($ssh, $remote, "screen -list");
		
		unless ( ($screenlist2 =~ tr/\n//) == 2 ) {
			print STDERR "screen still running on remote VM... stop\n";
			exit(1);
		}
		
	}
	return;
}

	
#################################
# 2. main sub


sub parallell_job {
	print STDERR "warning: deprecated function parallell_job\n";
	my $command  = shift(@_);
	my $vmips_ref = shift(@_);
	my $vmargs_ref = shift(@_);
	
	my $function_ref = shift(@_);
	
	
	my $args_hash = {	"vmips_ref" => $vmips_ref,
						"vmargs_ref" => $vmargs_ref
	};
	
	if (defined($command)) {
		$args_hash->{"command"}= $command;
	}
	if (defined($function_ref)) {
		$args_hash->{"function_ref"}= $function_ref;
	}

	my $stuff = parallell_job_new($args_hash);
	
	if (defined($stuff) ) {
		return 1;
		
	}
	
	return 0;
}

# @vmargs should be at least of size of @vmips=number of VMs, or bigger
sub parallell_job_new {
	my $args_hash = shift(@_);
	
	my $command;
	my $vmips_ref;
	my $vmargs_ref;
	
	my $function_ref;

	
	if (defined($args_hash->{"command"})) {
		$command = $args_hash->{"command"};
	}
	if (defined($args_hash->{"function_ref"})) {
		$function_ref = $args_hash->{"function_ref"};
	}
	
	my $ip_to_keyfile;
	if (defined($args_hash->{"ip_to_keyfile"})) {
		$ip_to_keyfile = $args_hash->{"ip_to_keyfile"};
	}
	
	
	
	unless (defined $args_hash->{"vmips_ref"}) {
		print STDERR "error: no IPs found\n";
		exit(1);
	}
	
	$vmips_ref = $args_hash->{"vmips_ref"} || die;
	$vmargs_ref = $args_hash->{"vmargs_ref"} || $vmips_ref;
	
	
	if (defined($command) && defined($function_ref) ) {
		print STDERR "error: (parallell_job) command and function_ref defined\n";
		exit(1);
	}
	unless (defined($command) || defined($function_ref) ) {
		print STDERR "error: (parallell_job) both command and function_ref not defined\n";
		exit(1);
	}
	
	
	#print "got: ".join(",", @$vmargs_ref)."\n";
	
	
	my @available_ips = split(/,/,join(',',@$vmips_ref));
	
	
	my @job_ip_assignment=();
	
	my @children_pid=();
	
	my $vm_count = @available_ips;
	my $job_count = @$vmargs_ref;
	
	
	if ($vm_count == 0) {
		print STDERR "error: vm_count == 0, no IPs\n";
		exit(1);
	}
	
	
	my @job_requests_ip = ();
	
	
	my $job_finished = 0;
	
	
	my $manager = new Parallel::ForkManager( $job_count);
	
	$SIG{CHLD} = sub{  Parallel::ForkManager::wait_children($manager) };
	
	$manager->run_on_start(
	sub {
		my ($pid,$ident) = @_;
		print "Starting processes $ident under process id $pid\n";
		push (@job_requests_ip, $ident);
		push (@children_pid, $pid);
		
	}, 1
	);
	
	my $return_values={};
	
	#my $currently_running_ref = \$currently_running;
	my $somethingwrong = 0;
	$manager->run_on_finish(
	sub {
		
		my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $data_structure_reference) = @_;
		
		if ($exit_code != 0 ) {
			print "\n-----------\njob finished\n";
			print "pid: $pid\n";
			print "exit_code: $exit_code\n";
			
			unless (defined $ident) {
				$ident = "undefined";
			}
			print "ident: $ident\n";
			
			if ( $core_dump ) {
				print "core_dump: $core_dump\n";
				print "exit_signal: $exit_signal\n";
				
			}
			
			
			print "-----------\n\n";
		}
		
		if (defined $data_structure_reference) {
			#print "child $ident returned: \"".${$data_structure_reference}."\"\n";
			$return_values->{$ident}{"text"} = ${$data_structure_reference};
		} else {
			#print "child $ident returned nothing\n";
			$return_values->{$ident}{"text"} = "returned nothing";
		}
		
		#print "list_a: ".join(",", @available_ips)."\n";
		#print "job_ip_assignment: ".join(",", @job_ip_assignment)."\n";
		#print "try to push ip: ".makedefined($job_ip_assignment[$ident])."\n";
		
		if  (defined $job_ip_assignment[$ident] ) {
			$return_values->{$ident}{"ip"} = $job_ip_assignment[$ident];
			push(@available_ips, $job_ip_assignment[$ident]);
		} else {
			
			print STDERR "error: job $ident could not give IP back\n";
		}
		#print "list_b: ".join(",", @available_ips)."\n";
		$job_finished++;
		
		
		if ($exit_code != 0) {
			#system("kill ".join(' ', @children_pid));
			
			system("kill ".join(' ', @children_pid));
			print STDERR "Child exited with exit_code != 0. Stop whole script. Be aware that other VM probably are still running.\n";
			print STDERR "children: ".join(' ', @children_pid)."\n";
			print STDERR "Use this to stop processes: for i in ".join(' ', @$vmips_ref )."\; do ssh -o StrictHostKeyChecking=no -i sshkey ubuntu\@\$i \"sudo killall screen\"\; done\n";
			#system("ps -o pid -ax --ppid ".$$);
			$somethingwrong = 1;
			return undef;
		}
		
		
		#$currently_running--;
	}
	);
	
	system("rm -f job_*.communication");
	
	#print "mainPID: ".$$."\n";
	my $tempdir_obj = File::Temp->newdir(TEMPLATE => 'submitvmXXXXXXXXX',);
	my $tempdir = $tempdir_obj->dirname."/";
	
	unless (-d $tempdir) {
		print STDERR "temp dir $tempdir not created\n";
		exit(1);
	}
	
	for (my $i=0 ; $i < $job_count ; ++$i) {
		$job_ip_assignment[$i] = 0;
	}
	
	#print "START job_ip_assignment: ".join(",", @job_ip_assignment)."\n";
	
	my $ip;
	
	for (my $i=0 ; $i < $job_count ; ++$i) {
		my $parameter = $vmargs_ref->[$i];
		unless (defined $parameter) {
			return undef;
		}
		#print "command=".$command."\n";
		#print "start job num: ".$i."\n";
		
		########## CHILD START ############
		$manager->start($i) and next;
		
		my $talk = 0;
		
		# wait for communication file that assigns IP
		my $ip;
		my $com_file = $tempdir."job_$i.communication";
		while ( 1 ) {
			
			if (-e $com_file) {
				my $comfile = `cat $com_file`;
				
				my ($childip) = $comfile =~ /(\d+\.\d+\.\d+\.\d+)/;
				unless (defined $childip) {
					print "child $i says: could not read IP from file\n";
					print "child $i says: this is what I read from from comfile: $comfile\n";
				} else {
					$ip = $childip;
					system("rm -f $com_file");
					last;
				}
				
			}
			if ($talk==1) {
				print "child num $i waits for an IP\n";
			}
			sleep 10;
		}
		
		
		
		print "child $i says: got ip $ip\n";
		
		if ( defined($command) ) {
		
			my $real_command = $command;
			#"perl $vmblastbin $ip $vm_user $sshkey $files";
			
			$real_command =~ s/\[IP\]/$ip/;
			
			$real_command =~ s/\[PARAMETER\]/$parameter/;
			
			
			print "child $i says: call: ".$real_command."\n";
			
			
			
			#my $return_value = system( $real_command );
			exec($real_command)  or print STDERR "couldn't exec foo: $!";
			
			
		} else {
			
			my $ssh_options = "-o StrictHostKeyChecking=no";
			if (defined $ip_to_keyfile) {
				if (defined $ip_to_keyfile->{$ip}) {
					$ssh_options .= " -i ".$ip_to_keyfile->{$ip};
				} else {
					print "error: ip $ip missing in ip_to_keyfile\n";
					exit(1);
				}
			} else {
				print "error: ip_to_keyfile not defined\n";
				
				exit(1);
			}
			
			
			my $func_exit_code=0;# good
			my $func_ret;
			eval {
				$func_ret = &$function_ref($ip, $parameter, $ssh_options);
			};
			if($@) {
                warn "caught error: ".$@;
				$func_ret = $@;
				$func_exit_code = 1;
			}
		
			
			if (defined $func_ret) {
				$manager->finish($func_exit_code, \$func_ret);
			} else {
				$manager->finish($func_exit_code);
			}
			
						
		}
		#$return_value = $return_value >> 8;  # bitshift to correct return value
		#my $return_value = 1;
		#sleep 7;
		
		#my $return_data = `date`;
		#$return_data =~ s/\n//;
		#my $return_data = "child $i says: finished!";
		
		
		#$manager->finish($return_value, \$return_data);
		
		########## CHILD END ############
		
	};
	
	while ($job_finished < $job_count) {
		
		print "scheduler: $job_finished of $job_count ready.\n";
		if (@job_requests_ip == 0 ) {
			print "scheduler: at the moment no job asks for an IP...\n";
			sleep 30;
		} else {
			
			if (@job_requests_ip <= 20 ) {
				print "scheduler: list of jobs that request an IP: ".join(',', @job_requests_ip)."\n";
			} else {
				print "scheduler: ".@job_requests_ip." jobs request an IP.\n";
			}
			if (@available_ips > 0) {
				#my $ip = pop(@available_ips);
				my $ip = shift(@available_ips); # rotation, this guarantees that every IP is used
				my $job = pop(@job_requests_ip);
				print "scheduler: assign ip $ip to job $job\n";
				$job_ip_assignment[$job] = $ip;
				system("echo $ip > ".$tempdir."job_$job.communication");
				
				
			}
			sleep 2;
		}
		
		
		
		
		
	}
	print "all jobs should have finished by now.\n";
	
	
	print "to be sure, wait for the last children to finish...\n";
	$manager->wait_all_children;
	
	#system("rm -f job_*.communication");
	
	if ($somethingwrong ==1) {
		print "SubmitVM: something wrong.\n";
		return undef;
	}
	
	#foreach my $ident (keys %$return_values) {
	#	print "$ident (".$return_values->{$ident}{"ip"}.") returns:\n";
	#	print $return_values->{$ident}{"text"}."\n";
	#}
	
	
	print "SubmitVM: done.\n";
	
	
	
	
	return $return_values; #good
}


