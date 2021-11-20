###########################################################################
#                 EventStore DB cluster
#  https://developers.eventstore.com/cloud/automation/#terraform-provider
###########################################################################

# In EventStoreCloud, add a project named FFT.Signals
resource "eventstorecloud_project" "signals" {
  name = "FFT.Signals"
}

# In EventStoreCloud, add a network to the FFT.Signals project
resource "eventstorecloud_network" "signals" {
  name              = "FFT.Signals"
  project_id        = eventstorecloud_project.signals.id
  resource_provider = "aws"
  region            = var.aws_region
  cidr_block        = "172.29.98.0/24"
}

# In EventStoreCloud, add an EventStore db cluster to the FFT.Signals network in the FFT.Signals project
resource "eventstorecloud_managed_cluster" "signals" {
  name             = "FFT.Signals"
  project_id       = eventstorecloud_project.signals.id
  network_id       = eventstorecloud_network.signals.id
  topology         = "single-node"
  instance_type    = "F1"
  disk_size        = 10
  disk_type        = "gp2"
  server_version   = "20.10"
  projection_level = "user"
}

# In EventStoreCloud, add a network peering request to the AWS vpc
resource "eventstorecloud_peering" "signals" {
  name = "FFT.Signals"

  project_id = eventstorecloud_network.signals.project_id
  network_id = eventstorecloud_network.signals.id

  peer_resource_provider = eventstorecloud_network.signals.resource_provider
  peer_network_region    = eventstorecloud_network.signals.region

  peer_account_id = data.aws_caller_identity.current.account_id
  peer_network_id = aws_vpc.signals.id
  routes          = toset([aws_vpc.signals.cidr_block])
}

# In AWS, accept the network peering request from EventStoreCloud
resource "aws_vpc_peering_connection_accepter" "eventstore" {
  vpc_peering_connection_id = eventstorecloud_peering.signals.provider_metadata.aws_peering_link_id
  auto_accept               = true
  tags = {
    Side = "Accepter"
  }
}

# In AWS, add routes to the EventStore network for all the public subnets
resource "aws_route" "eventstore-public" {
  for_each                  = toset(local.public_route_table_ids)
  route_table_id            = each.key
  destination_cidr_block    = eventstorecloud_network.signals.cidr_block
  vpc_peering_connection_id = eventstorecloud_peering.signals.provider_metadata.aws_peering_link_id
}

# In AWS, add routes to the EventStore network for all the private subnets
resource "aws_route" "eventstore-private" {
  for_each                  = toset(local.private_route_table_ids)
  route_table_id            = each.key
  destination_cidr_block    = eventstorecloud_network.signals.cidr_block
  vpc_peering_connection_id = eventstorecloud_peering.signals.provider_metadata.aws_peering_link_id
}