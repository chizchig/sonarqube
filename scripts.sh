#!/bin/bash

# Exit on error
set -e

# Log all output
exec 1> >(logger -s -t $(basename $0)) 2>&1

# Update system packages
echo "Updating system packages..."
sudo yum update -y

# Install essential tools
echo "Installing essential tools..."
sudo yum install -y \
    wget \
    git \
    htop \
    vim \
    docker \
    java-11-amazon-corretto \
    python3 \
    python3-pip \
    jq \
    unzip

# Start and enable Docker service
echo "Configuring Docker..."
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ec2-user

# Configure storage volumes
echo "Configuring storage volumes..."

# Configure the EBS volume (1000GB)
if [ -b "/dev/xvda" ]; then
    echo "Configuring EBS volume..."
    
    # Check if the volume is already mounted
    if ! mountpoint -q /data; then
        # Create mount point if it doesn't exist
        sudo mkdir -p /data
        
        # Check if the volume is already formatted
        if ! blkid /dev/xvda | grep -q 'TYPE='; then
            sudo mkfs -t xfs /dev/xvda
        fi
        
        # Add to fstab if not already present
        if ! grep -q '/dev/xvda' /etc/fstab; then
            echo "/dev/xvda /data xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab
        fi
        
        # Mount volume
        sudo mount /data || echo "Mount failed, but continuing..."
    else
        echo "/data is already mounted, skipping mount step"
    fi
fi

# Set up swap space
echo "Configuring swap space..."
if [ ! -f /swapfile ]; then
    sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab
fi

# Install AWS CLI v2
echo "Installing AWS CLI..."
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
fi

# Set up CloudWatch agent
echo "Installing CloudWatch agent..."
sudo yum install -y amazon-cloudwatch-agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:/AmazonCloudWatch-Config

# Configure system limits
echo "Configuring system limits..."
cat << EOF | sudo tee /etc/security/limits.d/custom.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF

# Configure sysctl parameters
echo "Configuring sysctl parameters..."
cat << EOF | sudo tee /etc/sysctl.d/99-custom.conf
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_max_syn_backlog = 20480
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65536
vm.swappiness = 10
EOF

sudo sysctl -p /etc/sysctl.d/99-custom.conf

# Set timezone
sudo timedatectl set-timezone UTC

# Create status file
echo "Bootstrap completed at $(date)" | sudo tee /var/log/bootstrap-complete

echo "Bootstrap script completed successfully"