# Casos de Prueba del Servidor de Correo

Este documento describe los procedimientos exactos para verificar el correcto funcionamiento de las integraciones realizadas en el servidor de correo CUJAE. Se incluyen pruebas tanto desde la consola como desde la interfaz web (Roundcube), indicando la evidencia exacta requerida en los logs del sistema.

---

## 1. Verificación de OpenDKIM (Firma de Correos)

**Objetivo:** Asegurar que los correos salientes se están firmando correctamente utilizando las claves y dominios configurados en OpenDKIM.

### Procedimiento:
1. Iniciar sesión en **Roundcube** con una cuenta local (ej. `estudiante1@cujae.local`).
2. Enviar un correo a otra cuenta interna (ej. `estudiante2@cujae.local`) o externa (si el routing lo permite).
3. **Alternativa por consola:**
   ```bash
   echo "Prueba de DKIM" | s-nail -s "Prueba DKIM" estudiante2@cujae.local
   ```

### Evidencia Requerida en Logs:
Monitorear los logs en tiempo real o buscar en el historial de `postfix/cleanup`:
```bash
sudo journalctl -u postfix -u opendkim -f
```

**Líneas esperadas (Éxito):**
```text
opendkim[PID]: [MessageID]: DKIM-Signature field added (s=mail, d=cujae.local)
postfix/cleanup[PID]: [MessageID]: message-id=<...>
```
*Si falta la línea `DKIM-Signature field added`, significa que OpenDKIM no firmó el mensaje.*

---

## 2. Verificación de Entrega LMTP (Dovecot)

**Objetivo:** Confirmar que Postfix puede entregar los correos entrantes a Dovecot mediante el socket LMTP sin problemas de permisos, y que estos se guardan correctamente en el buzón IMAP.

### Procedimiento:
1. Utilizar **Roundcube** para enviar un correo ordinario entre dos usuarios (ej. de `estudiante1` a `estudiante2`).
2. Ver que el correo llega a la bandeja de entrada del destinatario en Roundcube.

### Evidencia Requerida en Logs:
Monitorear el log de Postfix y Dovecot para rastrear la entrega:
```bash
sudo journalctl -u postfix -u dovecot -f
```

**Líneas esperadas (Éxito):**
```text
postfix/lmtp[PID]: [MessageID]: to=<estudiante2@cujae.local>, relay=mail.cujae.local[private/dovecot-lmtp], delay=..., status=sent (250 2.0.0 <estudiante2@cujae.local> Saved)
dovecot: lmtp(estudiante2@cujae.local): msgid=<...>: saved mail to INBOX
```
*Si observas errores como `Permission denied` conectando al socket `private/dovecot-lmtp`, los permisos en `10-master.conf` son incorrectos.*

---

## 3. Verificación de SpamAssassin (Filtrado de Spam)

**Objetivo:** Garantizar que los correos recibidos pasen por el analizador de SpamAssassin y se clasifiquen correctamente en base a su puntuación.

### Procedimiento:
1. Desde la consola, enviar un correo utilizando la cadena de prueba estándar GTUBE para forzar un falso positivo de SPAM.
   ```bash
   echo "XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X" > /tmp/spamtest.txt
   mail -s "Test de SPAM" estudiante1@cujae.local < /tmp/spamtest.txt
   ```
2. Iniciar sesión en **Roundcube** como `estudiante1` y verificar si el correo fue marcado en el asunto (ej. `[SPAM] Test de SPAM`) o movido a la carpeta de correo no deseado (según las reglas de Sieve de Dovecot, si aplican).
3. Ver las cabeceras del correo en Roundcube (Botón Más -> Mostrar código del mensaje). 
   Deberías ver cabeceras como:
   ```text
   X-Spam-Flag: YES
   X-Spam-Status: Yes, score=1000.0 required=5.0 tests=GTUBE...
   ```

### Evidencia Requerida en Logs:
Monitorear el demonio de SpamAssassin:
```bash
sudo journalctl -u spamd -f
```

**Líneas esperadas (Éxito para SPAM/GTUBE):**
```text
spamd[PID]: spamd: connection from ip6-localhost [::1]...
spamd[PID]: spamd: processing message <...> for debian-spamd:130
spamd[PID]: spamd: identified spam (1000.0/5.0) for debian-spamd:130...
spamd[PID]: spamd: result: Y 1000 - GTUBE...
```

**Líneas esperadas (Éxito para Correo Limpio):**
```text
spamd[PID]: spamd: result: . -0.2 - ALL_TRUSTED...
spamd[PID]: spamd: clean message (-0.2/5.0) for debian-spamd:130...
```

---

## 4. Verificación de ClamAV (Escaneo Antivirus)

**Objetivo:** Verificar que el milter de ClamAV escanea los correos entrantes y bloquea la entrega si detecta un adjunto malicioso.

### Procedimiento:
1. Crear el archivo de prueba estándar EICAR. Es inofensivo pero todos los antivirus lo detectan.
   ```bash
   echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > /tmp/eicar.com
   ```
2. Iniciar sesión en **Roundcube**.
3. Redactar un nuevo correo.
4. Adjuntar el archivo `/tmp/eicar.com` (o crearlo localmente en la PC y adjuntarlo).
5. Oprimir "Enviar". El sistema de Roundcube debería mostrarte un error de envío porque el servidor SMTP rechazará el mensaje.

### Evidencia Requerida en Logs:
Monitorear Postfix y ClamAV-Milter:
```bash
sudo journalctl -u postfix -u clamav-milter -f
```

**Líneas esperadas (Éxito de detección y bloqueo):**
```text
postfix/smtpd[PID]: [MessageID]: reject: END-OF-MESSAGE from localhost[127.0.0.1]: 550 5.7.1 Message rejected by milter: ... infected with Eicar-Signature; from=<...> to=<...>
```
*Esto demuestra que Postfix consultó al milter en el puerto 8892 (clamav-milter) y este, usando `clamd`, identificó la firma `Eicar-Signature`, ordenándole a Postfix que rechace la transacción (error SMTP 550).*
