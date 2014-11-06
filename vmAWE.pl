#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";

#use lib $ENV{"HOME"}."/projects/libraries/"; # path to SubmitVM module
use SubmitVM;
use ManageBulkInstances;


use File::Temp qw/ tempfile tempdir /;
use File::Basename;

my $awecfg_url = "http://www.mcs.anl.gov/~wtang/files/awe.cfg";


my $options_awe_actions = [	"AWE actions (independent, can be combinded)",
							"addscripts=s"	=> "list of scripts, comma separated",					undef,
							#"awecfgfile=s"	=> "awe config file to use as template, default: $awecfg_url ",				undef,
							"deploy=s@"     => "deploy any software on vm",                          undef,
							"root_deploy=s@"     => "deploy any software on vm as root",             undef,
							"deploy_target=s"   => "deploy target",                          undef,
							"deploy_data_target=s"   => "specifiy data target, e.g. /home/ubuntu/data/",                          undef,
							"awecfg=s@"		=> "configure AWE client: [section]key=value?key=value...",                  undef,
							"k_awecfg=s@"	=> "(KBase) configure AWE client: [section]key=value?key=value...",                  undef,
							"update"		=> "installs or updates AWE client",					undef,
							"k_update"		=> "(KBase) updates AWE client",					undef,
							"id_rsa=s"		=> "copy local file to /root/.ssh/id_rsa",					undef,
							"startawe"		=> "",													undef,
							"stopawe"		=> "",													undef,
							"restartawe"	=> "",													undef,
							"command=s"		=> "pass a command to all VMs, e.g. \"df -h\"",			undef,
							"copy=s"		=> "scp file over to host, local:remote",			undef,
							"snapshot=s"	=> "awesome feature that is not implemented yet",		undef,
							"example"		=> "example for executing perl subroutine remotely"	,	undef
							];

#my $options_awe_options = [	"AWE options",
#							"serverurl=s"	=> "optional, use with action --awecfg",				undef,
#							"awegroup=s"	=> "optional, use with actions --awecfg",				undef
#							];



my @options_array = @ManageBulkInstances::options_all;
push(@options_array , $options_awe_actions); #$options_awe_options



unless ( @ARGV ) {
	print "vmAWE.pl \n\n";
	
	ManageBulkInstances::print_usage(\@options_array);

	print " \n";
	print " example: ./vmAWE.pl --create 2 --groupname MY_UNIQUE_NAME --awecfg=\"[Client]serverurl=<url>?group=MYGROUP?supported_apps=blast\" --deploy=otherpackage --update --startawe 2>\&1 \| tee vmAWE.log\n";
	exit 1;
}




my $cities = "Hangzhou,Chengdu,Qingdao,Changchun,Chongqing,Jiangyin,Nanjing,Huizhou,Hong,Suzhou,Harbin,Yantai,Ningbo,Yichun,Dalian,Siping,Weihai,Zhaoqing,Tonghua,Shaoxing,Zhengzhou,Lijiang,Erdos,Xuzhou,Xiamen,Shenyang,Guangzhou,Duyun,Kunming,Changsha,Dongying,Kunshan,Tangshan,Yulin,Foshan,Linyi,Jinzhou,Yangzhou,Chengde,Binzhou,Xining,Quanzhou,Baotou,Taipei,Zhongshan,Taizhou,Fuzhou,Yunfu,Macao,Dezhou,Kaili,Xiangtan,Xuchang,Qinzhou,Huaibei,Zhangjiakou,Baoji,Liaocheng,Handan,Mudanjiang,Kaifeng,Baoding,Tongliao,Ningde,Fushun,Liupanshui,Yingkou,Chifeng,Xingtai,Benxi,Luoyang,Longyan,Huainan,Langfang,Hefei,Bijie,Xinxiang,Guiyang,Songyuan,Xinyang,Anshan,Jilin,Shaoguan,Liaoyuan,Shangqiu,Zhenjiang,Zhaotong,Yinchuan,Jixi,Tieling,Bozhou,Shenzhen,Chaohu,Beijing,Jincheng,Shanghai,Sanming,Baicheng,Wuhu";

my %arg_hash = ();


#push (@options_array, $options_hidden_options);

#get values from command line
ManageBulkInstances::getOptionsHash(\@options_array, \%arg_hash);

# get values from config file
ManageBulkInstances::read_config_file(\%arg_hash, "default");

# get values from IP file
if (defined $arg_hash{"ipfile"}) {
	ManageBulkInstances::read_config_file(\%arg_hash, $arg_hash{"ipfile"});
}


my $cfg=undef;

###########################################################


sub thread_function {
	my ($ip, $parameter, $ssh_options) = @_;
	
	print "********** thread function starts **********\n";
	print "ip: $ip\n";
	print "parameter: $parameter\n";
	
	
	#my $ip = $arg_hash{"iplist"};
	
	unless (defined $arg_hash{"username"}) {
		$arg_hash{"username"} = "ubuntu";
	}
	
	my $remote = $arg_hash{"username"}."\@$ip";
	my $remoteDataDir = "/home/".$arg_hash{"username"}."/data/";
	
	
	my $ssh = "ssh ".$ssh_options;
	my $scp = "scp -c blowfish ".$ssh_options;
	
	
	
	# ---------- some basic tests on VM -----------
	
	# --- conections test
	my $ssh_test_result = SubmitVM::connection_test($ssh, $remote);
	
	#if (defined $arg_hash{"sshtest"}) {
		if ($ssh_test_result == 0) {
			print STDERR "no ssh connection!!!\n";
			return 0;
		}
	#}
	
	# --- check if a screen session is running
	SubmitVM::check_screen($ssh, $remote);
	
	# --- apt-get update
	#SubmitVM::ubuntu_aptget_update($ssh , $scp, $remote);
	
	# --- get number of CPUs
	#my $cpus = SubmitVM::getCPUCount($ssh, $remote);
	
	# --- check if stuff is installed, install if needed with apt-get
	#SubmitVM::program_needed($ssh, $remote, "git", "git") or die;
	#SubmitVM::program_needed($ssh, $remote, "make", "make") or die;
	#SubmitVM::program_needed($ssh, $remote, "gcc", "build-essential") or die;
	
	
	
	# ----------------- START --------------------
	
	if (defined $arg_hash{"example"}) {
		
		my $rpf = SubmitVM::remote_perl_function(	$ssh , $scp, $remote,
			# this subroutine will be executed on remote VM
			sub {
				my $data_hash_ref = shift(@_);
				my $data = $data_hash_ref->{"data"};
				
				print "hello world\n";
				print "this script function runs on a VM!\n";
				print "data: $data\n";
				
				return; # return value is not used
			}
		,
		{"data" => "this_is_data"} # hash with some data for the subroutine
		
		);
		print $rpf."\n"; # this contains all STDOUT output (if needed we could return real data structures)
		
	}
	
	sub deploy_package_lists_to_array {
		my $packages_cmdline = shift(@_);
		
		my @packages =();
		foreach my $p_string (@{$packages_cmdline}) {
			my @p_with_args = $p_string =~ /([\w\-\.\/]+(?:\(.+\))?)/g; # ?: indicates that I do not want to caputure the inner round brackets
			print "p_with_args: ".join(',', @p_with_args)."\n";
			print "remaining string: $p_string\n";
			#exit(0);
			push(@packages, @p_with_args);
		}
		#print "p_with_args: ".join(',', @p_with_args)."\n";
		#print "remaining string: $p_string\n";
		
		return @packages;
	}
	
	if (defined($arg_hash{"deploy"}) || defined($arg_hash{"root_deploy"})) {
		
		my $deploy_target = $arg_hash{"deploy_target"};
		#my $deploy_asroot = $arg_hash{"deploy_asroot"} || 0;
		
		if (defined($arg_hash{"root_deploy"})) {
			my @packages =deploy_package_lists_to_array($arg_hash{"root_deploy"});
	
			print "list of packages: ".join(' ' , @packages)."\n";
			SubmitVM::deploy_software($ssh, $remote, "root" => 1, "target" => $deploy_target, "packages" => \@packages);
		}
		
		if (defined($arg_hash{"deploy"})) {
			my @packages =deploy_package_lists_to_array($arg_hash{"deploy"});
			
			print "list of packages: ".join(' , ' , @packages)."\n";
			
			SubmitVM::deploy_software($ssh, $remote, "root" => 0, "source_file" => "/home/ubuntu/.bashrc", "target" => $deploy_target, 'data_target' => $arg_hash{"deploy_data_target"}, "packages" => \@packages);
		}
		
		#for Wei "aweclient/cfg([Client]server=hello)" --ignore=aweclient/cfg/default
		
		# ManageBulkInstances::deploy_software($ssh, $remote, "root" => 1, "upstart-aweclient");
		
	}
	
	if (defined($arg_hash{"awecfg"}) || defined($arg_hash{"k_awecfg"})) {
		
		my $remote_hostname = SubmitVM::execute_remote_command_backtick($ssh, $remote, "hostname");
		chomp($remote_hostname);
		
		my $awe_deploy_target;
		my $awe_root;
		my $awecfgs = "";
		my $packages = [];
		
		if (defined $arg_hash{"awecfg"}) {
			$awecfgs = join(' ',@{$arg_hash{"awecfg"}});
			$awe_deploy_target = "/home/ubuntu/etc/";
			$awe_root = 0;
			$packages = ["aweclient/cfg/default(awe.cfg)", "aweclient/cfg-awe.cfg([Client]name=$remote_hostname $awecfgs)"];
		} elsif (defined $arg_hash{"k_awecfg"}) {
			$awecfgs = join(' ',@{$arg_hash{"k_awecfg"}});
			$awe_deploy_target = "/kb/deployment/services/awe_service/conf/";
			$awe_root = 1;
			$packages = ["aweclient/cfg/default(awec.cfg)", "aweclient/cfg-awec.cfg([Client]name=$remote_hostname $awecfgs)"];
		} else {
			die "cannot combine k_awecfg and awecfg !";
		}
		
				
		print "list of packages: ".join(' ' , @{$packages})."\n";
		
		SubmitVM::deploy_software($ssh, $remote, "forcetarget" => 1, "root" => $awe_root, "target" => $awe_deploy_target, "packages" => $packages);
	}
	
	

	
	if (defined $arg_hash{"addscripts"}) {
		my @scripts = split(',', $arg_hash{"addscripts"});
		
		SubmitVM::remote_system($ssh, $remote, "mkdir -p /home/".$arg_hash{"username"}."/install_scripts/");
		
		foreach my $localscript (@scripts) {
			my $localscript_basename = basename($localscript);
			SubmitVM::remote_system($ssh, $remote, "rm -f /home/".$arg_hash{"username"}."/install_scripts/".$localscript_basename);
			SubmitVM::myscp($scp, $localscript, $remote.":/home/".$arg_hash{"username"}."/install_scripts/".$localscript_basename)  || die "error: scp $localscript file";
			SubmitVM::remote_system($ssh, $remote, "chmod +x /home/".$arg_hash{"username"}."/install_scripts/".$localscript_basename);
		}
		
	}
	
	if (defined $arg_hash{"update"}) {
		SubmitVM::remote_system($ssh, $remote, "rm -f install_aweclient.sh ; wget -t 20 --retry-connrefused --waitretry 5 http://www.mcs.anl.gov/~wtang/files/install_aweclient.sh && chmod +x install_aweclient.sh && ./install_aweclient.sh") || die "error: wget install_aweclient.sh failed";
		
		#SubmitVM::execute_remote_command_in_screen_and_wait($ssh, $remote, "install_awe", 3, "./install_awe.sh");
		#SubmitVM::remote_system($ssh, $remote, "./install_aweclient.sh") || die "error: install_aweclient.sh failed";
	}
	
	if (defined $arg_hash{"k_update"}) {
		
		SubmitVM::deploy_software($ssh, $remote, "root" => 1, "packages" => ['kbase-mgrast-update']);
		
	}
	
	if (defined $arg_hash{"id_rsa"}) {
		my $localfile = $arg_hash{"id_rsa"};
		unless (-e $localfile) {
			die "local file \"$localfile\" not found";
		}
		
		my $ubuntu_rsa = "/home/".$arg_hash{"username"}."/.ssh/id_rsa";
		my $root_rsa = "/root/.ssh/id_rsa";
		
		SubmitVM::remote_system($ssh, $remote, "sudo rm -f  ".$ubuntu_rsa);
		sleep(1);
		SubmitVM::myscp($scp, $localfile, $remote.":".$ubuntu_rsa)  || die "error: scp $$localfile file";
		sleep(1);
		SubmitVM::remote_system($ssh, $remote, "chmod 600 ".$ubuntu_rsa." ; sudo rm -f ".$ubuntu_rsa." ; sudo ln -s ".$ubuntu_rsa." ".$root_rsa);
	}
	
	if (defined $arg_hash{"startawe"}) {
		#sudo start awe-client
		SubmitVM::remote_system($ssh, $remote, "sudo start awe-client") || print STDERR "warning $ip: sudo start awe-client failed";
	}
	
	if (defined $arg_hash{"stopawe"}) {
		#sudo start awe-client
		SubmitVM::remote_system($ssh, $remote, "sudo stop awe-client") || print STDERR "warning $ip: sudo stop awe-client failed";
	}
	
	if (defined $arg_hash{"restartawe"}) {
		#sudo start awe-client
		SubmitVM::remote_system($ssh, $remote, "sudo restart awe-client") || die "error $ip: sudo restart awe-client failed";
	}
	
	if (defined $arg_hash{"command"}) {
		my $command =  $arg_hash{"command"};
		my $return = SubmitVM::execute_remote_command_backtick($ssh, $remote, $command);
		return $return;
	}
	
	if (defined $arg_hash{"copy"}) {
		my $copy_thing =  $arg_hash{"copy"};
		
		my ($localfile, $target) = split(/:/, $copy_thing);
		unless (defined $target) {
			$target = "";
		}
		
		# scp x.txt remotehost:
		my $copy_cmd = "$scp $localfile $remote:$target";
		print "scp_cmd: $copy_cmd\n";
		system($copy_cmd) == 0 or die;
		
	}
	
	return;
}



#########################################################################




#############  START ###############


#$arg_hash{"saveIpToFile"} = 1;

unless (defined $arg_hash{"groupname"}) {
	$arg_hash{"groupname"}  = "awe".int(rand(90000)+10000);
}

unless (defined $arg_hash{"namelist"}) {
	$arg_hash{"namelist"} = $cities;
}

unless (defined $arg_hash{"flavor_name"}) {
	$arg_hash{"flavor_name"} = "idp.12";
}


ManageBulkInstances::runActions(\%arg_hash, [ $ManageBulkInstances::options_basicactions ]);








# for any VM actions

my $action_count = 0;

if (defined $arg_hash{"sshtest"}) {
	$action_count++;
}

for (my $i = 1; $i < @$options_awe_actions; $i+=3) {
	my $option = ${$options_awe_actions}[$i];
	($option) = split('\=', $option);
	
	#print "AWE action checked: $option\n";
	if (defined $arg_hash{$option}) {
		print "VM action found: $option\n";
		$action_count++;
	}
}

if ($action_count > 0) {

	print "perform $action_count VM action(s) ...\n";
	
	#if (@{$arg_hash{"iplist"}} == 0) {
	#	print STDERR "error: no IPs found\n";
	#	exit(1);
	#}
	
	
        my $result = ManageBulkInstances::parallell_job_new({"vmips_ref" => $arg_hash{"iplist"},
                                                             "group" => $arg_hash{"group"},
																"owner" => $arg_hash{"owner"},
																"nogroupcheck" => $arg_hash{"nogroupcheck"},
                                                             "groupname" => $arg_hash{"groupname"},
															 "instance_ips" => $arg_hash{"instance_ips"},
															 "instance_ids" => $arg_hash{"instance_ids"},
                                                             "instance_names" => $arg_hash{"instance_names"},
                                                             "function_ref" => \&thread_function
	});

	
	if (defined($result)) {
		
		foreach my $ident (keys %$result) {
			print "$ident (".$result->{$ident}{"ip"}.") returns:\n";
			print $result->{$ident}{"text"}."\n";
		}
		
	} else {
		
		if (defined $arg_hash{"sshtest"}) {
			print STDERR "warning: the ssh test failed!\n";
		} else {
			print STDERR "something went wrong, exit 1....\n";
			exit(1);
		}
	}
} else {
	print "no AWE actions to perform...\n";
}

print "done.\n";



