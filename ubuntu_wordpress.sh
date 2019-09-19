#!/bin/bash
OS=$(grep -e '^ID=' /etc/os-release | cut -d "=" -f 2 | tr -d '"')
WP_MYSQL_DB_NAME=""
WP_MYSQL_DB_USER_NAME=""
WP_MYSQL_DB_USER_PASSWORD=""
if [ "${OS}" == "ubuntu" ]; then

sudo apt-get update -y
sudo apt install software-properties-common -y
sudo add-apt-repository ppa:ondrej/php --yes
sudo apt-get update -y
#sudo apt-get install -y aptitude
sudo apt-get install -y python-pip \
                        python-dev \
                        libffi-dev \
                        libssl-dev
#sudo apt-get install sshpass -y
sudo -H pip install pip --upgrade
sudo -H pip install setuptools --upgrade
sudo -H pip install pyopenssl ndg-httpsclient pyasn1
sudo -H pip install passlib
sudo -H pip install ansible==2.3.3.0

cd ~
sudo touch wordpress.yml
cat <<EOF | sudo tee ./wordpress.yml
- hosts: 127.0.0.1
  connection: local
  become: yes

  tasks:
  - name: install python 2
    raw: test -e /usr/bin/python || (apt -y update && apt install -y python-minimal)

- hosts: local

  roles:
    - server
    - php
    - mysql
    - wordpress
EOF

sudo mkdir roles
cd roles
sudo ansible-galaxy init server
sudo ansible-galaxy init php
sudo ansible-galaxy init mysql
sudo ansible-galaxy init wordpress
cd ~

sudo mkdir -p "/etc/ansible/" && sudo touch "/etc/ansible/hosts"
cat <<EOF | sudo tee /etc/ansible/hosts
[local]
localhost ansible_connection=local
EOF

#sudo mkdir -p "./roles/server/tasks/" &&
#sudo touch "./roles/server/tasks/main.yml"
cat <<EOF | sudo tee ./roles/server/tasks/main.yml
---
- name: Update apt cache
  apt: update_cache=yes cache_valid_time=3600
  become: yes

- name: Install required software
  apt: name={{ item }} state=present
  become: yes
  with_items:
    - apache2
    - mysql-server
    - php7.2-mysql
    - php7.2
    - libapache2-mod-php7.2
    - python-mysqldb
EOF

#sudo mkdir -p "./roles/php/tasks/" &&
#sudo touch "./roles/php/tasks/main.yml"
cat <<EOF | sudo tee ./roles/php/tasks/main.yml
---
- name: Install php extensions
  apt: name={{ item }} state=present
  become: yes
  with_items:
    - php7.2-gd
    - php7.2-ssh2
EOF

#sudo mkdir -p "./roles/mysql/defaults/" &&
#sudo touch "./roles/mysql/defaults/main.yml"
{   echo "---";
    echo "wp_mysql_db: ${WP_MYSQL_DB_NAME}";
    echo "wp_mysql_user: ${WP_MYSQL_DB_USER_NAME}";
    echo "wp_mysql_password: ${WP_MYSQL_DB_USER_PASSWORD}";
    echo "wp_db_host: localhost";
} >> ./roles/mysql/defaults/main.yml

#sudo mkdir -p "./roles/mysql/tasks/" &&
#sudo touch "./roles/mysql/tasks/main.yml"
cat <<EOF | sudo tee ./roles/mysql/tasks/main.yml
---
- name: Create mysql database
  mysql_db: name={{ wp_mysql_db }} state=present
  become: yes

- name: Create mysql user
  mysql_user:
    name={{ wp_mysql_user }}
    password={{ wp_mysql_password }}
    priv=*.*:ALL
  become: yes
EOF

#sudo mkdir -p "./roles/wordpress/tasks/" &&
#sudo touch "./roles/wordpress/tasks/main.yml"
cat <<EOF | sudo tee ./roles/wordpress/tasks/main.yml
---
- name: Download WordPress
  get_url:
    url=https://wordpress.org/latest.tar.gz
    dest=/tmp/wordpress.tar.gz
    validate_certs=no

- name: Extract WordPress
  unarchive: src=/tmp/wordpress.tar.gz dest=/var/www/ copy=no
  become: yes

- name: Update default Apache site
  become: yes
  lineinfile:
    dest=/etc/apache2/sites-enabled/000-default.conf
    regexp="(.)+DocumentRoot /var/www/html"
    line="DocumentRoot /var/www/wordpress"
  notify:
    - restart apache

- name: Copy sample config file
  command: mv /var/www/wordpress/wp-config-sample.php /var/www/wordpress/wp-config.php creates=/var/www/wordpress/wp-config.php
  become: yes

- name: Update WordPress config file - DataBase
  become: yes
  replace:
    path: /var/www/wordpress/wp-config.php
    regexp: 'database_name_here'
    replace: "{{wp_mysql_db}}"
- name: Update WordPress config file - User
  become: yes
  replace:
    path: /var/www/wordpress/wp-config.php
    regexp: 'username_here'
    replace: "{{wp_mysql_user}}"
- name: Update WordPress config file - PassWord
  become: yes
  replace:
    path: /var/www/wordpress/wp-config.php
    regexp: 'password_here'
    replace: "{{wp_mysql_password}}"
- name: Update WordPress config file - Host
  become: yes
  replace:
    path: /var/www/wordpress/wp-config.php
    regexp: 'localhost'
    replace: "{{wp_db_host}}"
EOF

#sudo mkdir -p "./roles/wordpress/handlers/" &&
#sudo touch "./roles/wordpress/handlers/main.yml"
cat <<EOF | sudo tee ./roles/wordpress/handlers/main.yml
---
- name: restart apache
  service: name=apache2 state=restarted
  become: yes
EOF
echo ""
echo "Running Ansible Build."
cd ~
sudo ansible-playbook wordpress.yml
echo ""
sleep 5
cd ~
sudo rm -rf ./wordpress.yml
sudo rm -rf ./roles/
sudo rm -rf ./etc/ansible/
sudo pip uninstall ansible==2.3.3.0 -y
echo "WordPress Installation completed"
else
    echo "WordPress Installation not completed due to Incompatible OS"
fi
