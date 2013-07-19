BulkVM
======

Perl modules for the instantiation of, configuration of and communication with multiple VMs in an Openstack environment.

Installation
------------
Install some Perl libraries:
> sudo apt-get install liblocal-lib-perl libio-all-lwp-perl<br>
> sudo cpan install Parallel::ForkManager File::Flock JSON Text::ASCIITable<br>

Make sure that Parallel::ForkManager is at least version 0.7.6.

Do a "git clone" of this repository or simply wget the two modules:
> wget https://github.com/wgerlach/BulkVM/raw/master/ManageBulkInstances.pm<br>
> wget https://github.com/wgerlach/BulkVM/raw/master/SubmitVM.pm<br>

If you want to use AWE, you might want to download this script:<br>
> wget https://github.com/wtangiit/vmScriptAWE/raw/master/vmAWE.pl<br>
> chmod +x vmAWE.pl<br>

Configure your ~/.bashrc and create ~/.bulkvm as explained below.<br>

Test vmAWE.pl:<br>
> vmAWE.pl --info


Configuration
-------------
Please defined the following environment variables, or modify ManageBulkInstances.pm accordingly:<br>
> OS_USERNAME=<br>
> OS_PASSWORD=<br>
> OS_AUTH_URL=<br>
> OS_TENANT_NAME= or OS_TENANT_ID=<br>

Afterwards, do not forget to update the current shell:
> . ~/.bashrc

When you start VMs, you can specify some default options that are used when you create new VMs, e.g. default ssh key_name, or default image you want. Username ubuntu is currently required.<br>

~/.bulkvm<br>

> key_name=xyz<br>
> image_name=Ubuntu Precise 12.04 (Preferred Image)<br>
> username=ubuntu<br>

<br>
Options provided at command line have higher priority of course. Note that your private key file should have the same name as the keyfile and should be located in your ~/.ssh directory. In this example it would be ~/.ssh/xyz.pem .

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
     --info                list all instances, volumes, flavors...
     --listgroup=s         list all instances in this group (must be owner)
     --savegroup=s         save group in ipfile

    VM actions:
     --sshtest             try to ssh all instances

    Create options:
     --flavor_name=s       optional, use with --create
     --image=s             image ID, use with --create
     --image_name=s        image name, use with action --create
     --key_name=s          required, key_name as in Openstack
     --groupname=s         optional, name of the new group
     --nogroupcheck        optional, use this to add VMs to existing group
     --onlygroupname       optional, instance names all equal groupname
     --owner=s             optional, metadata information on VM, default os_username
     --noownercheck        optional, disables owner check
     --disksize=i          optional, in GB, creates, attaches and mounts volume
     --wantip              optional, external IP, only with count=1
     --user-data=s         optional, pass user data file to new instances
     --saveIpToFile        optional, saves list of IPs in file

    Specify existing VMs for actions and deletion:
     --group=s             use VMs with this groupname (metadata-field)
     --instance=s          use single VMs with this instance name
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

 
Complicated AWE specific example:
> vmAWE.pl --create 2 --key_name dmnewmagellanpub --awecfg awe.cfg --groupname MY_UNIQUE_NAME --awegroup MY_UNIQUE_NAME --update --startawe    2>&1 | tee vmawe.log

Show tenant resources:
> vmAWE.pl --info

Start instance from default image:
> vmAWE.pl --create 5 --flavor_name idp.100 --groupname mygroup

List group:
> vmAWE.pl --listgroup mygroup

Do something with group (script-specific, in this AWE example the AWE client will started on all VMs in the group "mygroup")
> vmAWE.pl --group mygroup --startawe

Delete group:
> vmAWE.pl --delete --group mygroup
