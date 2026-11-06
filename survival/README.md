# SURVIVAL — Offline Knowledge System

Plataforma personal de conocimiento offline. La aplicación web es la interfaz; el conjunto de servicios locales añade biblioteca ZIM, IA privada con recuperación documental y mapas propios.

## Arquitectura
- `web/`: PWA responsive, notas y checklist local.
- `server.mjs`: API local, proxy y orquestación de IA/RAG.
- `ollama`: modelo conversacional y embeddings locales.
- `qdrant`: base vectorial para fragmentos de documentos.
- `kiwix`: servidor de archivos ZIM.
- `tileserver-gl`: servidor de mapas MBTiles.
- `data/zim/`: archivos ZIM descargados por el usuario.
- `data/maps/`: archivos MBTiles descargados por el usuario.

## Arranque local
Requisitos: Docker Desktop o Docker Engine con Compose, y suficiente almacenamiento para los modelos y datos cartográficos.

```bash
docker compose up -d --build
docker exec -it survival-ollama ollama pull llama3.2:3b
docker exec -it survival-ollama ollama pull nomic-embed-text
```

Abre `http://localhost:8788`. Desde otro equipo conectado a la misma red local, abre `http://IP-DEL-PC:8788`. No publiques los puertos de Ollama ni Qdrant en Internet. El panel local y los servicios auxiliares están pensados para una red de confianza.

## Biblioteca Kiwix
Descarga archivos ZIM desde [Kiwix Library](https://library.kiwix.org/) o [Kiwix downloads](https://download.kiwix.org/zim/). Copia los archivos `.zim` en `data/zim/` y reinicia el servicio si es necesario:

```bash
docker compose restart kiwix
```

Abre la biblioteca en `http://IP-DEL-PC:8081`. Los archivos ZIM pueden ocupar desde cientos de MB hasta decenas de GB; elige los contenidos según tu capacidad de disco.

## Mapas offline
Descarga un archivo MBTiles de una fuente que permita su uso y guárdalo en `data/maps/`. TileServer GL detecta los MBTiles al iniciar:

```bash
docker compose restart maps
```

Abre `http://IP-DEL-PC:8082`. El panel SURVIVAL enlaza al servidor local de mapas. Los mapas no se incluyen automáticamente porque un mapa nacional puede ocupar varios GB y sus licencias/estilos dependen del proveedor. Conserva la atribución requerida por la fuente cartográfica.

## Memoria documental (RAG)
En la pestaña Asistente IA, pega el texto de un manual o documento (hasta 500.000 caracteres). SURVIVAL lo divide en fragmentos, crea embeddings con `nomic-embed-text` y guarda vectores y texto en Qdrant. Al conversar, recupera fragmentos relevantes y los entrega como contexto a Ollama.

La indexación de texto está activa en la API local. En esta primera integración, los documentos se incorporan pegando su texto; la carga automática de PDF/EPUB y la extracción OCR quedan para una siguiente fase.

## Modo sin conexión
La PWA almacena el shell de la aplicación después de la primera visita; notas y checklist quedan en el almacenamiento del navegador. La biblioteca ZIM y los mapas MBTiles se sirven desde el PC local y funcionan sin conexión una vez descargados. Para usar estos servicios desde el teléfono, conecta ambos dispositivos a la misma red local y abre SURVIVAL con la IP del PC.

## Preview Cloudflare
La página pública sirve la interfaz. Los contenedores Kiwix, Qdrant, Ollama y TileServer GL se ejecutan en el PC local: Cloudflare Pages no ejecuta Docker ni aloja automáticamente esos volúmenes de varios GB. Para usar el conjunto completo, inicia el stack local y entra por la dirección local del PC.

## Seguridad y límites
- No expongas Ollama ni Qdrant directamente a Internet.
- La API local está pensada para uso personal en LAN; no tiene autenticación multiusuario en esta versión.
- No uses el contenido como sustituto de servicios de emergencia o asesoría profesional.
