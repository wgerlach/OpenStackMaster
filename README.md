BulkVM
======

Perl modules for the instantiation of, configuration of and communication with multiple VMs in an Openstack environment.

Installation
------------
Install some Perl libraries:
> sudo apt-get install liblocal-lib-perl libio-all-lwp-perl<br>
> sudo cpan install Parallel::ForkManager File::Flock JSON Text::ASCIITable LWP::Protocol::https<br>

Make sure that Parallel::ForkManager is at least version 0.7.6.

Do a "git clone" of this repository or simply wget the two modules:
> wget https://github.com/wgerlach/BulkVM/raw/master/ManageBulkInstances.pm<br>
> wget https://github.com/wgerlach/BulkVM/raw/master/SubmitVM.pm<br>

If you want to use AWE, you might want to download this script:<br>
> wget https://github.com/wtangiit/vmScriptAWE/raw/master/vmAWE.pl<br>
> chmod +x vmAWE.pl<br>

Configure your ~/.bashrc and create ~/.bulkvm as explained below.<br>

Configuration
-------------
Please defined the following environment variables, or modify ManageBulkInstances.pm accordingly:<br>
> export OS_USERNAME=<br>
> export OS_PASSWORD=<br>
> export OS_AUTH_URL=<br>
> export OS_TENANT_NAME= or OS_TENANT_ID=<br>

Afterwards, do not forget to update the current shell:
> . ~/.bashrc

When you start VMs, you can specify some default options that are used when you create new VMs, e.g. default ssh key_name, or default image you want.<br>

~/.bulkvm<br>

> key_name=xyz<br>
> image_name=Ubuntu Precise 12.04 (Preferred Image)<br>

<br>
Options provided at command line have higher priority of course. Note that your private key file should have the same name as the key_name in Openstack and should be located in your ~/.ssh directory. In this example it would be ~/.ssh/xyz or ~/.ssh/xyz.pem .

Test configuration, e.g. with vmAWE.pl:<br>
> vmAWE.pl --info

ManageBulkInstances.pm 
----------------------
This modules containes functions to start multiple instances and attach volumes, if needed. It uses the OpenStack JSON-based API.

SubmitVM.pm
-----------
This module contains functions to communicate with the VMs via ssh and scp within a threaded environment. For each VM there is one thread that is responsible for the communication. Most important functionality is the execution of commands on the remote VMs. Long running jobs can be executed within a screen environment, which allows to detach from the VM and periodically check if the job is still running.
A nice and fancy feature is the execution of small perl functions directly on the remote VM, without the need to create a perl script and scp'ing to the VM.



Usage Example
-------------
This example is based on vmAWE.pl which is now maintained by Wei and can be found here:<br>
https://github.com/wtangiit/vmScriptAWE<br>

The first four option groups are generic, they are inherited from the ManageBulkInstances.pm module. Only the last two option groups (AWE actions and AWE options) are AWE-specifc options that are defined in the vmAWE.pl script.

options of vmAWE.pl: 

    Nova actions:
     --create=i            create i new instances from snapshot/image
     --delete              use with --group,ipfile or iplist
     --reboot=s            reboot all instances, "soft" or "hard"
     --info                list all instances, volumes, flavors...
     --listgroup=s         list all instances in this group (must be owner)
     --list                list all instances by group or instance_names/ip/id
     --savegroup=s         save group in ipfile
     --newgroupname=s      rename group (will not change hostname!)

    VM actions:
     --sshtest             try to ssh all instances

    Create options:
     --flavor_name=s       flavor name for hardware selection
     --image=s             image identifier
     --image_name=s        image name, as alternative to image identifer
     --key_name=s          ssh key_name as in Openstack
     --groupname=s         required, name of the new group
     --nogroupcheck        use this to add VMs to existing group
     --onlygroupname       instance names all equal groupname
     --namelist=s          comma-separated list of names to choose from
     --owner=s             optional, metadata information on VM, default os_username
     --disksize=i          in GB, creates, attaches, partitions and mounts volume
     --wantip              external IP, only with count=1
     --user-data=s         pass user data file to new instances
     --security_groups=s   security_groups
     --saveIpToFile        saves list of IPs in file
     --greedy              continue with VM creation, even if some fail
     --to_srv_create=s     timeout server create

    Other options:
     --noownercheck        disables owner check
     --debug               debug info

    Specify existing VMs for actions and deletion:
     --group=s             use VMs with this groupname (metadata-field)
     --instance_names=s    VMs with these names, requires --groupname
     --instance_ids=s      VMs with these IDs, requires --groupname
     --instance_ips=s      list of IPs, comma separated, use with --groupname

    AWE actions (independent, can be combinded):
     --addscripts=s        list of scripts, comma separated
     --deploy=s@           deploy any software on vm
     --root_deploy=s@      deploy any software on vm as root
     --deploy_target=s     deploy target
     --deploy_data_target=sspecifiy data target, e.g. /home/ubuntu/data/
     --awecfg=s@           configure AWE client: [section]key=value?key=value...
     --k_awecfg=s@         (KBase) configure AWE client: [section]key=value?key=value...
     --update              installs or updates AWE client
     --k_update            (KBase) updates AWE client
     --id_rsa=s            copy local file to /root/.ssh/id_rsa
     --startawe            
     --stopawe             
     --restartawe          
     --command=s           pass a command to all VMs, e.g. "df -h"
     --copy=s              scp file over to host, local:remote
     --snapshot=s          awesome feature that is not implemented yet
     --example             example for executing perl subroutine remotely


Show tenant resources:
> vmAWE.pl --info

Start instance from default image:
> vmAWE.pl --create 5 --flavor_name idp.100 --groupname mygroup

List group:
> vmAWE.pl --listgroup mygroup

Do something with group (script-specific, in this example the AWE client will be started on all VMs in the group "mygroup")
> vmAWE.pl --group mygroup --startawe

Delete group:
> vmAWE.pl --delete --group mygroup

Complicated AWE specific example (everything in one step: creates VMs, installs AWE clients, configures them, start clients):
> vmAWE.pl --create 2 --key_name dmnewmagellanpub --awecfg awe.cfg --groupname MY_UNIQUE_NAME --awegroup MY_UNIQUE_NAME --update --startawe    2>&1 | tee vmawe.log

