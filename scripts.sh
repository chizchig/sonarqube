#!/bin/bash

# Exit on error
set -e

echo "Starting dynamic SonarQube installation with enhanced error handling..."

# Default configuration variables (can be overridden by environment variables)
SONARQUBE_VERSION=${SONARQUBE_VERSION:-"10.3.0.82913"}
POSTGRESQL_VERSION=${POSTGRESQL_VERSION:-"14"}
JAVA_VERSION=${JAVA_VERSION:-"17"}
SONARQUBE_USER=${SONARQUBE_USER:-"sonar"}
SONARQUBE_PASSWORD=${SONARQUBE_PASSWORD:-"admin123"}
SONARQUBE_DB=${SONARQUBE_DB:-"sonarqube"}
SONARQUBE_PORT=${SONARQUBE_PORT:-"9000"}
NGINX_PORT=${NGINX_PORT:-"80"}
INSTALL_DIR=${INSTALL_DIR:-"/opt/sonarqube"}

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
}

# Backup system configurations
echo "Backing up system configurations..."
sudo cp /etc/sysctl.conf /root/sysctl.conf_backup
sudo cp /etc/security/limits.conf /root/sec_limit.conf_backup

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

# Set up swap space
echo "Setting up swap space..."
if [ ! -f /swapfile ]; then
    SWAP_SIZE=${SWAP_SIZE:-4096}
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# Install Java
echo "Installing Java ${JAVA_VERSION}..."
sudo yum remove java* -y || true
sudo yum install -y java-${JAVA_VERSION}-amazon-corretto
verify_java

# Install PostgreSQL
echo "Installing PostgreSQL ${POSTGRESQL_VERSION}..."
sudo yum install -y postgresql${POSTGRESQL_VERSION} postgresql${POSTGRESQL_VERSION}-server
sudo /usr/bin/postgresql-${POSTGRESQL_VERSION}-setup initdb
sudo systemctl enable postgresql-${POSTGRESQL_VERSION}
sudo systemctl start postgresql-${POSTGRESQL_VERSION}

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
sudo curl -O https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip
sudo yum install unzip -y
sudo unzip -o sonarqube-${SONARQUBE_VERSION}.zip -d /opt/
sudo mv /opt/sonarqube-${SONARQUBE_VERSION}/ $INSTALL_DIR

# Create sonar user and set permissions
sudo groupadd sonar || true
sudo useradd -c "SonarQube - User" -d $INSTALL_DIR -g sonar $SONARQUBE_USER || true
sudo chown -R ${SONARQUBE_USER}:sonar $INSTALL_DIR
sudo chmod -R 755 $INSTALL_DIR

# Configure SonarQube
echo "Configuring SonarQube..."
sudo tee $INSTALL_DIR/conf/sonar.properties << EOF
sonar.jdbc.username=${SONARQUBE_USER}
sonar.jdbc.password=${SONARQUBE_PASSWORD}
sonar.jdbc.url=jdbc:postgresql://localhost/${SONARQUBE_DB}
sonar.web.host=0.0.0.0
sonar.web.port=${SONARQUBE_PORT}
EOF

# Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/sonarqube.service << EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target postgresql-${POSTGRESQL_VERSION}.service
Wants=postgresql-${POSTGRESQL_VERSION}.service

[Service]
Type=simple
User=${SONARQUBE_USER}
Group=sonar
ExecStart=/bin/bash -c "$INSTALL_DIR/bin/linux-x86-64/sonar.sh console"
LimitNOFILE=131072
LimitNPROC=8192
Restart=on-failure
Environment=JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}
Environment=SONAR_JAVA_PATH=/usr/lib/jvm/java-${JAVA_VERSION}/bin/java

[Install]
WantedBy=multi-user.target
EOF

# Install and configure Nginx
echo "Installing and configuring Nginx..."
sudo yum install nginx -y
sudo tee /etc/nginx/conf.d/sonarqube.conf << EOF
server {
    listen ${NGINX_PORT};
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:${SONARQUBE_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Start services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable postgresql-${POSTGRESQL_VERSION}
sudo systemctl start postgresql-${POSTGRESQL_VERSION}
sudo systemctl enable sonarqube
sudo systemctl start sonarqube
sudo systemctl enable nginx
sudo systemctl start nginx

# Verify installation
verify_installation

echo "Installation complete! Access SonarQube at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Default credentials: admin/admin"
