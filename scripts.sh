#!/bin/bash

# Exit on error
set -e

echo "Starting SonarQube installation..."

# Remove any existing Java installations
echo "Removing existing Java installations..."
sudo yum remove java* -y

# Install Java 11 (prerequisite)
echo "Installing Java 11..."
sudo yum install -y java-11-amazon-corretto

# Verify Java installation
java -version

# Set up swap space for memory management
echo "Setting up swap space..."
if [ ! -f /swapfile ]; then
    sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# Install required packages
echo "Installing required packages..."
sudo yum install -y unzip wget

# Create sonar user
echo "Creating sonar user..."
sudo useradd -r -m -U -d /opt/sonarqube -s /bin/bash sonar || echo "User sonar already exists"

# Download and install SonarQube
echo "Downloading and installing SonarQube..."
cd /tmp
sudo wget --no-verbose https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.0.65466.zip
sudo unzip -q sonarqube-9.9.0.65466.zip
sudo rm -rf /opt/sonarqube
sudo mv sonarqube-9.9.0.65466 /opt/sonarqube
sudo chown -R sonar:sonar /opt/sonarqube

# Configure SonarQube
echo "Configuring SonarQube..."
sudo tee -a /opt/sonarqube/conf/sonar.properties << EOF
sonar.web.javaOpts=-Xmx512m -Xms128m
sonar.ce.javaOpts=-Xmx512m -Xms128m
sonar.search.javaOpts=-Xmx512m -Xms512m
sonar.path.data=/opt/sonarqube/data
sonar.path.temp=/opt/sonarqube/temp
EOF

# Configure system limits
echo "Configuring system limits..."
sudo tee -a /etc/security/limits.conf << EOF
sonar   soft    nofile   65536
sonar   hard    nofile   65536
sonar   soft    nproc    4096
sonar   hard    nproc    4096
EOF

sudo tee /etc/sysctl.d/99-sonarqube.conf << EOF
vm.max_map_count=262144
fs.file-max=65536
EOF

sudo sysctl -p /etc/sysctl.d/99-sonarqube.conf

# Create systemd service file
echo "Creating systemd service..."
sudo tee /etc/systemd/system/sonarqube.service << EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonar
Group=sonar
Restart=always
LimitNOFILE=65536
LimitNPROC=4096
Environment="JAVA_HOME=/usr/lib/jvm/java-11"

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start SonarQube
echo "Starting SonarQube service..."
sudo systemctl daemon-reload
sudo systemctl start sonarqube
sudo systemctl enable sonarqube

# Wait for service to start
echo "Waiting for SonarQube to start..."
sleep 60

# Check service status
echo "Checking service status..."
sudo systemctl status sonarqube

# Verify port is listening
echo "Checking if port 9000 is listening..."
netstat -tulpn | grep 9000

# Print access instructions
echo "SonarQube installation completed!"
echo "You can access SonarQube at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000"
echo "Default credentials are admin/admin"

# Print memory status
echo "Current memory status:"
free -h

# Check Java version
echo "Installed Java version:"
java -version

echo "Installation complete. Please wait a few minutes for SonarQube to fully initialize."