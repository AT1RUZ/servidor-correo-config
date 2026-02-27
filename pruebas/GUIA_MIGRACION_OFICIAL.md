# Guía de Migración Oficial del Servidor de Correo (CUJAE)

Esta guía detalla el procedimiento para migrar los servicios de correo desde los servidores antiguos de las facultades al nuevo sistema centralizado.

## 1. Estrategia de Dominios y Redirección
Para asegurar la continuidad, el nuevo servidor aceptará correos de los dominios antiguos y los entregará en el nuevo buzón único (`usuario@cujae.edu.cu`).

### Configuración de Postfix (Aliases)
En el servidor nuevo, se ha configurado un mapa de alias virtuales:
- **Dominios Soportados**: `ceis.cujae.edu.cu`, `tele.cujae.edu.cu`, etc.
- **Acción**: Todo correo a `@dominio-viejo` se reescribe a `@cujae.edu.cu`.

Archivo: `/etc/postfix/virtual_aliases`
```text
@ceis.cujae.edu.cu    @cujae.edu.cu
@tele.cujae.edu.cu    @cujae.edu.cu
```

## 2. Migración de Buzones con `imapsync`
`imapsync` es la herramienta recomendada para transferir correos entre servidores IMAP de forma incremental.

### Instalación
```bash
sudo apt install imapsync
```

### Script de Migración Masiva
Se debe ejecutar un ciclo por cada usuario. Ejemplo para un usuario:
```bash
imapsync --host1 correo-viejo.cujae.edu.cu --user1 cedtorres --pass1 "pass_vieja" \
         --host2 mail.cujae.edu.cu --user2 cedtorres@cujae.edu.cu --pass2 "pass_nueva" \
         --noauthmd5 --ssl1 --ssl2
```

### Casos Especiales (Facultades sin servidor activo)
1. **Con Copia Vieja (Backup)**:
   - Si tienes los archivos Maildir/Mbox, se pueden copiar directamente a `/var/vmail/cujae.local/usuario/` y ejecutar `doveadm index -u usuario@cujae.edu.cu *`.
2. **Sin nada**:
   - Solo se crea el usuario en el LDAP y el buzón empezará vacío.

## 3. Pasos del Día de la Migración (Cutover)
1. **Reducir TTL**: 24 horas antes, reducir el TTL en el DNS institucional.
2. **Sincronización Previa**: Ejecutar `imapsync` una semana antes para copiar el grueso de los datos.
3. **Cambio de DNS**: Apuntar los registros MX a la nueva IP.
4. **Sincronización Final**: Volver a ejecutar `imapsync` para copiar los correos que llegaron en el último minuto.
5. **Apagar servidores viejos**.

---
> [!IMPORTANT]
> Asegúrate de que los nombres de usuario en el nuevo LDAP coincidan exactamente con los antiguos para facilitar el mapeo automático en `imapsync`.
