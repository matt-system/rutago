# MESHBIT Native — chat mesh local

Aplicación nativa Flutter para conversaciones locales sin Internet. El transporte MESH está limitado a **Bluetooth LE**: no usa Wi-Fi, router, datos móviles, servidores ni relays online.

## Funciones incluidas en esta versión

- Descubrimiento y publicidad BLE con el teléfono actuando como nodo que puede recibir y enviar.
- Sesiones punto a punto con cifrado del transporte y código PIN de verificación por sesión.
- Canal común **#general**, protegido por una clave compartida de 256 bits.
- Conversaciones privadas 1 a 1, sin teléfono, correo ni cuenta central.
- Alias y directorio local de contactos; las claves se guardan mediante Keychain en iOS y el almacén cifrado del sistema en Android.
- Sobres de mensajes cifrados con AES-256-GCM. El texto, alias, emisor y destinatario quedan dentro del ciphertext.
- Retransmisión multi-salto por inundación controlada, TTL máximo de 7 saltos, deduplicación y exclusión del enlace de entrada.
- Store-and-forward en SQLite: cada paquete queda guardado hasta 7 días y se reintenta al aparecer otro vecino. El registro de reenvío por vecino evita repetir continuamente el mismo paquete.
- Bandeja local y conversación con dos modos de lectura: burbujas y terminal.
- Comandos locales `/help`, `/who` y `/id`.
- Pantalla de nodos cercanos, verificación de sesión y contador de conexiones.
- La app mantiene la pantalla encendida durante una sesión MESH; aumenta el consumo de batería.

## Primer uso

1. Instala MESHBIT en dos o más teléfonos. Activa Bluetooth y concede los permisos solicitados.
2. Abre la app y deja la pantalla MESHBIT abierta. La búsqueda y publicidad Bluetooth se inician automáticamente.
3. Para el canal común, abre el icono de llave de **#general** y comparte el código `MESH1:...` con quienes quieras incluir. Los participantes deben guardar la misma clave.
4. Para un privado, comparte tu **ID MESH**. Añade el contacto con su ID, define o introduce una clave de 64 caracteres hexadecimales y guarda la misma clave en ambos teléfonos.
5. Al conectar teléfonos cercanos, compara el PIN de ambos extremos antes de confirmar. Un vecino que no se haya verificado no puede retransmitir paquetes.
6. Para probar varios saltos, deja el teléfono B conectado a A y C; separa A y C fuera de alcance directo. Un mensaje de A destinado a C puede atravesar B y permanecer guardado en los nodos intermedios.

Las claves se deben compartir por un canal de confianza distinto de MESHBIT. El código QR para invitaciones y el intercambio autenticado de claves quedan para una siguiente versión.

## Distribución fuera de las tiendas

- Android: GitHub Actions construye un APK de prueba y lo publica en una GitHub Release. Se instala directamente; no se publica en Google Play.
- El botón **CHAT online** abre la PWA cifrada ya existente. Es un acceso separado que requiere Internet; no participa en el transporte MESH ni es necesario para el chat Bluetooth.
- iOS: el proyecto compila sin firma en CI. Para instalar un IPA en iPhones se necesita firmarlo con un perfil/certificado válido y distribuirlo directamente; no requiere publicar en App Store.
- Las pruebas de compilación no sustituyen pruebas físicas BLE entre varios teléfonos. Todavía hay que validar Android↔Android, iPhone↔iPhone y Android↔iPhone en campo.

## Límites de seguridad y funciones pendientes

Esta versión ya transporta mensajes cifrados por una red BLE local, pero **no es aún equivalente a Bitchat ni está auditada**. Usa clave compartida manual y AES-GCM; aún no integra un protocolo de sesión tipo Noise XX/Double Ratchet, firmas independientes de cada emisor, recibos de entrega/lectura, adjuntos, notas de voz, canales geográficos ni un sistema de courier spray-and-wait. En el canal común, cualquier miembro que conozca la clave puede generar mensajes con el alias que elija.

Los nodos intermedios ven metadatos mínimos de transporte (ID aleatorio de paquete, TTL, tamaño del ciphertext y momento local de recepción), pero no el texto ni el alias. La radio BLE permite inferir proximidad. No prometer anonimato absoluto ni usar esta beta para comunicaciones de alto riesgo.

## Licencias y procedencia

Meshbit tiene implementación independiente. No se ha copiado código fuente de Bitchat Android (GPL-3.0) ni del repositorio iOS/macOS de Bitchat (Unlicense). Ver [PROVENANCE.md](PROVENANCE.md). Los paquetes Flutter externos conservan las licencias que les corresponden, incluidas las BSD de `nearby` y `flutter_secure_storage`.

## Compilar

Desde esta carpeta:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
