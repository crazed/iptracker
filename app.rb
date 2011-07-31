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

  def create_vlan(data)
    validate_new_vlan(data)
    cidr = NetAddr::CIDR.create(data['cidr'])
    vlan = Vlan.new(
      :vlan => data['vlan'], 
      :ip_version => cidr.version, 
      :netmask => cidr.netmask,
      :network => cidr.network,
      :description => data['description']
    )
    vlan.gateway = data['gateway'] || cidr.range(1,1).first
    vlan.save!
    vlan
  end

  def vlans
    vlans = Array.new
    Vlan.all.each do |vlan|
      vlans << vlan
    end
    vlans
  end

  def available_addresses(vlan)
    available = Array.new
    vlan.addresses.where(:in_use => false).each do |addr|
      available << addr.address
    end
    available
  end

  def vlan(id)
    Vlan.where(:vlan => id.to_i).first
  end

  def validate_new_vlan(data)
    missing = Array.new
    [ 'vlan', 'cidr', 'description' ].each do |req|
      if not data.include?(req)
        missing << req
      end
    end
    raise "Missing required options: #{missing.join(', ')}" if missing.size > 0
    
    vlan = data['vlan'].to_i
    raise 'Invalid VLAN' unless vlan
  end

  def update_vlan(vlan, data)
    # check the supplied data, error out on 
    # any invalid options
    data.each do |k,v|
      if vlan.fields.include?(k)
        vlan.send("#{k.to_sym}=", v)
      else
        raise "Invalid field: #{k}"
      end
    end
    vlan.save!
    vlan
  end


end

## Frontend Requests
#

get '/' do
  @vlans = vlans
  haml :index
end

get '/vlan/:vlan' do
  vlan = vlan(params[:vlan])
  if vlan.nil?
    redirect to '/'
  else
    @vlan = vlan
    haml :vlan
  end
end

get '/vlan/:vlan/addresses/:address' do
  vlan = vlan(params[:vlan])
  if vlan.nil?
    redirect to "/vlan/#{params[:vlan]}"
  else
    address = vlan.addresses.where(:address => params[:address]).first
    if address.nil?
      redirect to "/vlan/#{params[:vlan]}"
    else
      @vlan = vlan
      @address = address
      haml :address
    end
  end
end

#
## End Frontend Requests

## API Requests
#

get '/api/vlans' do
  status 200
  data = Array.new
  vlans.each do |vlan|
    data << vlan.to_h
  end
  body(data)
end

# remove a vlan id
delete '/api/vlan/:id' do
  vlan = vlan(params[:id])
  if vlan.nil?
    status 404
    body({ :error => "Vlan with this ID not found." }.to_json)
  else
    begin
      vlan.destroy
      status 200
    rescue Exception => error
      status 400
      body({ :error => error.to_s }.to_json)
    end
  end
end

# display a vlan id
get '/api/vlan/:id' do
  vlan = vlan(params[:id])
  if vlan.nil?
    status 404
    body({ :error => "Vlan with this ID not found." }.to_json)
  else
    status 200
    body(vlan.to_json)
  end
end

# create a new vlan id
put '/api/vlan' do
  begin
    data = JSON.parse(request.body.string)
    raise if data.nil?
  rescue
    status 400
    body({ :error => 'Invalid JSON' }.to_json)
    return
  end

  begin
    vlan = create_vlan(data)
    status 200
    body(vlan.to_json)
  rescue Exception => error
    status 400
    body({ :error => error.to_s }.to_json)
  end
end

# update vlan id
post '/api/vlan/:id' do
  vlan = vlan(params[:id])
  if vlan.nil?
    status 404
    body({ :error => 'VLAN does not exist' }.to_json)
    return
  end

  begin
    data = JSON.parse(request.body.string)
    raise if data.nil?
  rescue
    status 400
    body({ :error => 'Invalid JSON' }.to_json)
    return
  end

  begin
    vlan = update_vlan(vlan, data)
    status 200
    body(vlan.to_json)
  rescue Exception => error
    status 400
    body({ :error => error.to_s }.to_json)
  end
end

get '/api/vlan/:id/available_addresses' do
  vlan = vlan(params[:id])
  if vlan.nil?
    status 404
  else
    status 200
    body(available_addresses(vlan))
  end
end

get '/api/vlan/:id/addresses' do
  vlan = vlan(params[:id])
  if vlan.nil?
    status 404
  else
    status 200
    body(vlan.addresses_to_json)
  end
end

get '/api/vlan/:id/addresses/:address' do
  vlan = vlan(params[:id])
  if vlan.nil?
    status 404
  else
    address = nil
    vlan.addresses.where(:address => params[:address]).each do |addr|
      address = addr
    end
    if address.nil?
      status 404
    else
      status 200
      body(address.to_json)
    end
  end
end

post '/api/vlan/:id/addresses/:address' do
end

after '/api/*', :provides => :json do ; end

#
## End API Requests
