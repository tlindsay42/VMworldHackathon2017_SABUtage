# VMworldHackathon2017_SABUtage

## Infrastructure
### Management vCenter Server
* VC Address = 192.168.0.10
* Username = team4
* Password = VMware1!
### Team vPod Environment
#### vCenter Server
* Address = 192.168.4.10
* SSO Username = administrator@vsphere.local
* Password = VMware1!
* Root Password = VMware1!
#### ESXi Hosts
* Address = 192.168.4.1, 192.168.4.2, 192.168.4.3
* Root Password = VMware1!

#### vDS
Network = vxw-dvs-42-virtualwire-4-sid-5003-Team4

#### Static IP Range
* Range = 192.168.4.50 - 192.168.4.99
* Netmask = 255.255.255.0
* Gateway = 192.168.4.254

#### DHCP IP Range
* Range = 192.168.4.250 - 192.168.4.254
* Netmask = 255.255.255.0
* Gateway = 192.168.4.254

## Questions
### Infrastructure Questions
* Credentials?
* Number of virtual sites (3?)?
  * Separate network per virtual site?
  * Number of hosts per virtual site?
* dvSwitch?
* Jumbo frames (y/n)?
* Separate witness vmkernel adapter?
* Vester to implement host config?

### Project Questions
* Do we want to start a git repo for this?

## Requirements
### Infrastructure Requirements
* vmkernel adapter per host
  * VSAN service enabled
  * Networks
    *  
  * IP addresses
    *  
  * Other
* DRS enabled
  * Automation level
* HA initially disabled
* vSAN configured
* HA enabled
* Witness host appliance OVA
  * Downloaded
* Vester
  * Config directory
  * Config json
	
### Project Requirements
* Config
* Prerequisites deployment
* Validation tests
* VSAN config deployment
* Validation tests
* Post-config deployment
* Validation tests

# Tasks
* Ben
  * Witness deployment
* Steve
  * HA setup
  * DRS setup
* Troy
  * UI
