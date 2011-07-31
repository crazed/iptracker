#!/usr/bin/env ruby
require 'rubygems'
require 'sinatra'
require 'netaddr'
require 'mongoid'
require 'json'
require 'haml'

Mongoid.configure do |config|
    config.master = Mongo::Connection.new.db("godfather4")
end

## Begin Model Definitions
#

class Vlan
  include Mongoid::Document
  field :ip_version, :type => Integer
  field :netmask, :type => String
  field :network, :type => String
  field :vlan, :type => Integer
  field :description, :type => String
  field :gateway, :type => String
  embeds_many :addresses

  index :vlan, :unique => true
  validates_uniqueness_of :vlan
  validates_format_of :netmask, :with => /\/\d+/

  before_save :verify_no_overlap
  before_save :verify_addresses
  before_save :verify_gateway
  before_create :generate_addresses

  def available_addresses
    available = Array.new
    self.addresses.where(:in_use => false).each do |addr|
      available << addr
    end
    available
  end

  def addresses_to_json
    data = Hash.new
    self.addresses.each do |addr|
      data[addr.address] = addr.to_json
    end
    data
  end

  def to_h
    data = {
      :ip_version   => self.ip_version,
      :netmask      => self.netmask,
      :vlan         => self.vlan,
      :description  => self.description,
      :gateway      => self.gateway,
      :addresses    => Hash.new
    }
    
    self.addresses.each do |addr|
      data[:addresses][addr.address] = addr.to_h
    end
    data
  end

  def to_json
    to_h.to_json
  end

  protected
  def generate_addresses
    cidr = NetAddr::CIDR.create("#{self.network}#{self.netmask}")
    cidr.range(1, cidr.size-2).each do |address|
      self.addresses.new(:address => address, :in_use => false)
    end
  end
  
  # This checks that the addresses embedded
  # actually should exist in the range, if the check fails
  # delete all embedded addresses and re-generate them
  def verify_addresses
    cidr = NetAddr::CIDR.create("#{self.network}#{self.netmask}")
    if not cidr.contains?(self.addresses.first.address) or not cidr.contains?(self.addresses.last.address)
      self.addresses.delete_all
      generate_addresses
    end
  end

  # Make sure that the gateway is included in the ip range
  def verify_gateway
    cidr = NetAddr::CIDR.create("#{self.network}#{self.netmask}")
    if not cidr.contains?(self.gateway)
      raise "Gateway is not contained in the IP range"
    end
  end

  # This loops through all VLANs to verify
  # that there is no overlapping IP space
  def verify_no_overlap
    new_cidr = NetAddr::CIDR.create("#{self.network}#{self.netmask}")
    new_vlan_min = NetAddr.ip_to_i(new_cidr.first)
    new_vlan_max = NetAddr.ip_to_i(new_cidr.last)
    Vlan.all.each do |vlan|
      if vlan._id == self._id
        next # skip checking yourself
      end
      vlan_cidr = NetAddr::CIDR.create("#{vlan.network}#{vlan.netmask}")
      vlan_min = NetAddr.ip_to_i(vlan_cidr.first)
      vlan_max = NetAddr.ip_to_i(vlan_cidr.last)
      check_overlap = (vlan_min - new_vlan_max) * (new_vlan_min - vlan_max)
      if check_overlap >= 0
        raise "VLAN overlaps with existing vlan: #{vlan.vlan} (#{vlan.description})"
      end
    end
  end
end

class Address
  include Mongoid::Document
  field :address, :type => String
  field :in_use, :type => Boolean
  embeds_one :device
  embedded_in :vlan

  index :address, :unique => true
  index :in_use
  validates_uniqueness_of :address

  def to_h
    data = {
      :in_use       => self.in_use
    }

    if self.device
      data[:device] = self.device.to_h
    end

    data
  end

  def to_json
    to_h.to_json
  end
end

class Device
  include Mongoid::Document
  field :hostname, :type => String
  embedded_in :address

  index :hostname, :unique => true
  validates_uniqueness_of :hostname

  def to_h
    data = {
      :hostname     => self.hostname
    }
  end

  def to_json
    to_h.to_json
  end
end

#
## End Model Definitions


helpers do
  include Rack::Utils
  def vlans
    Vlan.all
  end

  def vlan(id)
    Vlan.where(:vlan => id.to_i).first
  end
end

#
## End Frontend Requests

## API Requests
#

get '/api/vlans' do
  vlans.each do |vlan|
    #p vlan.attributes
    p vlan.to_h
  end
  status 200
end

# remove a vlan id
delete '/api/vlan/:id' do
end

# display a vlan id
get '/api/vlan/:id' do
  vlan = vlan(params[:id])
  if vlan
    p vlan.to_json
    status 200
    body(vlan.to_json.to_yaml)
  else
    status 404
  end
end

# create a new vlan id
put '/api/vlan/:id' do
end

# update vlan id
post '/api/vlan/:id' do
end

get '/api/vlan/:id/available_addresses' do
  vlan = vlan(params[:id])
  if vlan
    status 200
    available_addresses = Array.new
    vlan.addresses.where(:in_use => false).each do |addr|
      available_addresses << addr.address
    end
    body(available_addresses.to_yaml)
  else
    status 404
  end
end

get '/api/vlan/:id/addresses' do
  vlan = vlan(params[:id])
  if vlan
    status 200
    addresses = Hash.new
    vlan.addresses.each do |addr|
      addresses.merge!(addr.address => addr.to_json)
    end
    body(addresses.to_yaml)
  else
    status 404
  end
end

get '/api/vlan/:id/addresses/:address' do
  vlan = vlan(params[:id])
  if vlan
    status 200
    address = nil
    vlan.addresses.where(:address => params[:address]).each do |addr|
      address = addr.to_json
    end
    body(address.to_yaml)
  else
    status 404
  end
end

post '/api/vlan/:id/addresses/:address' do
end

#
## End API Requests
