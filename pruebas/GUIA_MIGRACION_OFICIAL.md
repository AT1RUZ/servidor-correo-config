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

## 4. Redirección de Dominios Antiguos
Usa el archivo `postfix/virtual_aliases` para mapear los dominios legados:
- `@ceis.cujae.edu.cu -> @cujae.edu.cu`
- `@fe.cujae.edu.cu -> @cujae.edu.cu`

## 5. Migración de Buzones con `imapsync`
(Mantenemos el procedimiento anterior de `imapsync` detallado anteriormente).

## 6. Monitoreo y Mantenimiento
1. **Logs**: Revisa regularmente `/var/log/mail.log` y `/var/log/apache2/error.log`.
2. **Backups**: Programa tareas `cron` para respaldar:
   - `/var/vmail` (Buzones)
   - `/etc/` (Configuraciones)
   - Base de datos de Roundcube.
