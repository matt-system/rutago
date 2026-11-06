# SURVIVAL — Offline Knowledge System

SURVIVAL es una plataforma original inspirada en la idea de un centro personal de conocimiento offline. Esta primera versión incluye una PWA instalable, panel responsive, guías básicas integradas, notas locales, utilidades y un servidor local opcional que conecta con Ollama.

## Estructura
- `web/`: aplicación PWA.
- `server.mjs`: servidor local y puente privado hacia Ollama.
- `Dockerfile` y `docker-compose.yml`: despliegue local del panel y motor IA.

## Vista web
La preview alojada en Cloudflare sirve el panel y permite probar su interfaz. El asistente local y los recursos realmente descargables requieren desplegar el servidor en un PC.

## Servidor local
Requisitos: Docker y Docker Compose.

```bash
docker compose up -d --build
docker exec -it survival-ollama ollama pull llama3.2:3b
```

Abre `http://localhost:8788`. Para acceder desde otro dispositivo de la misma red, abre `http://IP-DEL-PC:8788`. Mantén el servicio detrás de tu red local; no publiques el puerto de Ollama directamente en Internet.

## Modo offline
La PWA almacena el shell de la aplicación para abrirlo sin conexión después de la primera visita. Las notas y checklist se guardan en el almacenamiento del navegador. El mapa incrustado requiere Internet. Para biblioteca completa y mapas offline hay que descargar archivos ZIM/mapas al servidor y añadir sus servicios locales.

## Próximas integraciones
Kiwix para archivos ZIM; ProtoMaps/tiles locales para mapas; Qdrant para indexar documentos y responder con RAG; gestión de usuarios y copias de seguridad.
