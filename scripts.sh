#!/bin/bash

# Exit on error and enable debug output
set -e
set -x

echo "Starting SonarQube installation with debugging..."

# Function to check system resources
check_system_resources() {
    echo "Checking system resources..."
    free -h
    df -h
    nproc
}

# Function to verify Java
verify_java() {
    echo "Verifying Java installation..."
    which java
    java -version
    echo $JAVA_HOME
}

# Clean up any previous installation
echo "Cleaning up previous installation..."
sudo systemctl stop sonarqube || true
sudo rm -rf /opt/sonarqube*
sudo rm -f /etc/systemd/system/sonarqube.service

# Remove existing Java
echo "Removing existing Java..."
sudo yum remove -y java* || true

# Install Java 11
echo "Installing Java 11..."
sudo yum install -y java-11-amazon-corretto
verify_java

# Install required packages
echo "Installing required packages..."
sudo yum install -y unzip wget

# Configure larger swap
echo "Configuring swap..."
sudo swapoff -a || true
sudo rm -f /swapfile
sudo dd if=/dev/zero of=/swapfile bs=1M count=8192
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Create sonar user
echo "Creating sonar user..."
sudo userdel -r sonar || true
sudo useradd -r -m -U -d /opt/sonarqube -s /bin/bash sonar

# Set up directories
echo "Setting up directories..."
sudo rm -rf /opt/sonarqube
sudo mkdir -p /opt/sonarqube
sudo mkdir -p /opt/sonarqube/data
sudo mkdir -p /opt/sonarqube/temp
sudo mkdir -p /opt/sonarqube/logs

# Download and install SonarQube
echo "Downloading SonarQube..."
cd /tmp
sudo wget --no-verbose https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-9.9.0.65466.zip
sudo unzip -q sonarqube-9.9.0.65466.zip
sudo cp -r sonarqube-9.9.0.65466/* /opt/sonarqube/
sudo rm -rf sonarqube-9.9.0.65466*

# Set permissions
echo "Setting permissions..."
sudo chown -R sonar:sonar /opt/sonarqube
sudo chmod -R 755 /opt/sonarqube

# Configure system limits
echo "Configuring system limits..."
sudo tee /etc/security/limits.d/99-sonarqube.conf << EOF
sonar   soft    nofile   65536
sonar   hard    nofile   65536
EOF

sudo tee /etc/sysctl.d/99-sonarqube.conf << EOF
vm.max_map_count=524288
fs.file-max=131072
EOF

sudo sysctl --system

# Configure SonarQube
echo "Configuring SonarQube..."
sudo tee /opt/sonarqube/conf/sonar.properties << EOF
sonar.web.javaOpts=-Xmx512m -Xms128m -XX:+HeapDumpOnOutOfMemoryError
sonar.ce.javaOpts=-Xmx512m -Xms128m -XX:+HeapDumpOnOutOfMemoryError
sonar.search.javaOpts=-Xmx512m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.path.data=/opt/sonarqube/data
sonar.path.temp=/opt/sonarqube/temp
sonar.telemetry.enabled=false
EOF

# Create service file with enhanced debugging
echo "Creating service file..."
sudo tee /etc/systemd/system/sonarqube.service << EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh console
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=sonar
Group=sonar
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/sonarqube/logs/stdout.log
StandardError=append:/opt/sonarqube/logs/stderr.log
LimitNOFILE=65536
LimitNPROC=4096
TimeoutStartSec=180
Environment=JAVA_HOME=/usr/lib/jvm/java-11
Environment=PATH=/usr/lib/jvm/java-11/bin:${PATH}

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
echo "Starting SonarQube..."
sudo systemctl daemon-reload
sudo systemctl enable sonarqube
sudo systemctl start sonarqube

# Function to check service status with enhanced logging
check_service_status() {
    echo "Checking service status..."
    sudo systemctl status sonarqube
    echo "Checking logs..."
    sudo tail -n 50 /opt/sonarqube/logs/sonar.log
    sudo tail -n 50 /opt/sonarqube/logs/es.log
    sudo tail -n 50 /opt/sonarqube/logs/stdout.log
    sudo tail -n 50 /opt/sonarqube/logs/stderr.log
}

# Wait and check status
echo "Waiting for service to start..."
sleep 30
check_service_status
check_system_resources

# Create convenience script for log viewing
sudo tee /usr/local/bin/sonar-logs << EOF
#!/bin/bash
echo "=== SonarQube Logs ==="
sudo tail -f /opt/sonarqube/logs/sonar.log /opt/sonarqube/logs/es.log
EOF
sudo chmod +x /usr/local/bin/sonar-logs

echo "Installation complete. To view logs, run: sonar-logs"
echo "Access SonarQube at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000"
echo "Default credentials: admin/admin"