#!/bin/bash

# Exit on error
set -e

echo "Starting SonarQube installation with systemd service setup..."

# Function to wait for yum lock
wait_for_yum_lock() {
    while sudo fuser /var/run/yum.pid >/dev/null 2>&1 ; do
        echo "Waiting for other yum processes to complete..."
        sleep 5
    done
}

# Default configuration variables
SONARQUBE_VERSION=${SONARQUBE_VERSION:-"10.3.0.82913"}
SONARQUBE_USER=${SONARQUBE_USER:-"sonar"}
SONARQUBE_PASSWORD=${SONARQUBE_PASSWORD:-"admin123"}
INSTALL_DIR=${INSTALL_DIR:-"/opt/sonarqube"}

# Setup swap space
echo "Setting up swap space..."
if [ ! -f /swapfile ]; then
    sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# Configure system settings
echo "Configuring system settings..."
sudo tee /etc/sysctl.d/99-sonarqube.conf << EOF
vm.max_map_count=524288
fs.file-max=131072
EOF

sudo sysctl --system

# Configure security limits
echo "Configuring security limits..."
sudo tee /etc/security/limits.d/99-sonarqube.conf << EOF
${SONARQUBE_USER}   -   nofile   131072
${SONARQUBE_USER}   -   nproc    8192
* soft nofile 131072
* hard nofile 131072
* soft nproc 8192
* hard nproc 8192
EOF

# Install Java
echo "Installing Java 17..."
wait_for_yum_lock
sudo yum remove java* -y || true
wait_for_yum_lock
sudo yum install -y java-17-amazon-corretto
java -version

# Download and install SonarQube
echo "Installing SonarQube version ${SONARQUBE_VERSION}..."
cd /tmp
sudo curl -L -O https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip
wait_for_yum_lock
sudo yum install unzip -y
sudo unzip -o sonarqube-${SONARQUBE_VERSION}.zip
sudo rm -rf ${INSTALL_DIR}
sudo mv sonarqube-${SONARQUBE_VERSION} ${INSTALL_DIR}

# Create sonar user and set permissions
echo "Creating sonar user and setting permissions..."
sudo groupadd sonar || true
sudo useradd -r -m -c "SonarQube User" -d ${INSTALL_DIR} -g sonar ${SONARQUBE_USER} || true
sudo chown -R ${SONARQUBE_USER}:sonar ${INSTALL_DIR}
sudo chmod -R 755 ${INSTALL_DIR}

# Create necessary directories with proper permissions
sudo mkdir -p ${INSTALL_DIR}/data
sudo mkdir -p ${INSTALL_DIR}/temp
sudo mkdir -p ${INSTALL_DIR}/logs
sudo chown -R ${SONARQUBE_USER}:sonar ${INSTALL_DIR}/data
sudo chown -R ${SONARQUBE_USER}:sonar ${INSTALL_DIR}/temp
sudo chown -R ${SONARQUBE_USER}:sonar ${INSTALL_DIR}/logs
sudo chmod -R 755 ${INSTALL_DIR}/data
sudo chmod -R 755 ${INSTALL_DIR}/temp
sudo chmod -R 755 ${INSTALL_DIR}/logs

# Configure SonarQube
echo "Configuring SonarQube..."
sudo tee ${INSTALL_DIR}/conf/sonar.properties << EOF
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.web.javaOpts=-Xmx2048m -Xms1024m -XX:+HeapDumpOnOutOfMemoryError
sonar.ce.javaOpts=-Xmx2048m -Xms1024m -XX:+HeapDumpOnOutOfMemoryError
sonar.search.javaOpts=-Xmx2048m -Xms1024m -XX:+HeapDumpOnOutOfMemoryError
sonar.path.data=${INSTALL_DIR}/data
sonar.path.temp=${INSTALL_DIR}/temp
sonar.log.level=INFO
sonar.path.logs=${INSTALL_DIR}/logs
EOF

# Create systemd service file
echo "Creating systemd service file..."
sudo tee /etc/systemd/system/sonarqube.service << EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=simple
User=${SONARQUBE_USER}
Group=sonar
PermissionsStartOnly=true
ExecStart=${INSTALL_DIR}/bin/linux-x86-64/sonar.sh console
StandardOutput=journal
StandardError=journal
LimitNOFILE=131072
LimitNPROC=8192
TimeoutStartSec=5m
Restart=always
SuccessExitStatus=143
Environment=JAVA_HOME=/usr/lib/jvm/java-17

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start SonarQube
echo "Starting SonarQube..."
sudo systemctl daemon-reload
sudo systemctl enable sonarqube
sudo systemctl start sonarqube

# Wait for service to start
echo "Waiting for SonarQube to start..."
sleep 30

# Check service status
echo "Checking service status..."
sudo systemctl status sonarqube

# Get public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "Installation complete! Access SonarQube at: http://${PUBLIC_IP}:9000"
echo "Default credentials: admin/admin"
echo "To check logs, use: sudo journalctl -u sonarqube -f"