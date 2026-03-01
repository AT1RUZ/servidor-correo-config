#!/bin/bash

# ==============================================================================
# Script de Despliegue y Portabilidad del Servidor de Correo (CUJAE)
# ==============================================================================
# Este script automatiza la instalación de paquetes y el despliegue de
# Este script automatiza la instalación de paquetes y el despliegue de
# configuraciones para Postfix, Dovecot, LDAP, OpenDKIM, SpamAssassin, ClamAV
# Roundcube y Apache.
#
# Uso: sudo ./deploy-mailserver.sh
# ==============================================================================

set -e

# Configuración de Colores
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"

# ------------------------------------------------------------------------------
# Función auxiliar: leer input con valor por defecto
# Uso: prompt_input "Descripción" "VARIABLE" "valor_por_defecto"
# ------------------------------------------------------------------------------
prompt_input() {
    local description="$1"
    local varname="$2"
    local default="$3"
    local input

    echo -en "${CYAN}  ${description} [${default}]: ${NC}"
    read -r input
    # Si el usuario no escribe nada, usar el valor por defecto
    if [ -z "$input" ]; then
        eval "$varname=\"$default\""
    else
        eval "$varname=\"$input\""
    fi
}

# ------------------------------------------------------------------------------
# Función auxiliar: leer password con valor por defecto (oculta la entrada)
# ------------------------------------------------------------------------------
prompt_password() {
    local description="$1"
    local varname="$2"
    local default="$3"
    local input

    echo -en "${CYAN}  ${description} [${default}]: ${NC}"
    read -rs input
    echo ""
    if [ -z "$input" ]; then
        eval "$varname=\"$default\""
    else
        eval "$varname=\"$input\""
    fi
}

# ==============================================================================
echo -e "${BLUE}"
echo "=============================================="
echo "  Despliegue del Servidor de Correo CUJAE    "
echo "=============================================="
echo -e "${NC}"

# 1. Verificación de permisos
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Este script debe ejecutarse con sudo.${NC}"
    exit 1
fi

# ==============================================================================
# CONFIGURACIÓN INTERACTIVA
# Todos los valores tienen defaults. Si se presiona Enter se usa el default.
# ==============================================================================
echo -e "${BLUE}--- Configuración General ---${NC}"
prompt_input  "Hostname del servidor"          MAIL_HOSTNAME     "mail.cujae.local"
prompt_input  "Dominio de correo"              MAIL_DOMAIN       "cujae.local"
prompt_input  "Organización"                   LDAP_ORG          "CUJAE"

echo ""
echo -e "${BLUE}--- Credenciales LDAP ---${NC}"
prompt_password "Password del admin LDAP (cn=admin)"  LDAP_ADMIN_PASS  "admin"

echo ""
echo -e "${BLUE}--- Credenciales MariaDB para Roundcube ---${NC}"
prompt_input    "Nombre de la base de datos"   MYSQL_ROUNDCUBE_DB    "roundcube"
prompt_input    "Usuario de la base de datos"  MYSQL_ROUNDCUBE_USER  "roundcube"
prompt_password "Password del usuario"         MYSQL_ROUNDCUBE_PASS  "roundcube"

echo ""
echo -e "${BLUE}--- Repositorio Git ---${NC}"
prompt_input "URL del repositorio de configuración" GIT_REPO_URL "https://github.com/AT1RUZ/servidor-correo-config.git"



echo ""
echo -e "${BLUE}--- Inicializar usuarios LDAP ---${NC}"
echo -en "${CYAN}  ¿Cargar usuarios iniciales desde ldap_scripts/initial_users.ldif? [s/n] [s]: ${NC}"
read -r INIT_LDAP_INPUT
INIT_LDAP_INPUT="${INIT_LDAP_INPUT:-s}"
if [[ "$INIT_LDAP_INPUT" =~ ^[sS]$ ]]; then
    INITIALIZE_LOCAL_LDAP="true"
else
    INITIALIZE_LOCAL_LDAP="false"
fi

# Resumen antes de continuar
echo ""
echo -e "${BLUE}=============================================="
echo -e "  Resumen de configuración"
echo -e "==============================================${NC}"
echo -e "  Hostname:          ${GREEN}$MAIL_HOSTNAME${NC}"
echo -e "  Dominio:           ${GREEN}$MAIL_DOMAIN${NC}"
echo -e "  Organización:      ${GREEN}$LDAP_ORG${NC}"
echo -e "  LDAP admin pass:   ${GREEN}[configurado]${NC}"
echo -e "  BD Roundcube:      ${GREEN}$MYSQL_ROUNDCUBE_DB${NC}"
echo -e "  Usuario BD:        ${GREEN}$MYSQL_ROUNDCUBE_USER${NC}"
echo -e "  Pass BD:           ${GREEN}[configurado]${NC}"
echo -e "  Repositorio:       ${GREEN}$GIT_REPO_URL${NC}"
echo -e "  Firmas ClamAV:     ${GREEN}Descargar con freshclam (~230 MB)${NC}"
echo -e "  Inicializar LDAP:  ${GREEN}$INITIALIZE_LOCAL_LDAP${NC}"
echo ""
echo -en "${YELLOW}¿Continuar con el despliegue? [s/n] [s]: ${NC}"
read -r CONFIRM
CONFIRM="${CONFIRM:-s}"
if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
    echo -e "${RED}Despliegue cancelado.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}=== Iniciando Despliegue del Servidor de Correo ===${NC}"

# ==============================================================================
# 2. Preparación inicial
# ==============================================================================
echo -e "${GREEN}[1/8] Preparando sistema e instalando herramientas base...${NC}"
apt update -y
apt install -y git debconf-utils openssh-client openssl

# ==============================================================================
# 3. Pre-configuración de Slapd (antes de instalar)
# ==============================================================================
echo -e "${GREEN}[2/8] Pre-configurando LDAP para ${MAIL_DOMAIN}...${NC}"
echo "slapd slapd/no_configuration boolean false"          | debconf-set-selections
echo "slapd slapd/domain string ${MAIL_DOMAIN}"            | debconf-set-selections
echo "slapd slapd/organization string ${LDAP_ORG}"         | debconf-set-selections
echo "slapd slapd/internal_admin_password password ${LDAP_ADMIN_PASS}"        | debconf-set-selections
echo "slapd slapd/internal_admin_password_again password ${LDAP_ADMIN_PASS}"  | debconf-set-selections
echo "slapd slapd/purge_database boolean true"             | debconf-set-selections
echo "slapd slapd/move_old_database boolean true"          | debconf-set-selections
echo "slapd slapd/backend string MDB"                      | debconf-set-selections

# Pre-configuración de Roundcube para MariaDB via dbconfig-common
echo "roundcube-core roundcube/dbconfig-install boolean true"                         | debconf-set-selections
echo "roundcube-core roundcube/database-type select mysql"                            | debconf-set-selections
echo "roundcube-core roundcube/mysql/admin-pass password "                            | debconf-set-selections
echo "roundcube-core roundcube/db/dbname string ${MYSQL_ROUNDCUBE_DB}"                | debconf-set-selections
echo "roundcube-core roundcube/db/app-user string ${MYSQL_ROUNDCUBE_USER}"            | debconf-set-selections
echo "roundcube-core roundcube/mysql/app-pass password ${MYSQL_ROUNDCUBE_PASS}"       | debconf-set-selections
echo "roundcube-core roundcube/mysql/app-pass-confirm password ${MYSQL_ROUNDCUBE_PASS}" | debconf-set-selections

# ==============================================================================
# 4. Creación de Usuario Virtual de Correo (vmail)
# ==============================================================================
if ! getent group vmail > /dev/null; then
    groupadd -g 5000 vmail
fi
if ! getent passwd vmail > /dev/null; then
    useradd -g vmail -u 5000 vmail -d /var/mail -s /usr/sbin/nologin
fi

# ==============================================================================
# 5. Estructura de Buzones
# ==============================================================================
echo -e "${GREEN}[3/8] Preparando estructura de buzones...${NC}"
mkdir -p /var/mail/vhosts/${MAIL_DOMAIN}
chown -R vmail:vmail /var/mail
chmod -R 770 /var/mail

# ==============================================================================
# 6. Verificación / Clonado de Repositorio
# ==============================================================================
REPO_DIR=$(pwd)
if [ ! -d "$REPO_DIR/postfix" ] || [ ! -d "$REPO_DIR/dovecot" ]; then
    TEMP_DIR="/tmp/mailserver_config_$(date +%s)"
    echo -e "${GREEN}Clonando repositorio en $TEMP_DIR...${NC}"
    git clone "$GIT_REPO_URL" "$TEMP_DIR"
    cd "$TEMP_DIR"
    REPO_DIR=$(pwd)
fi

# ==============================================================================
# 7. Instalación de Paquetes
# ==============================================================================
echo -e "${GREEN}[4/8] Instalando paquetes...${NC}"
export DEBIAN_FRONTEND=noninteractive

# MariaDB primero — el instalador de roundcube-mysql se conecta durante el apt install
apt install -y mariadb-server mariadb-client
systemctl start mariadb
systemctl enable mariadb

# Crear BD y usuario ANTES de instalar roundcube
echo -e "${GREEN}Preparando base de datos MariaDB para Roundcube...${NC}"
mysql -u root << SQLEOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_ROUNDCUBE_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_ROUNDCUBE_USER}'@'localhost' IDENTIFIED BY '${MYSQL_ROUNDCUBE_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_ROUNDCUBE_DB}\`.* TO '${MYSQL_ROUNDCUBE_USER}'@'localhost';
FLUSH PRIVILEGES;
SQLEOF

# Resto de paquetes
apt install -y \
    postfix \
    dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-ldap \
    slapd ldap-utils \
    opendkim opendkim-tools \
    spamassassin spamc \
    clamav-daemon clamav-milter clamav-freshclam \
    roundcube roundcube-mysql apache2 libapache2-mod-php \
    swaks mailutils wget curl php-ldap php-imap sqlite3

# ==============================================================================
# FIX LDAP: Reconfigurar slapd con base de datos limpia
# ==============================================================================
echo -e "${GREEN}[5/8] Reconfigurando slapd...${NC}"
systemctl stop slapd || true
rm -rf /var/lib/ldap/* /etc/ldap/slapd.d/*
echo "slapd slapd/no_configuration boolean false"          | debconf-set-selections
echo "slapd slapd/domain string ${MAIL_DOMAIN}"            | debconf-set-selections
echo "slapd slapd/organization string ${LDAP_ORG}"         | debconf-set-selections
echo "slapd slapd/internal_admin_password password ${LDAP_ADMIN_PASS}"        | debconf-set-selections
echo "slapd slapd/internal_admin_password_again password ${LDAP_ADMIN_PASS}"  | debconf-set-selections
echo "slapd slapd/purge_database boolean true"             | debconf-set-selections
echo "slapd slapd/move_old_database boolean true"          | debconf-set-selections
echo "slapd slapd/backend string MDB"                      | debconf-set-selections
dpkg-reconfigure -f noninteractive slapd

systemctl restart slapd
sleep 5

# Verificar y corregir password LDAP si dpkg-reconfigure no lo aplicó bien
echo -e "${GREEN}Verificando credenciales LDAP...${NC}"
LDAP_DC="dc=$(echo $MAIL_DOMAIN | sed 's/\./,dc=/g')"
if ! ldapsearch -x -H ldap://localhost -b "$LDAP_DC" \
    -D "cn=admin,${LDAP_DC}" -w "$LDAP_ADMIN_PASS" > /dev/null 2>&1; then
    echo -e "${YELLOW}Corrigiendo password LDAP via interfaz local...${NC}"
    LDAP_HASH=$(slappasswd -s "$LDAP_ADMIN_PASS")
    ldapmodify -Y EXTERNAL -H ldapi:/// << EOF 2>/dev/null || true
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $LDAP_HASH
EOF
    systemctl restart slapd
    sleep 3
fi

# ==============================================================================
# 8. Firmas de ClamAV
# ==============================================================================
echo -e "${GREEN}[6/8] Descargando firmas de ClamAV (~230 MB, puede tardar varios minutos)...${NC}"
# Detener el servicio freshclam antes de correrlo manualmente,
# de lo contrario el servicio bloquea el log y freshclam falla
systemctl stop clamav-freshclam || true
freshclam || echo -e "${YELLOW}Advertencia: freshclam falló. ClamAV puede no funcionar hasta que las firmas estén disponibles.${NC}"
systemctl start clamav-freshclam || true

# Arrancar ClamAV daemon una vez que las firmas están listas
systemctl start clamav-daemon || true
sleep 10
systemctl restart clamav-milter || true

# ==============================================================================
# 9. Despliegue de Configuraciones
# ==============================================================================
echo -e "${GREEN}[7/8] Desplegando archivos de configuración...${NC}"
mkdir -p /etc/postfix /etc/dovecot/conf.d /etc/opendkim/keys \
         /etc/spamassassin /etc/clamav /etc/roundcube /etc/apache2/sites-available

# --- Postfix ---
[ -d "$REPO_DIR/postfix" ] && cp -rv "$REPO_DIR/postfix"/* /etc/postfix/

# FIX: /etc/mailname requerido por main.cf (myorigin = /etc/mailname)
# Debe contener el DOMINIO (cujae.local), no el hostname (mail.cujae.local),
# para que los correos salgan como usuario@cujae.local y no como usuario@mail.cujae.local
echo "$MAIL_DOMAIN" > /etc/mailname

# FIX: Forzar inet_interfaces=all (Ubuntu instala con loopback-only)
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = all"

# FIX TLS: Generar certificado autofirmado si no existe
if [ ! -f /etc/ssl/certs/mailserver.pem ] || [ ! -f /etc/ssl/private/mailserver.key ]; then
    echo -e "${GREEN}Generando certificado TLS autofirmado...${NC}"
    openssl req -new -x509 -days 3650 -nodes \
        -out /etc/ssl/certs/mailserver.pem \
        -keyout /etc/ssl/private/mailserver.key \
        -subj "/C=CU/ST=LaHabana/L=LaHabana/O=${LDAP_ORG}/CN=${MAIL_HOSTNAME}" \
        2>/dev/null
    chmod 644 /etc/ssl/certs/mailserver.pem
    chmod 640 /etc/ssl/private/mailserver.key
    chown root:ssl-cert /etc/ssl/private/mailserver.key 2>/dev/null || \
        chown root:root /etc/ssl/private/mailserver.key
fi

# --- Dovecot ---
if [ -d "$REPO_DIR/dovecot" ]; then
    [ -f "$REPO_DIR/dovecot/dovecot.conf" ]         && cp -v "$REPO_DIR/dovecot/dovecot.conf" /etc/dovecot/dovecot.conf
    [ -f "$REPO_DIR/dovecot/dovecot-ldap.conf.ext" ] && cp -v "$REPO_DIR/dovecot/dovecot-ldap.conf.ext" /etc/dovecot/dovecot-ldap.conf.ext
    [ -d "$REPO_DIR/dovecot/conf.d" ]               && cp -rv "$REPO_DIR/dovecot/conf.d"/* /etc/dovecot/conf.d/
fi

# --- OpenDKIM ---
if [ -d "$REPO_DIR/opendkim" ]; then
    [ -f "$REPO_DIR/opendkim/opendkim.conf" ] && cp -v "$REPO_DIR/opendkim/opendkim.conf" /etc/opendkim.conf
    [ -f "$REPO_DIR/opendkim/opendkim" ]      && cp -v "$REPO_DIR/opendkim/opendkim" /etc/default/opendkim
    cp -rv "$REPO_DIR/opendkim"/* /etc/opendkim/
fi

# --- Roundcube ---
# Siempre copiamos config.inc.php del repo (contiene username_domain y otras
# configuraciones de la interfaz). La configuración de BD la maneja
# debian-db.php que se genera justo después, por lo que no hay conflicto.
if [ -d "$REPO_DIR/roundcube" ] && [ -f "$REPO_DIR/roundcube/config.inc.php" ]; then
    cp -v "$REPO_DIR/roundcube/config.inc.php" /etc/roundcube/config.inc.php
fi

# Garantizar debian-db.php con los datos correctos
cat > /etc/roundcube/debian-db-roundcube.php << PHPEOF
<?php
## database access settings - generated by deploy-mailserver.sh
\$dbuser='${MYSQL_ROUNDCUBE_USER}';
\$dbpass='${MYSQL_ROUNDCUBE_PASS}';
\$basepath='';
\$dbname='${MYSQL_ROUNDCUBE_DB}';
\$dbserver='localhost';
\$dbport='3306';
\$dbtype='mysql';
PHPEOF
chown root:www-data /etc/roundcube/debian-db-roundcube.php
chmod 640 /etc/roundcube/debian-db-roundcube.php

# Inicializar esquema de BD si las tablas no existen
RC_TABLE_COUNT=$(mysql -u "$MYSQL_ROUNDCUBE_USER" -p"$MYSQL_ROUNDCUBE_PASS" \
    "$MYSQL_ROUNDCUBE_DB" -e "SHOW TABLES;" 2>/dev/null | wc -l)
if [ "$RC_TABLE_COUNT" -lt 5 ]; then
    RC_SCHEMA=$(find /usr/share/roundcube/SQL/ -name "mysql.initial.sql" 2>/dev/null | head -1)
    if [ -n "$RC_SCHEMA" ]; then
        mysql -u "$MYSQL_ROUNDCUBE_USER" -p"$MYSQL_ROUNDCUBE_PASS" \
            "$MYSQL_ROUNDCUBE_DB" < "$RC_SCHEMA" 2>/dev/null \
            && echo -e "${GREEN}Esquema Roundcube inicializado.${NC}" \
            || echo -e "${YELLOW}No se pudo inicializar el esquema (Roundcube lo hará en el primer acceso).${NC}"
    fi
fi

# --- SpamAssassin & ClamAV configs ---
[ -d "$REPO_DIR/spamassassin" ] && cp -rv "$REPO_DIR/spamassassin"/* /etc/spamassassin/
[ -d "$REPO_DIR/clamav" ]       && cp -rv "$REPO_DIR/clamav"/* /etc/clamav/

# --- Apache ---
[ -f "$REPO_DIR/apache/mail.cujae.local.conf" ] && \
    cp -v "$REPO_DIR/apache/mail.cujae.local.conf" /etc/apache2/sites-available/

# Mapeo de aliases de Postfix
postmap /etc/postfix/virtual_aliases || true

# ==============================================================================
# Permisos y activación de servicios
# ==============================================================================
echo -e "${GREEN}[8/8] Ajustando permisos y activando servicios...${NC}"

chown -R opendkim:opendkim /etc/opendkim/
chmod 640 /etc/opendkim/KeyTable /etc/opendkim/SigningTable /etc/opendkim/TrustedHosts || true

# SpamAssassin
if [ -f /etc/default/spamassassin ]; then
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/spamassassin
    sed -i 's/CRON=0/CRON=1/' /etc/default/spamassassin
fi

# Apache
a2enmod rewrite || true
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.3")
a2enmod php${PHP_VER} || true
a2ensite mail.cujae.local.conf || true
a2dissite 000-default.conf || true

# FIX ROUNDCUBE: Detectar path real y crear conf de Apache
if [ -d /usr/share/roundcube/public_html ]; then
    RC_PATH="/usr/share/roundcube/public_html"
elif [ -d /var/lib/roundcube/public_html ]; then
    RC_PATH="/var/lib/roundcube/public_html"
elif [ -d /usr/share/roundcube ]; then
    RC_PATH="/usr/share/roundcube"
else
    RC_PATH="/var/lib/roundcube"
fi

echo -e "${GREEN}Roundcube detectado en: $RC_PATH${NC}"

cat > /etc/apache2/conf-available/roundcube.conf << APACHECONF
Alias /roundcube $RC_PATH

<Directory $RC_PATH>
    Options -FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

<Directory $RC_PATH/config>
    Options -FollowSymLinks
    AllowOverride None
    Require all denied
</Directory>
<Directory $RC_PATH/temp>
    Options -FollowSymLinks
    AllowOverride None
    Require all denied
</Directory>
<Directory $RC_PATH/logs>
    Options -FollowSymLinks
    AllowOverride None
    Require all denied
</Directory>
APACHECONF

a2enconf roundcube || true

# ==============================================================================
# Configuración de Logs del Servidor de Correo
# ==============================================================================
echo -e "${GREEN}Configurando logs del servidor de correo...${NC}"

# Crear directorio y archivos de log
mkdir -p /var/log/mailserver

# Log principal de correo (Postfix + Dovecot + todos los servicios)
touch /var/log/mailserver/mail.log
# Log exclusivo de errores
touch /var/log/mailserver/mail.err
# Log de SMTP (entregas y rechazos)
touch /var/log/mailserver/smtp.log
# Log de autenticación SASL/IMAP
touch /var/log/mailserver/auth.log
# Log de SpamAssassin
touch /var/log/mailserver/spam.log
# Log de ClamAV
touch /var/log/mailserver/clamav.log

# Permisos: syslog escribe, root y el grupo adm pueden leer
chown -R syslog:adm /var/log/mailserver
chmod -R 640 /var/log/mailserver
chmod 750 /var/log/mailserver

# Configurar rsyslog para enrutar los logs de correo al directorio centralizado
cat > /etc/rsyslog.d/50-mailserver.conf << 'RSYSLOGCONF'
# ==============================================================
# Logs centralizados del Servidor de Correo CUJAE
# ==============================================================

# Log general de mail (Postfix, Dovecot, OpenDKIM, etc.)
mail.*                          /var/log/mailserver/mail.log

# Solo errores de mail
mail.err                        /var/log/mailserver/mail.err

# SMTP: entregas y rechazos (Postfix)
if $programname == 'postfix' then /var/log/mailserver/smtp.log

# Autenticación IMAP/SASL (Dovecot)
if $programname == 'dovecot' then /var/log/mailserver/auth.log

# SpamAssassin
if $programname == 'spamd' then /var/log/mailserver/spam.log

# ClamAV
if $programname startswith 'clam' then /var/log/mailserver/clamav.log
RSYSLOGCONF

# Configurar logrotate para rotar los logs semanalmente
cat > /etc/logrotate.d/mailserver << 'LOGROTATECONF'
/var/log/mailserver/*.log /var/log/mailserver/*.err {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 640 syslog adm
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
LOGROTATECONF

# Reiniciar rsyslog para aplicar la nueva configuración
systemctl restart rsyslog

echo -e "${GREEN}Logs configurados en /var/log/mailserver/${NC}"
echo -e "  mail.log   — Log general (todos los servicios)"
echo -e "  mail.err   — Solo errores"
echo -e "  smtp.log   — Postfix (entregas/rechazos)"
echo -e "  auth.log   — Dovecot (autenticación IMAP/SASL)"
echo -e "  spam.log   — SpamAssassin"
echo -e "  clamav.log — ClamAV"

# Firewall
if command -v ufw > /dev/null; then
    ufw allow 25/tcp  || true
    ufw allow 80/tcp  || true
    ufw allow 143/tcp || true
    ufw allow 587/tcp || true
    ufw allow 993/tcp || true
fi

# Inicialización de usuarios LDAP
if [ "$INITIALIZE_LOCAL_LDAP" = "true" ] && [ -f "$REPO_DIR/ldap_scripts/initial_users.ldif" ]; then
    echo -e "${GREEN}Inicializando usuarios en LDAP...${NC}"
    sleep 2
    ldapadd -x -D "cn=admin,${LDAP_DC}" -w "$LDAP_ADMIN_PASS" \
        -f "$REPO_DIR/ldap_scripts/initial_users.ldif" \
        || echo -e "${YELLOW}Aviso: Usuarios ya existentes o falló la conexión LDAP${NC}"
fi

# Reinicio final de servicios
echo -e "${GREEN}Reiniciando servicios y validando puertos...${NC}"
chmod +x "$REPO_DIR/scripts/restart-mailserver.sh"
"$REPO_DIR/scripts/restart-mailserver.sh"

echo ""
echo -e "${BLUE}=== Despliegue Completado Exitosamente ===${NC}"
echo -e "${GREEN}  Roundcube: http://$(hostname -I | awk '{print $1}')/roundcube/${NC}"
echo -e "${GREEN}  LDAP DN:   cn=admin,${LDAP_DC}${NC}"