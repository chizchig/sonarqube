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
POSTGRESQL_VERSION=${POSTGRESQL_VERSION:-"14"}
JAVA_VERSION=${JAVA_VERSION:-"17"}
SONARQUBE_USER=${SONARQUBE_USER:-"sonar"}
SONARQUBE_PASSWORD=${SONARQUBE_PASSWORD:-"admin123"}
SONARQUBE_DB=${SONARQUBE_DB:-"sonarqube"}
SONARQUBE_PORT=${SONARQUBE_PORT:-"9000"}
INSTALL_DIR=${INSTALL_DIR:-"/opt/sonarqube"}

# Check system resources
echo "Checking system resources..."
free -h
df -h
nproc

# Set up swap if needed
if free -m | awk 'NR==2{print $2}' | awk '{ if ($1 < 4096) exit 1; }'; then
    echo "Sufficient memory available"
else
    echo "Setting up swap space..."
    sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# Backup system configurations
echo "Backing up system configurations..."
sudo cp /etc/sysctl.conf /root/sysctl.conf_backup || true
sudo cp /etc/security/limits.conf /root/sec_limit.conf_backup || true

# Configure system settings
echo "Configuring system settings..."
sudo tee /etc/sysctl.d/99-sonarqube.conf << EOF
vm.max_map_count=262144
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
echo "Installing Java ${JAVA_VERSION}..."
wait_for_yum_lock
sudo yum remove java* -y || true
wait_for_yum_lock
sudo yum install -y java-${JAVA_VERSION}-amazon-corretto
java -version

# Install PostgreSQL repository
echo "Adding PostgreSQL repository..."
wait_for_yum_lock
sudo yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Install PostgreSQL
echo "Installing PostgreSQL ${POSTGRESQL_VERSION}..."
wait_for_yum_lock
sudo yum install -y postgresql${POSTGRESQL_VERSION}-server postgresql${POSTGRESQL_VERSION}

# Initialize PostgreSQL
echo "Initializing PostgreSQL..."
sudo /usr/pgsql-${POSTGRESQL_VERSION}/bin/postgresql-${POSTGRESQL_VERSION}-setup initdb
sudo systemctl enable postgresql-${POSTGRESQL_VERSION}
sudo systemctl start postgresql-${POSTGRESQL_VERSION}

# Verify PostgreSQL installation
if ! systemctl is-active --quiet postgresql-${POSTGRESQL_VERSION}; then
    echo "PostgreSQL installation failed!"
    exit 1
fi

# Configure PostgreSQL
echo "Configuring PostgreSQL..."
sudo -u postgres psql << EOF
CREATE USER ${SONARQUBE_USER} WITH ENCRYPTED PASSWORD '${SONARQUBE_PASSWORD}';
CREATE DATABASE ${SONARQUBE_DB} OWNER ${SONARQUBE_USER};
GRANT ALL PRIVILEGES ON DATABASE ${SONARQUBE_DB} TO ${SONARQUBE_USER};
\q
EOF

# Configure PostgreSQL authentication
sudo sed -i 's/peer/trust/g' /var/lib/pgsql/${POSTGRESQL_VERSION}/data/pg_hba.conf
sudo sed -i 's/ident/md5/g' /var/lib/pgsql/${POSTGRESQL_VERSION}/data/pg_hba.conf
sudo systemctl restart postgresql-${POSTGRESQL_VERSION}

# Download and install SonarQube
echo "Installing SonarQube version ${SONARQUBE_VERSION}..."
sudo mkdir -p /sonarqube/
cd /sonarqube/
sudo curl -L -O https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip
wait_for_yum_lock
sudo yum install unzip -y
sudo unzip -o sonarqube-${SONARQUBE_VERSION}.zip -d /opt/
sudo mv /opt/sonarqube-${SONARQUBE_VERSION}/ $INSTALL_DIR

# Create sonar user and set permissions
echo "Creating sonar user and setting permissions..."
sudo groupadd sonar || true
sudo useradd -c "SonarQube - User" -d $INSTALL_DIR -g sonar $SONARQUBE_USER || true
sudo chown -R ${SONARQUBE_USER}:sonar $INSTALL_DIR
sudo chmod -R 755 $INSTALL_DIR

# Create necessary directories
sudo mkdir -p $INSTALL_DIR/data
sudo mkdir -p $INSTALL_DIR/temp
sudo mkdir -p $INSTALL_DIR/logs
sudo chown -R ${SONARQUBE_USER}:sonar $INSTALL_DIR/data
sudo chown -R ${SONARQUBE_USER}:sonar $INSTALL_DIR/temp
sudo chown -R ${SONARQUBE_USER}:sonar $INSTALL_DIR/logs

# Configure SonarQube
echo "Configuring SonarQube..."
sudo tee $INSTALL_DIR/conf/sonar.properties << EOF
sonar.jdbc.username=${SONARQUBE_USER}
sonar.jdbc.password=${SONARQUBE_PASSWORD}
sonar.jdbc.url=jdbc:postgresql://localhost/${SONARQUBE_DB}
sonar.web.host=0.0.0.0
sonar.web.port=${SONARQUBE_PORT}
sonar.path.data=$INSTALL_DIR/data
sonar.path.temp=$INSTALL_DIR/temp
sonar.log.level=DEBUG
sonar.web.javaOpts=-Xmx512m -Xms128m -XX:+HeapDumpOnOutOfMemoryError
sonar.ce.javaOpts=-Xmx512m -Xms128m -XX:+HeapDumpOnOutOfMemoryError
sonar.search.javaOpts=-Xmx512m -Xms512m -XX:+HeapDumpOnOutOfMemoryError
EOF

# Create systemd service file
echo "Creating systemd service file for SonarQube..."
sudo tee /etc/systemd/system/sonarqube.service << EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target postgresql-${POSTGRESQL_VERSION}.service
Wants=postgresql-${POSTGRESQL_VERSION}.service

[Service]
Type=simple
User=${SONARQUBE_USER}
Group=sonar
PermissionsStartOnly=true
ExecStart=$INSTALL_DIR/bin/linux-x86-64/sonar.sh console
StandardOutput=journal
StandardError=journal
LimitNOFILE=131072
LimitNPROC=8192
TimeoutStartSec=5m
Restart=always
SuccessExitStatus=143
Environment=JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}
Environment=SONAR_JAVA_PATH=/usr/lib/jvm/java-${JAVA_VERSION}/bin/java

[Install]
WantedBy=multi-user.target
EOF

# Verify service file creation
if [ ! -f /etc/systemd/system/sonarqube.service ]; then
    echo "Service file creation failed!"
    exit 1
fi

# Start and enable the SonarQube service
echo "Starting SonarQube service..."
sudo systemctl daemon-reload
sudo systemctl enable sonarqube
sudo systemctl start sonarqube

# Wait for service to start
echo "Waiting for SonarQube to start..."
sleep 30

# Verify installation
echo "Verifying SonarQube installation..."
sudo systemctl status sonarqube
curl -f http://localhost:${SONARQUBE_PORT} || echo "SonarQube web interface not responding"

# Get the public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "Installation complete! Access SonarQube at: http://${PUBLIC_IP}:${SONARQUBE_PORT}"
echo "Default credentials: admin/admin"
echo "To check logs, use: sudo journalctl -u sonarqube"