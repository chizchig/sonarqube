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

# Install required packages
echo "Installing required packages..."
sudo yum install -y unzip wget

# Set up swap space for memory management
echo "Setting up swap space..."
if [ ! -f /swapfile ]; then
    sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

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

# Set correct permissions
sudo chown -R sonar:sonar /opt/sonarqube
sudo chmod -R 755 /opt/sonarqube

# Configure system limits
echo "Configuring system limits..."
sudo tee -a /etc/security/limits.conf << EOF
sonar   soft    nofile   131072
sonar   hard    nofile   131072
sonar   soft    nproc    8192
sonar   hard    nproc    8192
EOF

sudo tee /etc/sysctl.d/99-sonarqube.conf << EOF
vm.max_map_count=262144
fs.file-max=131072
EOF

sudo sysctl -p /etc/sysctl.d/99-sonarqube.conf

# Configure SonarQube properties
echo "Configuring SonarQube properties..."
sudo tee /opt/sonarqube/conf/sonar.properties << EOF
sonar.web.javaOpts=-Xmx1024m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
sonar.ce.javaOpts=-Xmx1024m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
sonar.search.javaOpts=-Xmx1024m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.path.data=/opt/sonarqube/data
sonar.path.temp=/opt/sonarqube/temp
sonar.jdbc.username=sonar
sonar.jdbc.password=sonar
EOF

# Create directories for SonarQube data
sudo mkdir -p /opt/sonarqube/data
sudo mkdir -p /opt/sonarqube/temp
sudo chown -R sonar:sonar /opt/sonarqube/data
sudo chown -R sonar:sonar /opt/sonarqube/temp
sudo chmod -R 755 /opt/sonarqube/data
sudo chmod -R 755 /opt/sonarqube/temp

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
Restart=on-failure
RestartSec=30
LimitNOFILE=131072
LimitNPROC=8192
TimeoutStartSec=180
Environment=JAVA_HOME=/usr/lib/jvm/java-11
Environment=SONAR_JAVA_PATH=/usr/lib/jvm/java-11/bin/java

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
echo "Reloading systemd..."
sudo systemctl daemon-reload

# Start SonarQube
echo "Starting SonarQube..."
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
sudo netstat -tulpn | grep 9000

# Show memory status
echo "Current memory status:"
free -h

# Show Java version
echo "Installed Java version:"
java -version

# Show logs if service failed
if ! systemctl is-active --quiet sonarqube; then
    echo "SonarQube failed to start. Checking logs..."
    echo "=== sonar.log ==="
    sudo tail -n 50 /opt/sonarqube/logs/sonar.log
    echo "=== es.log ==="
    sudo tail -n 50 /opt/sonarqube/logs/es.log
    echo "=== ce.log ==="
    sudo tail -n 50 /opt/sonarqube/logs/ce.log
    echo "=== web.log ==="
    sudo tail -n 50 /opt/sonarqube/logs/web.log
fi

# Print access instructions
echo "SonarQube installation completed!"
echo "You can access SonarQube at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000"
echo "Default credentials are admin/admin"
echo "Note: It might take a few minutes for SonarQube to initialize completely."

# Create a log viewing script for convenience
sudo tee /usr/local/bin/sonarqube-logs << EOF
#!/bin/bash
echo "=== SonarQube Logs ==="
sudo tail -f /opt/sonarqube/logs/sonar.log /opt/sonarqube/logs/es.log /opt/sonarqube/logs/web.log /opt/sonarqube/logs/ce.log
EOF

sudo chmod +x /usr/local/bin/sonarqube-logs

echo "A log viewing script has been created. Run 'sonarqube-logs' to view all SonarQube logs."