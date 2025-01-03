#!/bin/bash

# Exit on error
set -e

echo "Starting SonarQube installation with enhanced error handling..."

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
sudo tee /etc/security/limits.d/99-sonarqube.conf << EOF
sonarqube   -   nofile   131072
sonarqube   -   nproc    8192
* soft nofile 131072
* hard nofile 131072
* soft nproc 8192
* hard nproc 8192
EOF

# Set up swap space
echo "Setting up swap space..."
if [ ! -f /swapfile ]; then
    sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# Install Java 17
echo "Installing Java 17..."
sudo yum remove java* -y || true
sudo yum install -y java-17-amazon-corretto
verify_java

# Install PostgreSQL 14
echo "Installing PostgreSQL..."
sudo yum install -y postgresql14 postgresql14-server
sudo /usr/bin/postgresql-14-setup initdb
sudo systemctl enable postgresql-14
sudo systemctl start postgresql-14

# Configure PostgreSQL
echo "Configuring PostgreSQL..."
sudo -u postgres psql << EOF
CREATE USER sonar WITH ENCRYPTED PASSWORD 'admin123';
CREATE DATABASE sonarqube OWNER sonar;
GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonar;
\q
EOF

# Configure PostgreSQL authentication
sudo sed -i 's/peer/trust/g' /var/lib/pgsql/14/data/pg_hba.conf
sudo sed -i 's/ident/md5/g' /var/lib/pgsql/14/data/pg_hba.conf
sudo systemctl restart postgresql-14

# Download and install SonarQube
echo "Installing SonarQube..."
sudo mkdir -p /sonarqube/
cd /sonarqube/
sudo curl -O https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-10.3.0.82913.zip
sudo yum install unzip -y
sudo unzip -o sonarqube-10.3.0.82913.zip -d /opt/
sudo mv /opt/sonarqube-10.3.0.82913/ /opt/sonarqube

# Create sonar user and set permissions
sudo groupadd sonar || true
sudo useradd -c "SonarQube - User" -d /opt/sonarqube/ -g sonar sonar || true
sudo chown -R sonar:sonar /opt/sonarqube/
sudo chmod -R 755 /opt/sonarqube/

# Configure SonarQube
sudo tee /opt/sonarqube/conf/sonar.properties << EOF
sonar.jdbc.username=sonar
sonar.jdbc.password=admin123
sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube
sonar.web.host=0.0.0.0
sonar.web.port=9000
sonar.web.javaAdditionalOpts=-server
sonar.web.javaOpts=-Xmx2048m -Xms1024m -XX:+HeapDumpOnOutOfMemoryError
sonar.ce.javaOpts=-Xmx2048m -Xms1024m -XX:+HeapDumpOnOutOfMemoryError
sonar.search.javaOpts=-Xmx2048m -Xms2048m -XX:+HeapDumpOnOutOfMemoryError
sonar.log.level=DEBUG
sonar.path.logs=/opt/sonarqube/logs
sonar.path.data=/opt/sonarqube/data
sonar.path.temp=/opt/sonarqube/temp
EOF

# Create systemd service
sudo tee /etc/systemd/system/sonarqube.service << EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target postgresql-14.service
Wants=postgresql-14.service

[Service]
Type=simple
User=sonar
Group=sonar
PermissionsStartOnly=true
ExecStart=/bin/bash -c "/opt/sonarqube/bin/linux-x86-64/sonar.sh console"
StandardOutput=journal
StandardError=journal
LimitNOFILE=131072
LimitNPROC=8192
TimeoutStartSec=600
Restart=on-failure
RestartSec=30
Environment=JAVA_HOME=/usr/lib/jvm/java-17
Environment=SONAR_JAVA_PATH=/usr/lib/jvm/java-17/bin/java
Environment=PATH=/usr/lib/jvm/java-17/bin:${PATH}

[Install]
WantedBy=multi-user.target
EOF

# Install and configure Nginx
echo "Installing and configuring Nginx..."
sudo yum install nginx -y
sudo tee /etc/nginx/conf.d/sonarqube.conf << EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
}
EOF

# Create directories and set permissions
sudo mkdir -p /opt/sonarqube/data
sudo mkdir -p /opt/sonarqube/temp
sudo mkdir -p /opt/sonarqube/logs
sudo chown -R sonar:sonar /opt/sonarqube/data
sudo chown -R sonar:sonar /opt/sonarqube/temp
sudo chown -R sonar:sonar /opt/sonarqube/logs
sudo chmod -R 755 /opt/sonarqube/data
sudo chmod -R 755 /opt/sonarqube/temp
sudo chmod -R 755 /opt/sonarqube/logs

# Start services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable postgresql-14
sudo systemctl start postgresql-14
sudo systemctl enable sonarqube
sudo systemctl start sonarqube
sudo systemctl enable nginx
sudo systemctl start nginx

# Create log viewing script
sudo tee /usr/local/bin/sonar-logs << EOF
#!/bin/bash
echo "=== SonarQube Logs ==="
sudo journalctl -u sonarqube -f
echo "=== Database Logs ==="
sudo tail -f /var/lib/pgsql/14/data/log/postgresql-*.log
echo "=== Nginx Logs ==="
sudo tail -f /var/log/nginx/error.log
EOF
sudo chmod +x /usr/local/bin/sonar-logs

# Function to verify installation
verify_installation() {
    echo "Verifying installation..."
    check_system_resources
    verify_java
    sudo systemctl status postgresql-14
    sudo systemctl status sonarqube
    sudo systemctl status nginx
    curl -I http://localhost:9000
}

# Run verification
verify_installation

echo "Installation complete! Please wait a few minutes for SonarQube to initialize."
echo "You can access SonarQube at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Default credentials: admin/admin"
echo "To view logs, run: sonar-logs"
echo "To check service status: sudo systemctl status sonarqube"