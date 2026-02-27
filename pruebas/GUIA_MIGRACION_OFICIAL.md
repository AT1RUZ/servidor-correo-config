# Guía Completa de Migración a Producción (CUJAE)

Esta guía detalla el procedimiento integral para llevar el servidor de pruebas a la infraestructura oficial de la CUJAE.

## 1. Preparación de la Infraestructura
### Seguridad y Red (Firewall)
Asegúrate de que el centro de datos abra los siguientes puertos hacia el servidor:
- **SMTP/S**: 25, 465, 587
- **IMAP/S**: 143, 993
- **HTTP/S**: 80, 443 (para Roundcube)
- **LDAP**: 389 (si la sincronización es externa)

### Certificados SSL/TLS (CRÍTICO)
No uses certificados auto-firmados en producción.
1. Solicita certificados válidos a la autoridad de certificación institucional o usa Let's Encrypt (`certbot`).
2. Actualiza las rutas en Postfix (`main.cf`) y Dovecot (`10-ssl.conf`):
   ```text
   smtpd_tls_cert_file=/etc/ssl/certs/oficial_cujae.pem
   smtpd_tls_key_file=/etc/ssl/private/oficial_cujae.key
   ```

## 2. Configuración de DNS Institucional
El administrador del DNS de la CUJAE debe configurar los siguientes registros para `cujae.edu.cu`:

| Tipo | Host | Valor | Descripción |
| :--- | :--- | :--- | :--- |
| **A** | `mail` | `IP.DEL.NUEVO.SRV` | Punto de entrada |
| **MX** | `@` | `10 mail.cujae.edu.cu` | Servidor principal |
| **TXT** | `@` | `v=spf1 ip4:IP_SRV -all` | Registro SPF |
| **TXT** | `default._domainkey` | `v=DKIM1; k=rsa; p=...` | Llave pública DKIM |
| **TXT** | `_dmarc` | `v=DMARC1; p=quarantine` | Política DMARC |

## 3. Integración con LDAP Institucional
Si vas a usar el servidor LDAP central de la CUJAE en lugar del local:
1. Modifica `/etc/postfix/ldap-users.cf` y `/etc/dovecot/dovecot-ldap.conf.ext`.
2. Actualiza `server_host`, `search_base`, `bind_dn` y `password` con los datos del servidor central.

## 4. Despliegue en Contenedores (LXC / VM)
El script `deploy-mailserver.sh` está diseñado para sistemas basados en Debian/Ubuntu con `systemd`.
- **Contenedores LXC**: Funcionará perfectamente si el contenedor tiene `systemd` habilitado. Es ideal para el servidor "temporal" que mencionas.
- **Docker**: No se recomienda ejecutar este script dentro de un Dockerfile estándar, ya que Postfix y Dovecot esperan un gestor de servicios real. Para Docker, se requeriría una orquestación diferente.

## 5. Integración con la Red Interna de la CUJAE
Para que el servidor sea accesible desde cualquier PC de la universidad:
1. **Acceso Web (Roundcube)**: En el DNS institucional (o en los `hosts` de las PCs clientes), debe existir un registro que apunte `mail.cujae.edu.cu` a la IP interna del contenedor.
2. **Conexión al LDAP Institucional**: 
   Si el LDAP está en la misma red interna, solo necesitas actualizar la IP en:
   - `postfix/ldap-users.cf` -> `server_host = IP_LDAP_INSTITUCIONAL`
   - `dovecot/dovecot-ldap.conf.ext` -> `hosts = IP_LDAP_INSTITUCIONAL`
   Asegúrate de que no haya firewalls bloqueando el puerto 389 entre el contenedor de correo y el LDAP.

## 6. Redirección de Dominios Antiguos
Usa el archivo `postfix/virtual_aliases` para mapear los dominios legados:
- `@ceis.cujae.edu.cu -> @cujae.edu.cu`
- `@tele.cujae.edu.cu -> @cujae.edu.cu`

## 7. Sustitución de Dominio (Paso Previo al Despliegue)
El repositorio actual está configurado para `cujae.local`. Antes de ejecutar `deploy-mailserver.sh` en el servidor oficial, realiza un reemplazo masivo:
```bash
grep -rl "cujae.local" . | xargs sed -i 's/cujae.local/cujae.edu.cu/g'
```
*Nota: Revisa también los nombres de los archivos en `apache/` y `postfix/`.*

## 6. Configuraciones Avanzadas (Para un Correo de Calidad)
### Cuotas de Disco (Dovecot Quota)
Para evitar que un usuario llene el disco del servidor:
1. Habilita el plugin `quota` en `10-mail.conf` y `20-imap.conf`.
2. Define el límite en `90-quota.conf` (ej. `vmail_quota = 2G`).

### Filtros Sieve (Pigeonhole)
Permite a los usuarios crear reglas de filtrado (ej. "mover a carpeta Facturas"):
1. Instala `dovecot-sieve dovecot-managesieved`.
2. Habilita el protocolo `sieve` en `10-master.conf` y configura el puerto 4190.

### Autoconfiguración (Thunderbird/Outlook)
Para que los usuarios no tengan que escribir puertos y servidores:
1. Crea registros DNS CNAME: `autoconfig.cujae.edu.cu` y `autodiscover.cujae.edu.cu`.
2. Configura un VirtualHost en Apache que sirva los archivos XML de configuración automática.

## 7. Migración de Buzones con `imapsync`
(Procedimiento incremental detallado anteriormente).

## 8. Monitoreo y Mantenimiento
### Logs Centralizados (Syslog Remoto)
Para enviar los logs de Postfix, Dovecot y el sistema a un servidor central de la CUJAE (vía `rsyslog`):
1. Edita el archivo `/etc/rsyslog.d/50-remote.conf` (o crea uno nuevo):
   ```text
   # Enviar todos los logs vía UDP al servidor central
   *.* @IP_SERVIDOR_LOGS:514

   # O enviar solo los logs de correo vía TCP (más confiable)
   mail.* @@IP_SERVIDOR_LOGS:514
   ```
2. Reinicia el servicio: `sudo systemctl restart rsyslog`.

### Seguridad
Instala `fail2ban` para proteger contra ataques de fuerza bruta en el puerto 25 y 993.

### Backups
Respalda diariamente `/var/vmail` y la configuración de LDAP.
