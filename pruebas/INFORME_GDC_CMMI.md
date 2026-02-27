# Informe de Gestión de Configuración (GDC) - CMMI
**Proyecto:** Servidor de Correo Institucional CUJAE
**Fecha de Auditoría:** 27 de febrero de 2026
**Responsable de GDC:** Diego

---

## 1. Introducción
Este informe documenta la implementación y cumplimiento de las políticas de Gestión de Configuración siguiendo los lineamientos de CMMI. El objetivo es asegurar la integridad de los productos de trabajo (código, configuraciones y documentación) mediante un control riguroso de versiones y cambios.

## 2. Roles y Responsabilidades
Se han definido los siguientes roles funcionales para el proyecto:

| Rol | Responsable | Responsabilidades en GDC |
| :--- | :--- | :--- |
| **Jefe de Proyecto** | AT1RUZ | Aprobación de cambios críticos, gestión del Plan de Proyecto y liberación de versiones. |
| **Gestor de Configuración**| Diego | Mantenimiento del repositorio, cumplimiento de convenios de nombres y auditoría de ramas. |
| **Programador** | AT1RUZ / Diego | Desarrollo de funcionalidades y correcciones siguiendo la política de ramas y commits. |
| **Analista / Auditor** | Diego | Creación de especificaciones de requisitos y validación de la integridad del sistema. |

## 3. Identificación de Elementos de Configuración (EC)
Se han identificado los siguientes elementos sujetos a control de versiones:
- **Código Fuente**: Scripts de despliegue (`scripts/*.sh`).
- **Configuraciones**: Archivos de Postfix, Dovecot, LDAP, OpenDKIM, SpamAssassin y ClamAV.
- **Documentación**: Guías de migración, casos de prueba y reportes técnicos (`pruebas/*.md`).
- **Scripts de Base de Datos**: Esquemas LDAP (`ldap_scripts/*.ldif`).

## 4. Convenio de Nombres
Se ha establecido y verificado el siguiente convenio para mantener la trazabilidad:

### 4.1. Convenio de Mensajes de Commit (Basado en Conventional Commits)
| Prefijo | Descripción | Ejemplo |
| :--- | :--- | :--- |
| `feat:` | Nueva funcionalidad | `feat: integración de ClamAV` |
| `fix:` | Corrección de error | `fix: permisos en socket LMTP` |
| `docs:` | Cambios en documentación | `docs: guía de migración oficial` |
| `config:` | Cambios en archivos de configuración | `config: ajuste de milters en master.cf` |
| `merge:` | Fusión de ramas | `merge: resolver conflictos de fusión` |

### 4.2. Convenio de Ramas
- `main`: Rama de producción estable.
- `feature/[nombre]`: Desarrollo de nuevas capacidades.
- `bugfix/[nombre]`: Corrección de errores en producción o integración.

## 5. Política de Gestión de Ramas y Cambios
1. Todo cambio debe originarse en una rama de `feature` o `bugfix`.
2. El **Programador** sube los cambios a su rama de responsabilidad.
3. Se realiza una autoevaluación o revisión por pares (Auditor).
4. El **Jefe de Proyecto** autoriza el "Merge Request" hacia la rama `main`.
5. Se documenta la duración y el cumplimiento en el registro de tareas (`task.md`).

## 6. Evidencias de Cumplimiento (Auditoría de Git)
Se evidencia el cumplimiento de la política mediante la historia del repositorio:

- **Mapeo de Roles y Versiones**:
  - **Programador (Diego/AT1RUZ)**: Commits como `8a72efc` (feat: bootstrap) y `51d380b` (fix: ssl).
  - **Jefe de Proyecto (AT1RUZ)**: Gestión de fusiones en commit `25c4484` (merge: resolver conflictos).
  - **Analista (AT1RUZ)**: Documentación en commit `bcf6b0f` (docs: guía de producción).

- **Registro de Tiempos**: El seguimiento de duración se realiza mediante el historial de timestamps de Git y el artefacto `task.md`.

## 7. Auto-evaluación (Lista de Chequeo CMMI)
| Actividad | Estado | Evidencia |
| :--- | :--- | :--- |
| Entregar documento del rol | Cumplido | Este informe (Sección 2). |
| Estudiar área de CMMI GDC | Cumplido | Implementación de este informe. |
| Asimilar herramienta GDC | Cumplido | Uso experto de Git y GitHub. |
| Identificar elementos (EC) | Cumplido | Sección 3 de este informe. |
| Elaborar convenio de nombres | Cumplido | Sección 4 de este informe. |
| Definir política de ramas | Cumplido | Sección 5 de este informe. |
| Seguimiento de políticas | Cumplido | Auditoría de commits y branches del 27/02/2026. |
| Registro de tiempo y duración | Cumplido | Timestamps en Git log y `task.md`. |
| Gestión de cambios documentada | Cumplido | Flujo de Merge/Rebase en el historial. |

---
**Resultado de Auditoría:** **CUMPLIMIENTO TOTAL**
**Firma:** Diego (Gestor de Configuración)
