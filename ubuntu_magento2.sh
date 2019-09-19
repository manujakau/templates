#!/bin/bash
MG2_MYSQL_DB_ROOT_PASSWORD=""
MG2_DB_NAME=""
MG2_DB_USER_NAME=""
MG2_DB_PASSWORD=""

MG2_ACC_PUBLIC_KEY=""
MG2_ACC_PRIVATE_KEY=""

ADMIN_EMAIL=""

MG2_ADMIN_USER_NAME=""
MG2_ADMIN_PASSWORD=""

sudo apt update -y
sudo apt install -y apache2 \
                    unzip

sudo systemctl stop apache2.service
sudo systemctl start apache2.service
sudo systemctl enable apache2.service

DEBIAN_FRONTEND=noninteractive
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password ${MG2_MYSQL_DB_ROOT_PASSWORD}"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${MG2_MYSQL_DB_ROOT_PASSWORD}"
sudo apt install -y mysql-server mysql-client

sudo systemctl stop mysql.service
sudo systemctl start mysql.service
sudo systemctl enable mysql.service

sudo apt-get install software-properties-common -y
sudo add-apt-repository ppa:ondrej/php --yes
sudo apt update -y

sudo apt install -y php7.1 libapache2-mod-php7.1 php7.1-common php7.1-gmp php7.1-curl php7.1-soap php7.1-bcmath php7.1-intl php7.1-mbstring \
php7.1-xmlrpc php7.1-mcrypt php7.1-mysql php7.1-gd php7.1-xml php7.1-cli php7.1-zip

sudo apt-get install -y python-pip python-dev build-essential
sudo -H pip install pip --upgrade
sudo -H pip install setuptools --upgrade
sudo -H pip install pyopenssl ndg-httpsclient pyasn1
sudo -H pip install passlib
sudo apt-get update -y
sudo -H pip install ansible==2.3.3.0

cd ~
sudo touch magentophp.yml
cat <<EOF | sudo tee ./magentophp.yml
- hosts: 127.0.0.1
  connection: local
  become: yes

  tasks:
  - name: install python 2
    raw: test -e /usr/bin/python || (apt -y update && apt install -y python-minimal)

  - name: Tag Open
    lineinfile:
      path: /etc/php/7.1/apache2/php.ini
      regexp: 'short_open_tag = Off'
      line: 'short_open_tag = On'

  - name: Memory Limit
    lineinfile:
      path: /etc/php/7.1/apache2/php.ini
      regexp: 'memory_limit = 128M'
      line: 'memory_limit = 256M'

  - name: MAX file Upload
    lineinfile:
      path: /etc/php/7.1/apache2/php.ini
      regexp: 'upload_max_filesize = 2M'
      line: 'upload_max_filesize = 100M'

  - name: Execution time
    lineinfile:
      path: /etc/php/7.1/apache2/php.ini
      regexp: 'max_execution_time = 30'
      line: 'max_execution_time = 360'

  - name: output-compression-cli
    lineinfile:
      path: /etc/php/7.1/cli/php.ini
      regexp: ';date.timezone ='
      line: 'date.timezone = Europe/Tallinn'
EOF

sudo mkdir -p "/etc/ansible/" && sudo touch "/etc/ansible/hosts"
cat <<EOF | sudo tee /etc/ansible/hosts
[local]
localhost ansible_connection=local
EOF

sudo ansible-playbook magentophp.yml

sudo systemctl restart apache2.service

mysql -u root -p${MG2_MYSQL_DB_ROOT_PASSWORD} -e "create database ${MG2_DB_NAME};
create user ${MG2_DB_USER_NAME}@localhost identified by '${MG2_DB_PASSWORD}';
grant all privileges on ${MG2_DB_NAME}.* to ${MG2_DB_USER_NAME}@localhost identified by '${MG2_DB_PASSWORD}';
flush privileges;"

sudo apt install -y curl git
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

cd /var/www/html
#magento_account_public_key=
#magento_account_private_key=
composer config --global http-basic.repo.magento.com ${MG2_ACC_PUBLIC_KEY} ${MG2_ACC_PRIVATE_KEY}
sudo composer create-project --repository=https://repo.magento.com/ magento/project-community-edition magento2

ip=$(ip -o -4  address show  | awk ' NR==2 { gsub(/\/.*/, "", $4); print $4 } ')
#email=noreply@manujak.com

cd /var/www/html/magento2
sudo bin/magento setup:install --base-url=http://$ip/ --db-host=localhost --db-name=${MG2_DB_NAME} --db-user=${MG2_DB_USER_NAME} \
--db-password=${MG2_DB_PASSWORD} --admin-firstname=Admin --admin-lastname=User --admin-email=${ADMIN_EMAIL} \
--admin-user=${MG2_ADMIN_USER_NAME} --admin-password=${MG2_ADMIN_PASSWORD} --language=en_US --currency=USD --timezone=Europe/Tallinn --use-rewrites=1

sudo chown -R www-data:www-data /var/www/html/magento2/
sudo chmod -R 755 /var/www/html/magento2/

cat <<EOF | sudo tee /etc/apache2/sites-available/magento2.conf
<VirtualHost *:80>
     ServerAdmin email
     DocumentRoot /var/www/html/magento2/
     ServerName IP
     ServerAlias http://IP/

     <Directory /var/www/html/magento2/>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Order allow,deny
        allow from all
     </Directory>

     ErrorLog ${APACHE_LOG_DIR}/error.log
     CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

sudo sed -i "s/email/${ADMIN_EMAIL}/g" /etc/apache2/sites-available/magento2.conf
sudo sed -i "s/IP/$ip/g" /etc/apache2/sites-available/magento2.conf

sudo a2ensite magento2.conf
sudo a2enmod rewrite
sudo systemctl restart apache2.service

cd ~
sudo rm -rf magentophp.yml
sudo rm -rf /etc/ansible/
sudo pip uninstall ansible==2.3.3.0 -y

cd /var/www/html/magento2
php bin/magento info:adminuri
