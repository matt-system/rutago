# Meshbit — principios de discreción y privacidad

Este documento define los requisitos de producto y arquitectura. La privacidad no es un complemento: es el criterio principal de diseño.

## Objetivo
Permitir conversaciones privadas y discretas entre dispositivos Android y iPhone, reduciendo tanto la exposición del contenido como la cantidad de metadatos que el servicio necesita conocer. No prometer anonimato absoluto ni invulnerabilidad.

## Requisitos obligatorios

### 1. Identidad mínima
- No exigir teléfono, correo, nombre real, agenda ni inicio de sesión con redes sociales.
- Usar identificadores aleatorios y alias opcionales.
- No publicar directorios abiertos de usuarios ni permitir enumeración masiva de cuentas.
- Separar identidad de cuenta, claves criptográficas y credenciales de sesión.

### 2. Cifrado de extremo a extremo
- El cifrado y descifrado ocurren en los dispositivos.
- El servidor y los relays reciben únicamente sobres cifrados.
- Adoptar un protocolo mantenido y revisado para mensajería asíncrona, con ratchet, rotación de claves y secreto hacia adelante; no diseñar criptografía propia.
- Verificar identidad de contacto mediante códigos de seguridad/QR por un canal independiente.
- Las claves privadas no salen del dispositivo y deben almacenarse mediante mecanismos seguros del sistema operativo cuando estén disponibles.
- Rechazar mensajes alterados, repetidos o dirigidos a claves incorrectas.

### 3. Minimización de metadatos
- No guardar contenido en claro, agenda, ubicación, identificadores publicitarios ni analítica.
- Evitar logs de IP y de actividad en componentes bajo control del proyecto; revisar también logs y retención del proveedor de infraestructura.
- Reducir los metadatos de enrutamiento y la retención al mínimo necesario para entregar mensajes.
- Usar identificadores opacos, no alias, en las rutas internas cuando sea posible.
- Aplicar límites contra enumeración y abuso sin crear perfiles de actividad.
- Expirar y borrar sobres cifrados después de la entrega o de una ventana corta y documentada.

### 4. Discreción de la aplicación
- Sin trackers, anuncios, SDK de analítica ni telemetría de terceros.
- No mostrar contenido de mensajes en notificaciones por defecto; permitir vista previa opcional.
- Bloqueo local de la app y protección frente a capturas/recientes cuando la plataforma lo permita.
- No cachear mensajes ni claves en el Service Worker; borrar cachés sensibles y mantener la app shell separada de los datos privados.
- Mantener dependencias mínimas, fijadas y auditables; evitar scripts remotos.

### 5. Transporte e infraestructura
- TLS obligatorio.
- Diseñar la aplicación para poder cambiar de proveedor/relay sin cambiar el protocolo ni las identidades.
- Considerar relays separados y técnicas de reducción de correlación de tráfico; evaluar cuidadosamente el coste de latencia y disponibilidad.
- No afirmar que un servidor es “imposible de rastrear”. El proveedor de red puede observar metadatos de conexión, y la IP puede ser visible en distintos puntos del transporte.
- No recomendar infraestructura por ser “difícil de rastrear” como sustituto de un diseño seguro.

### 6. PWA Android/iOS
- Una misma PWA instalable desde navegador en ambas plataformas.
- Usar Web Crypto y almacenamiento protegido cuando sea compatible; evaluar limitaciones reales de Safari/iOS y el ciclo de vida de la PWA.
- La PWA debe bloquear el acceso a mensajes si el almacén local no puede proteger las claves adecuadamente.
- No confiar en IndexedDB como almacén secreto sin cifrado de aplicación y protección adicional.
- Probar instalación, persistencia, bloqueo, actualización, borrado y recuperación en iPhone y Android físicos.

## Condición antes de uso sensible
La versión beta actual no debe anunciarse como anónima ni como adecuada para información sensible. Antes de afirmarlo se requiere:
1. protocolo E2EE mantenido e integración revisada;
2. análisis de metadatos y políticas de retención de todos los proveedores;
3. pruebas cruzadas Android/iOS en dispositivos reales;
4. revisión independiente de seguridad y pruebas de penetración;
5. documentación honesta de límites, riesgos y modelo de amenazas.

## Modelo de amenazas
Proteger frente a lectura del contenido por el servidor, interceptación de red, robo de base de datos y exposición accidental por telemetría. Evaluar por separado la correlación de quién habla con quién, análisis de horarios/tráfico, compromiso del dispositivo, capturas de pantalla, copias de seguridad, notificaciones y errores del usuario. Ninguna aplicación puede garantizar anonimato absoluto frente a un dispositivo comprometido o a todos los observadores de red.
