#mapr-vertica-sandbox

Welcome to the MapR Vertica Sandbox Generator!  Here, you'll find instructions for creating a virtual machine image with the MapR Distribution for Hadoop and Vertica.

###Step 1 - Get Packer
[Packer](www.packer.io) is a useful tool for automating the process of creating VM images, and it's what we use at MapR to create our sandbox.  To download and install it on a linux machine, do the following -
```
cd ~/
mkdir packer
cd packer
wget https://dl.bintray.com/mitchellh/packer/0.6.0_linux_amd64.zip
unzip 0.6.0_linux_amd64.zip
export PATH=$PATH:~/packer/
```

###Step 2 - Download the MapR sandbox
Substitute the MapR version number in the command below.
```
mkdir output-virtualbox-ovf
wget -P output-virtualbox-ovf/ http://archive.mapr.com/releases/v4.1.0/sandbox/ova/MapR-Sandbox-For-Hadoop-4.1.0.ova
```

###Step 3 - Create the VM
```
packer build --var 'mapr_version=4.1.0' --var 'partner_version=7.1.1' vertica-sandbox.json
```
