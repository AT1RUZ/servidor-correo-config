#!/bin/bash

# ==============================================================================
# Script de Despliegue y Portabilidad del Servidor de Correo (CUJAE)
# ==============================================================================
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
prompt_input  "Hostname del servidor"          MAIL_HOSTNAME     "mail.cujae.edu.cu"
prompt_input  "Dominio de correo"              MAIL_DOMAIN       "cujae.edu.cu"
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
    postfix postfix-ldap \
    dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-ldap \
    slapd ldap-utils \
    opendkim opendkim-tools \
    spamassassin spamc \
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
# 8. Antivirus
# ==============================================================================
# El antivirus NO se instala en este script. Será indicado por el equipo de
# sistemas de la CUJAE. Una vez instalado, integrarlo con Postfix así:
#
#   1. En /etc/postfix/main.cf, añadir el socket del milter del antivirus:
#
#      smtpd_milters = inet:127.0.0.1:8891, inet:127.0.0.1:PUERTO_ANTIVIRUS
#      non_smtpd_milters = inet:127.0.0.1:8891, inet:127.0.0.1:PUERTO_ANTIVIRUS
#
#      (8891 es OpenDKIM — no quitarlo)
#      (sustituir PUERTO_ANTIVIRUS por el puerto real del nuevo antivirus)
#
#   2. Reiniciar Postfix:
#      sudo systemctl restart postfix@-.service
#
# Por ahora milter_default_action=accept en main.cf garantiza que los correos
# se entreguen aunque no haya antivirus activo.
echo -e "${YELLOW}[6/8] Antivirus omitido — pendiente de indicación del equipo de sistemas.${NC}"

# ==============================================================================
# 9. Despliegue de Configuraciones
# ==============================================================================
echo -e "${GREEN}[7/8] Desplegando archivos de configuración...${NC}"
mkdir -p /etc/postfix /etc/dovecot/conf.d /etc/opendkim/keys \
         /etc/spamassassin /etc/clamav /etc/roundcube /etc/apache2/sites-available

# --- Postfix ---
[ -d "$REPO_DIR/postfix" ] && cp -rv "$REPO_DIR/postfix"/* /etc/postfix/

# Quitar el milter de ClamAV (8892) de main.cf — el antivirus lo indicará sistemas
# Dejar solo OpenDKIM (8891) activo
sed -i 's|^smtpd_milters = .*|smtpd_milters = inet:127.0.0.1:8891|' /etc/postfix/main.cf
sed -i 's|^non_smtpd_milters = .*|non_smtpd_milters = inet:127.0.0.1:8891|' /etc/postfix/main.cf
# Añadir comentario explicativo sobre cómo integrar el nuevo antivirus
sed -i '/^smtpd_milters/a # ANTIVIRUS: cuando sistemas indique el antivirus, añadir su socket aquí:
# smtpd_milters = inet:127.0.0.1:8891, inet:127.0.0.1:PUERTO_ANTIVIRUS
# non_smtpd_milters = inet:127.0.0.1:8891, inet:127.0.0.1:PUERTO_ANTIVIRUS' /etc/postfix/main.cf

# ------------------------------------------------------------------------------
# Generar ldap-users.cf con los valores del entorno actual.
# search_base apunta a la raíz del árbol (LDAP_DC) para cubrir TODAS las OUs:
#   Area Central, Facultad de Arquitectura, Facultad de Ingeniería Civil,
#   Facultad de Ingeniería Eléctrica, Facultad de Ingeniería Industrial,
#   Facultad de Ingeniería Informática, Facultad de Ingeniería Mecánica,
#   Facultad de Ingeniería Química, Facultad de Ingeniería en Automática
#   y Biomédica, Facultad de Ingeniería en Telecomunicaciones y Electrónica,
#   Instituto Ciencias Básicas, Read_QR_Proyect.
#
# Cuando el equipo de sistemas proporcione la IP del LDAP institucional,
# cambiar server_host y bind_dn en /etc/postfix/ldap-users.cf
# ------------------------------------------------------------------------------
cat > /etc/postfix/ldap-users.cf << LDAPCF
# Generado por deploy-mailserver.sh
# ─────────────────────────────────────────────────────────────────
# PARA MIGRAR AL LDAP INSTITUCIONAL:
# 1. Comentar la línea "server_host = localhost"
# 2. Descomentar y rellenar las tres líneas de abajo
# 3. Ejecutar: sudo systemctl reload postfix
# ─────────────────────────────────────────────────────────────────
# server_host = [IP_LDAP_INSTITUCIONAL]   # ← IP del LDAP de la CUJAE
# bind_dn     = [BIND_DN_INSTITUCIONAL]   # ← ej: cn=readonly,dc=cujae,dc=edu,dc=cu
# bind_pw     = [BIND_PASSWORD_INSTITUCIONAL]
# ─────────────────────────────────────────────────────────────────
# LDAP LOCAL (activo por ahora):
server_host = localhost
search_base = ${LDAP_DC}
scope = sub
query_filter = (&(objectClass=inetOrgPerson)(mail=%s))
result_attribute = mail
bind = yes
bind_dn = cn=admin,${LDAP_DC}
bind_pw = ${LDAP_ADMIN_PASS}
version = 3
LDAPCF

# Parchar dovecot-ldap.conf.ext con los mismos valores del entorno
sed -i "s|^hosts = .*|hosts = localhost|"             /etc/dovecot/dovecot-ldap.conf.ext
sed -i "s|^dn = .*|dn = cn=admin,${LDAP_DC}|"        /etc/dovecot/dovecot-ldap.conf.ext
sed -i "s|^dnpass = .*|dnpass = ${LDAP_ADMIN_PASS}|"  /etc/dovecot/dovecot-ldap.conf.ext
sed -i "s|^base = .*|base = ${LDAP_DC}|"              /etc/dovecot/dovecot-ldap.conf.ext
# scope subtree para buscar en todas las OUs de facultades
grep -q "^scope" /etc/dovecot/dovecot-ldap.conf.ext \
    && sed -i "s|^scope.*|scope = subtree|" /etc/dovecot/dovecot-ldap.conf.ext \
    || echo "scope = subtree" >> /etc/dovecot/dovecot-ldap.conf.ext
# Actualizar rutas de buzones al dominio correcto
sed -i "s|vhosts/[^/]*/|vhosts/${MAIL_DOMAIN}/|g"    /etc/dovecot/dovecot-ldap.conf.ext

# FIX: /etc/mailname requerido por main.cf (myorigin = /etc/mailname)
# Debe contener el DOMINIO (cujae.edu.cu), no el hostname (mail.cujae.edu.cu),
# para que los correos salgan como usuario@cujae.edu.cu y no como usuario@mail.cujae.edu.cu
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
    # Actualizar dominio de usuario al dominio real del despliegue
    sed -i "s|'username_domain'\] = '[^']*'|'username_domain'] = '${MAIL_DOMAIN}'|" /etc/roundcube/config.inc.php
    sed -i "s|'mail_domain'\] = '[^']*'|'mail_domain'] = '${MAIL_DOMAIN}'|"         /etc/roundcube/config.inc.php
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
\$config['db_dsnw'] = \$dbtype . '://' . \$dbuser . ':' . rawurlencode(\$dbpass) . '@' . \$dbserver . '/' . \$dbname;
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

# --- SpamAssassin configs ---
[ -d "$REPO_DIR/spamassassin" ] && cp -rv "$REPO_DIR/spamassassin"/* /etc/spamassassin/
# ClamAV: no se copia configuración — antivirus pendiente de indicación de sistemas

# --- Apache ---
# Copiar config del repo y renombrar con el hostname real del despliegue
if [ -f "$REPO_DIR/apache/mail.cujae.local.conf" ]; then
    cp -v "$REPO_DIR/apache/mail.cujae.local.conf" \
        "/etc/apache2/sites-available/${MAIL_HOSTNAME}.conf"
    # Actualizar ServerName dentro del archivo al hostname real
    sed -i "s|ServerName mail.cujae.local|ServerName ${MAIL_HOSTNAME}|g" \
        "/etc/apache2/sites-available/${MAIL_HOSTNAME}.conf"
fi

# Generar virtual_aliases con las facultades actuales
# Para añadir más facultades, añadir una línea @nueva-facultad.cujae.edu.cu @cujae.edu.cu
cat > /etc/postfix/virtual_aliases << ALIASEOF
# Redirección de dominios de facultad al dominio unificado
# Facultad de Ingeniería Informática (antes @ceis.cujae.edu.cu)
@ceis.cujae.edu.cu    @${MAIL_DOMAIN}
# Facultad de Arquitectura (antes @arq.cujae.edu.cu)
@arq.cujae.edu.cu     @${MAIL_DOMAIN}
# Para añadir más facultades cuando se integren:
# @civil.cujae.edu.cu   @${MAIL_DOMAIN}
# @tesla.cujae.edu.cu   @${MAIL_DOMAIN}
# @ind.cujae.edu.cu     @${MAIL_DOMAIN}
# @mecan.cujae.edu.cu   @${MAIL_DOMAIN}
# @quimica.cujae.edu.cu @${MAIL_DOMAIN}
# @automatica.cujae.edu.cu @${MAIL_DOMAIN}
# @tele.cujae.edu.cu    @${MAIL_DOMAIN}
ALIASEOF

# Actualizar virtual_alias_domains en main.cf con los dominios activos
postconf -e "virtual_alias_domains = ceis.cujae.edu.cu, arq.cujae.edu.cu"
# Para añadir más facultades en el futuro:
# postconf -e "virtual_alias_domains = ceis.cujae.edu.cu, arq.cujae.edu.cu, civil.cujae.edu.cu"

# Actualizar virtual_mailbox_domains al dominio principal real
postconf -e "virtual_mailbox_domains = ${MAIL_DOMAIN}"

postmap /etc/postfix/virtual_aliases || true

# ==============================================================================
# Permisos y activación de servicios
# ==============================================================================
echo -e "${GREEN}[8/8] Ajustando permisos y activando servicios...${NC}"

chown -R opendkim:opendkim /etc/opendkim/
chmod 640 /etc/opendkim/KeyTable /etc/opendkim/SigningTable /etc/opendkim/TrustedHosts || true

# Actualizar dominio en ficheros de OpenDKIM al dominio real del despliegue
sed -i "s|cujae\.local|${MAIL_DOMAIN}|g" /etc/opendkim.conf
sed -i "s|cujae\.local|${MAIL_DOMAIN}|g" /etc/opendkim/KeyTable
sed -i "s|cujae\.local|${MAIL_DOMAIN}|g" /etc/opendkim/SigningTable
sed -i "s|cujae\.local|${MAIL_DOMAIN}|g" /etc/opendkim/TrustedHosts

# SpamAssassin
if [ -f /etc/default/spamassassin ]; then
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/spamassassin
    sed -i 's/CRON=0/CRON=1/' /etc/default/spamassassin
fi

# Apache
a2enmod rewrite || true
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.3")
a2enmod php${PHP_VER} || true
a2ensite "${MAIL_HOSTNAME}.conf" || true
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

# Permisos: syslog escribe, root y el grupo adm pueden leer
chown -R syslog:adm /var/log/mailserver
chmod -R 640 /var/log/mailserver
chmod 750 /var/log/mailserver

# Configurar rsyslog para enrutar los logs de correo al directorio centralizado
cat > /etc/rsyslog.d/50-mailserver.conf << 'RSYSLOGCONF'
# ==============================================================
# Logs centralizados del Servidor de Correo CUJAE
# ==============================================================
# IMPORTANTE: cada bloque escribe en su archivo específico Y
# también deja caer el mensaje al archivo general (mail.log).
# El "& ~" al final de cada bloque evita duplicados en syslog.

# ── Postfix (usa facility mail) ───────────────────────────────
if $programname startswith 'postfix' then {
    action(type="omfile" file="/var/log/mailserver/smtp.log")
    action(type="omfile" file="/var/log/mailserver/mail.log")
    stop
}

# ── Dovecot (usa facility mail) ───────────────────────────────
if $programname == 'dovecot' then {
    action(type="omfile" file="/var/log/mailserver/auth.log")
    action(type="omfile" file="/var/log/mailserver/mail.log")
    stop
}

# ── OpenDKIM (usa facility mail o daemon según versión) ───────
if $programname == 'opendkim' then {
    action(type="omfile" file="/var/log/mailserver/mail.log")
    stop
}
# OpenDKIM a veces usa facility daemon en lugar de mail
if $syslogfacility-text == 'daemon' and $programname == 'opendkim' then {
    action(type="omfile" file="/var/log/mailserver/mail.log")
    stop
}

# ── SpamAssassin (spamd, usa facility mail) ───────────────────
if $programname == 'spamd' then {
    action(type="omfile" file="/var/log/mailserver/spam.log")
    action(type="omfile" file="/var/log/mailserver/mail.log")
    stop
}

# ── Errores de cualquier servicio de mail ─────────────────────
mail.err                        /var/log/mailserver/mail.err
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

# Firewall
if command -v ufw > /dev/null; then
    ufw allow 25/tcp  || true
    ufw allow 80/tcp  || true
    ufw allow 143/tcp || true
    ufw allow 587/tcp || true
    ufw allow 993/tcp || true
fi

# Inicialización de usuarios LDAP
if [ "$INITIALIZE_LOCAL_LDAP" = "true" ]; then
    echo -e "${GREEN}Inicializando usuarios en LDAP...${NC}"
    sleep 2
    # Generar LDIF dinámicamente con el DC correcto y usuarios de prueba reales:
    # 2 usuarios de Informática (@ceis.cujae.edu.cu) y 2 de Arquitectura (@arq.cujae.edu.cu)
    # Estos reflejan cómo están los usuarios en el LDAP institucional actual.
    # En el futuro, cuando se unifique el dominio, los usuarios tendrán @cujae.edu.cu.
    LDIF_TMP=$(mktemp)
    cat > "$LDIF_TMP" << LDIFEOF
dn: ou=people,${LDAP_DC}
objectClass: organizationalUnit
ou: people

dn: uid=estudiante1,ou=people,${LDAP_DC}
objectClass: inetOrgPerson
uid: estudiante1
cn: Estudiante1 CEIS
sn: CEIS
userPassword: {SSHA}zardPE6ATWxjk34bJFzQOXj7+vri6XM+
mail: estudiante1@ceis.cujae.edu.cu

dn: uid=estudiante2,ou=people,${LDAP_DC}
objectClass: inetOrgPerson
uid: estudiante2
cn: Estudiante2 CEIS
sn: CEIS
userPassword: {SSHA}zardPE6ATWxjk34bJFzQOXj7+vri6XM+
mail: estudiante2@ceis.cujae.edu.cu

dn: uid=estudiante3,ou=people,${LDAP_DC}
objectClass: inetOrgPerson
uid: estudiante3
cn: Estudiante3 Arq
sn: ARQ
userPassword: {SSHA}zardPE6ATWxjk34bJFzQOXj7+vri6XM+
mail: estudiante3@arq.cujae.edu.cu

dn: uid=estudiante4,ou=people,${LDAP_DC}
objectClass: inetOrgPerson
uid: estudiante4
cn: Estudiante4 Arq
sn: ARQ
userPassword: {SSHA}zardPE6ATWxjk34bJFzQOXj7+vri6XM+
mail: estudiante4@arq.cujae.edu.cu
LDIFEOF
    ldapadd -x -D "cn=admin,${LDAP_DC}" -w "$LDAP_ADMIN_PASS"         -f "$LDIF_TMP"         || echo -e "${YELLOW}Aviso: Usuarios ya existentes o falló la conexión LDAP${NC}"
    rm -f "$LDIF_TMP"
fi

# Reinicio final de servicios
echo -e "${GREEN}Reiniciando servicios y validando puertos...${NC}"
chmod +x "$REPO_DIR/scripts/restart-mailserver.sh"
"$REPO_DIR/scripts/restart-mailserver.sh"

echo ""
echo -e "${BLUE}=== Despliegue Completado Exitosamente ===${NC}"
echo -e "${GREEN}  Roundcube: http://$(hostname -I | awk '{print $1}')/roundcube/${NC}"
echo -e "${GREEN}  LDAP DN:   cn=admin,${LDAP_DC}${NC}"