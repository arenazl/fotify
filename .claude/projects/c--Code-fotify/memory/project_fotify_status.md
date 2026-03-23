---
name: Fotify iOS App Status
description: Current state of Fotify iOS photo manager app - what works, what's pending
type: project
---

## Estado actual: v30 (Cortex v.30, version 1.4)

### Funciona:
- Dashboard con categorías y timeline (Hoy, Ayer, Esta semana)
- Fotos reales cargando desde PhotoKit
- Conteo real de fotos y capturas
- Groq API conectada y respondiendo
- Vision Framework clasificación (se ejecuta al buscar)
- Instalación via AltStore con source en fotify-dist repo
- Teclado se cierra al tocar fuera

### NO funciona (pendiente):
- **Botones de categorías no hacen nada**: Lugares, Personas, Selfies, Favoritos, Videos, Live Photos, Documentos, Noche, Tags IA, Timeline, Duplicados, Capturas — todos son solo visuales
- **MESH view**: muestra fotos por mes pero no filtra
- **PURGE view**: capturas y duplicados existen pero no se acceden desde el dashboard
- **Búsqueda por IA**: clasifica pero no muestra resultados filtrados visualmente
- **No hay persistencia**: tags se pierden al cerrar la app (SwiftData pendiente)

### Arquitectura:
- Repo código: github.com/arenazl/fotify
- Repo distribución IPA: github.com/arenazl/fotify-dist
- Source AltStore: raw.githubusercontent.com/arenazl/fotify-dist/main/altstore-source.json
- Build: GitHub Actions macos-15
- IA texto: Groq API (llama-3.3-70b-versatile)
- IA imágenes: Vision Framework on-device (Groq no tiene modelos de visión)
- iPhone: 16 Pro, iOS 26.3.1

### Para el update process:
1. Cambiar código + bump MARKETING_VERSION en pbxproj
2. Push a GitHub → build automático
3. Descargar IPA del release → copiar a fotify-dist
4. Actualizar version y size en altstore-source.json de fotify-dist
5. Push fotify-dist → esperar 5 min cache
6. Usuario: AltStore → Browse → Fotify → FREE

**Why:** El usuario quiere la app 100% funcional — todas las categorías conectadas, búsqueda real, y flujo completo.

**How to apply:** Próxima sesión: implementar todas las categorías con filtros reales de PhotoKit y conectar la búsqueda IA con resultados visuales.
