BulkVM
======

Perl modules for the instantiation of, configuration of and communication with multiple VMs in an Openstack environment

Requirements
------------
Nova-Tools (http://docs.openstack.org/cli/quick-start/content/install_openstack_nova_cli.html)<br>
Perl modules: Parallel::ForkManager 0.7.6, File::Flock

ManageBulkInstances.pm 
----------------------
This modules containes functions to start multiple instances and attach volumes, if needed. At the moment this script uses the nova tools, in the future I will switch to using the JSON-based API.

SubmitVM.pm
-----------
This module contains functions to communicate with the VMs via ssh and scp. Most important functionality is the execution of commands on the remote VMs. Long running jobs can be executed within a screen environment, which allows to detach from the VM and periodically check if the job is still running.
A nice and fancy feature is the execution of small perl functions directly on the remote VM, without the need to create a perl script and scp'ing to the VM.

Configuration file
------------------
When you start VMs, you have to specify some options like which ssh key to use, or which image you want. If you are lazy as I am, configure any option in the .bulkvm file in you home directory, like this:<br>
<br>
~/.bulkvm<br>
sshkey=~/.ssh/x.pem<br>
key_name=x<br>
image_name=Ubuntu Precise 12.04 (Preferred Image)<br>
username=ubuntu<br>
<br>
Options provided at command line or in the IpFile have higher priority of course.


Usage Example
-------------

example with vmAWE.pl 

    Nova actions:
     --create=i            create i new instances from snapshot/image
     --delete              use with --ipfile (recommended) or --iplist
     --info                list all instances, volumes, flavors...
     --listgroup           list all instances with prefix --groupname
     --savegroup           save group with prefix --groupname in ipfile

    VM actions:
     --sshtest             try to ssh all instances

    Create options:
     --flavor_name=s       optional, use with --create
     --image=s             image ID, use with --create
     --image_name=s        image name, use with action --create
     --sshkey=s            required, path to ssh key file
     --key_name=s          required, key_name as in Openstack
     --groupname=s         optional, Openstack instance prefix name
     --nogroupcheck        optional, disables check for unique groupname
     --onlygroupname       optional, instance names all equal groupname
     --disksize=i          optional, in GB, default 300GB
     --wantip              optional, external IP, only with count=1
     --user-data=s         optional, pass user data file to new instances
     --saveIpToFile        optional, saves list of IPs in file (recommended)

    Specify existing VMs for actions and deletion:
     --ipfile=s            file containing list of ips with names
     --iplist=s@           list of ips, comma separated, use with --sshkey

    AWE actions (independent, can be combinded):
     --addscripts=s        list of scripts, comma separated
     --awecfg=s            see --serverurl and --awegroup
     --update              installs or updates AWE client
     --startawe            
     --stopawe             
     --restartawe          
     --command=s           pass a command to all VMs, e.g. "df -h"
     --example             example for executing perl subroutine remotely

    AWE options:
     --serverurl=s         optional, use with action --awecfg
     --awegroup=s          optional, use with actions --awecfg

 
     Option priorities: 1) command line 2) ipfile 3) ~/.bulkvm ; for 2 and 3 use: sshkey=~/.ssh/dm_new_magellan.pem
 
     example: ./vmAWE.pl --create 2 --sshkey ~/.ssh/x.pem --key_name x --awecfg awe.cfg --groupname MY_UNIQUE_NAME --awegroup MY_UNIQUE_NAME --update --startawe    2>&1 | tee vmawe.log
