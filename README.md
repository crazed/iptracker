# IP Tracker #
I wanted to come up with a simple way of storing and manipulating data regarding IP addresses on the network, so I used Sinatra to create a simple REST api. Currently the frontend views are limited in what they can do and have no styling. This is the very start of the project, so a lot of functionality may be missing or incomplete.

## Example Usage ##
### VLANs ###
A VLAN contains many IP addresses which are one to one mapped to devices.
#### Create a new vlan ####
    curl -i -X PUT -d '{ "vlan": 2, "cidr": "10.0.1.1/24", "description": "database servers" }' localhost:4567/api/vlan
#### Read a vlan ####
    curl localhost:4567/api/vlan/2
#### Update a vlan ####
    curl -i -X POST -d '{ "gateway": "10.0.1.2" }' localhost:4567/api/vlan/2
#### Delete a vlan ####
    curl -i -X DELETE localhost:4567/api/vlan/2
### Devices ###
This is not implemented yet, but eventually a device will require a hostname, and have any amount of additional attributes tacked on, things like physical location, MAC addresses, etc can be added to the additional attributes field.
