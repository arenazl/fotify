# Fotify - Guía para el Agente

## Qué es Fotify
App iOS nativa (SwiftUI, iOS 18+) para gestión de fotos con IA. Se distribuye via AltStore (sideloading).

## Workflow de desarrollo
1. El agente escribe/modifica código Swift
2. El agente commitea y pushea a `master`
3. GitHub Actions (CI) buildea el IPA automáticamente
4. El usuario abre AltStore en su iPhone y actualiza

**El usuario NO toca código, NO usa Xcode, NO edita archivos.**
Su única acción es abrir AltStore y tocar "actualizar".

## Qué hace el agente en cada cambio
1. Modificar los `.swift` necesarios
2. Si se crea un archivo `.swift` nuevo, agregarlo al `Fotify.xcodeproj/project.pbxproj` (silenciosamente, sin mencionarlo)
3. Actualizar `altstore-source.json` con la nueva versión y descripción
4. Commitear todo junto y pushear a `master`
5. Avisar al usuario que ya puede actualizar en AltStore

## Qué NO hacer
- No mencionar pbxproj, xcodeproj, ni internals de Xcode
- No pedir al usuario que haga nada técnico
- No hablar de archivos, hablar de funcionalidades
- No preguntar cosas que ya están en este documento

## Estructura del proyecto
```
Fotify/
├── FotifyApp.swift              # Entry point
├── Info.plist                   # Permisos iOS
├── Assets.xcassets/             # Iconos
├── Views/
│   ├── ContentView.swift        # App shell, navegación, Neural Orb (Groq input)
│   ├── NeuralDashboard.swift    # CORTEX: grid 12 categorías + timeline
│   ├── PhotoMeshView.swift      # MESH: galería agrupada por mes
│   ├── CleanupView.swift        # PURGE: eliminar capturas y duplicados
│   └── CategoryDetailView.swift # Grid filtrado por categoría
├── ViewModels/
│   ├── TagsViewModel.swift      # Clasificación Vision Framework
│   └── DuplicatesViewModel.swift # Scanner duplicados (dHash)
└── Services/
    ├── PhotoLibraryService.swift # PhotoKit + enum PhotoCategory
    ├── GrokService.swift         # Groq LLama API (comandos naturales)
    └── Config.swift              # API keys, límites
```

## Stack
- **UI:** SwiftUI con MeshGradient, glass morphism, dark mode
- **Fotos:** PhotoKit (PHAsset, PHCachingImageManager)
- **IA local:** Vision Framework (clasificación, detección caras, texto)
- **IA cloud:** Groq API (LLama 3.3-70b) para comandos naturales
- **CI/CD:** GitHub Actions → IPA → AltStore
- **Distribución:** altstore-source.json apunta a fotify-dist repo

## Los 3 módulos
- **CORTEX** (dashboard): Grid de 12 categorías + timeline (hoy/ayer/semana)
- **MESH** (galería): Fotos agrupadas por mes con scroll horizontal
- **PURGE** (limpieza): Eliminar capturas de pantalla y duplicados

## Las 12 categorías (todas funcionales en v31)
| Categoría | Fuente de datos |
|-----------|----------------|
| Timeline | Todas las fotos |
| Lugares | Fotos con GPS |
| Personas | Vision: detección de caras |
| Capturas | PhotoKit: mediaSubtype screenshot |
| Duplicados | dHash perceptual |
| Favoritos | PhotoKit: isFavorite |
| Videos | PhotoKit: mediaType video |
| Selfies | Smart Album selfPortraits |
| Live Photos | PhotoKit: mediaSubtype live |
| Documentos | Vision: detección de texto (3+ regiones) |
| Noche | Hora de creación entre 20:00 y 06:00 |
| Tags IA | Vision Framework clasificación |

## Versionado
- Versión actual: 1.4 (v31)
- El JSON `altstore-source.json` lleva el historial de versiones
- Los commits siguen el patrón: `feat: v31 - descripción`
