#!/bin/bash

# Exit on error
set -e

# Install Java (prerequisite)
sudo yum install -y java-11-amazon-corretto

# Create sonar user
sudo useradd -r -m -U -d /opt/sonarqube -s /bin/bash sonar

# Download and install SonarQube
sudo wget https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.0.65466.zip
sudo unzip sonarqube-9.9.0.65466.zip
sudo mv sonarqube-9.9.0.65466 /opt/sonarqube
sudo chown -R sonar:sonar /opt/sonarqube

# Configure system limits
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
echo "fs.file-max=65536" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Create systemd service file
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

[Install]
WantedBy=multi-user.target
EOF

# Start SonarQube service
sudo systemctl daemon-reload
sudo systemctl start sonarqube
sudo systemctl enable sonarqube

# Wait for service to start
echo "Waiting for SonarQube to start..."
sleep 30

# Check service status
sudo systemctl status sonarqube

# Print access instructions
echo "SonarQube installation completed!"
echo "You can access SonarQube at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000"
echo "Default credentials are admin/admin"