BulkVM
======

Perl modules for the instantiation of, configuration of and communication with multiple VMs in an Openstack environment

Requirements
------------
Nova-Tools (http://docs.openstack.org/cli/quick-start/content/install_openstack_nova_cli.html)<br>
Perl modules: Parallel::ForkManager 0.7.6, File::Flock

ManageBulkInstances.pm 
----------------------
This modules containes functions to start mutiple instances and attach volumes, if needed. At the moment this script uses the nova tools, in the future I will switch to using the JSON-based API.

SubmitVM.pm
-----------
This module contains functions to communicate with the VMs via ssh and scp. Most improtant functionality execution of commands on the remote VMs. Long running jobs can be executed within a screen environment, which allows to detach from the VM and periodically check if the job is still running.
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
soon
