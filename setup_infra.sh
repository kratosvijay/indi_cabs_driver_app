#!/bin/bash

# Configuration
PROJECT_ID="indicabs-prod"
REGION="asia-south1"
NETWORK_NAME="indicabs-vpc"
SUBNET_NAME="connector-subnet"
CONNECTOR_NAME="cashfree-vpc"
ROUTER_NAME="indicabs-router"
NAT_NAME="indicabs-nat"
STATIC_IP_NAME="indicabs-static-ip"

echo "🚀 Starting Infrastructure Setup for $PROJECT_ID in $REGION..."

# 1. Create VPC Network
echo "🔹 Creating VPC Network: $NETWORK_NAME..."
gcloud compute networks create $NETWORK_NAME \
    --project=$PROJECT_ID \
    --subnet-mode=custom

# 2. Create Subnet for VPC Connector
echo "🔹 Creating Subnet: $SUBNET_NAME..."
gcloud compute networks subnets create $SUBNET_NAME \
    --project=$PROJECT_ID \
    --network=$NETWORK_NAME \
    --region=$REGION \
    --range=10.8.0.0/28

# 3. Create VPC Access Connector
echo "🔹 Creating VPC Access Connector: $CONNECTOR_NAME..."
gcloud compute networks vpc-access connectors create $CONNECTOR_NAME \
    --project=$PROJECT_ID \
    --region=$REGION \
    --network=$NETWORK_NAME \
    --range=10.8.0.0/28

# 4. Reserve Static External IP
echo "🔹 Reserving Static IP: $STATIC_IP_NAME..."
gcloud compute addresses create $STATIC_IP_NAME \
    --project=$PROJECT_ID \
    --region=$REGION

# 5. Create Cloud Router
echo "🔹 Creating Cloud Router: $ROUTER_NAME..."
gcloud compute routers create $ROUTER_NAME \
    --project=$PROJECT_ID \
    --network=$NETWORK_NAME \
    --region=$REGION

# 6. Create Cloud NAT with Static IP
echo "🔹 Creating Cloud NAT: $NAT_NAME..."
gcloud compute routers nats create $NAT_NAME \
    --project=$PROJECT_ID \
    --router=$ROUTER_NAME \
    --region=$REGION \
    --nat-all-subnet-ip-ranges \
    --nat-external-ip-pool=$STATIC_IP_NAME

echo "✅ Infrastructure Setup Requested!"
echo "--------------------------------------------------"
echo "Next Steps:"
echo "1. Wait a few minutes for the VPC Connector and NAT to be ready."
echo "2. Find your Static IP by running:"
echo "   gcloud compute addresses describe $STATIC_IP_NAME --region=$REGION --format='value(address)'"
echo "3. Copy this IP and whitelist it in your Cashfree Dashboard."
echo "4. Tell me 'Setup Done', and I will re-enable the VPC in your code."
echo "--------------------------------------------------"
