# Fotify - Documentación Técnica

## Stack

| Capa | Tecnología |
|------|-----------|
| Lenguaje | Swift 5.0 |
| UI | SwiftUI (nativo iOS) con diseño iOS 26 (MeshGradient, Glass Morphism) |
| Target mínimo | iOS 18.0 (requerido por MeshGradient) |
| Fotos | PhotoKit (PHAsset, PHCachingImageManager) |
| IA local | Vision Framework (VNClassifyImageRequest) |
| IA cloud | Grok Vision API (xAI, formato OpenAI-compatible) |
| Arquitectura | MVVM (Model-View-ViewModel) |
| CI/CD | GitHub Actions (runner macOS-14) |

---

## Estructura del proyecto

```
Fotify/
├── FotifyApp.swift                 # Entry point, inyecta PhotoLibraryService
├── Info.plist                      # Permisos: NSPhotoLibraryUsageDescription
├── Assets.xcassets/                # Iconos y assets
├── Views/
│   ├── ContentView.swift           # App shell: MeshGradient background, permisos,
│   │                               # header con stats reales, Neural Orb (Grok input),
│   │                               # module selector (CORTEX/MESH/PURGE)
│   ├── NeuralDashboard.swift       # Dashboard: stats reales de la librería,
│   │                               # barra de composición fotos/capturas,
│   │                               # accesos rápidos, preview de fotos recientes
│   ├── PhotoMeshView.swift         # Librería agrupada por mes (fecha real de PHAsset),
│   │                               # galerías horizontales, badges de screenshots,
│   │                               # barra de tags si están clasificadas
│   └── CleanupView.swift           # Tabs CAPTURAS/DUPLICADOS, círculo de vaporización
│                                   # con datos reales, grid con selección múltiple,
│                                   # scanner dHash, eliminación batch real
├── ViewModels/
│   ├── DuplicatesViewModel.swift   # Algoritmo dHash (difference hash) 64-bit
│   └── TagsViewModel.swift         # Clasificación Vision Framework + Grok API
└── Services/
    ├── PhotoLibraryService.swift   # PhotoKit: fetch, thumbnails, eliminación
    ├── GrokService.swift           # Cliente Grok: comandos NL + clasificación de imágenes
    └── Config.swift                # API keys y constantes
```

---

## Diseño Visual - iOS 26 Aesthetic

### Sistema de diseño

| Elemento | Implementación |
|----------|---------------|
| Fondo | `MeshGradient` 3x3 (black/indigo/purple/blue) con `hueRotation` animada |
| Cards | Glass morphism: `Color.white.opacity(0.03)` + border `0.05` + `cornerRadius(40)` |
| Botones | Capsule blancos con `shadow(color: .white.opacity(0.3), radius: 20)` |
| Texto | Kerning expandido, `weight: .ultraLight` para números grandes, `.black` para labels |
| Iconos | SF Symbols con `symbolEffect(.variableColor)` |
| Transiciones | `.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity)` |
| Pulse | Circle de 4px con `shadow(radius: 10)` y `scaleEffect` animado infinito |

### Pantallas

1. **CORTEX (Dashboard):** Stats reales de la librería, barra de composición fotos/capturas, accesos rápidos con glass morphism, preview horizontal de fotos recientes
2. **MESH (Librería):** Fotos agrupadas por mes con fecha real, galerías horizontales scrollables, badges para screenshots, barra de tags si hay clasificación
3. **PURGE (Limpieza):** Tabs capturas/duplicados, círculo de vaporización animado con datos reales, grid de selección múltiple, scanner dHash con progreso, botón "VAPORIZAR" conectado a `PHAssetChangeRequest.deleteAssets`

---

## Permisos iOS requeridos

| Permiso | Key en Info.plist | Motivo |
|---------|-------------------|--------|
| Lectura/escritura de fotos | `NSPhotoLibraryUsageDescription` | Acceder, organizar y eliminar fotos |
| Guardar fotos | `NSPhotoLibraryAddUsageDescription` | Guardar fotos organizadas |

La app solicita `.readWrite`. iOS muestra diálogo de confirmación del sistema en cada eliminación.

---

## Funcionalidades

### 1. Acceso a librería (PhotoLibraryService)
- Permisos con `PHPhotoLibrary.requestAuthorization(for: .readWrite)`
- UI de permisos con estética futurista (pulse animation, MeshGradient)
- Fetch de `PHAsset` tipo imagen, ordenados por fecha descendente
- Conteo separado de fotos y screenshots

### 2. Dashboard con datos reales (NeuralDashboard)
- Conteo real de fotos desde `PhotoLibraryService.photoCount`
- Barra de composición: ratio fotos/capturas calculado en tiempo real
- Barras de visualización animadas proporcionales al tamaño de la librería
- Preview de las 8 fotos más recientes con thumbnails reales

### 3. Librería agrupada por mes (PhotoMeshView)
- Agrupa `PHAsset` por `creationDate` usando `DateFormatter` con locale `es_AR`
- Ordenado por fecha descendente (más reciente primero)
- Galerías horizontales con hasta 20 fotos por grupo
- Badge de `rectangle.dashed` en fotos que son screenshots
- Barra de tags si se corrió clasificación

### 4. Detección y eliminación de screenshots (CleanupView)
- Filtra por `PHAsset.mediaSubtypes.photoScreenshot`
- Grid de 4 columnas con selección múltiple
- Círculo de vaporización con conteo real
- Eliminación batch via `PHAssetChangeRequest.deleteAssets`
- `confirmationDialog` antes de eliminar

### 5. Detección de duplicados - dHash (DuplicatesViewModel)
- Redimensiona a 9×8, convierte a grayscale
- Genera hash de 64 bits comparando píxeles adyacentes
- Agrupa por hash idéntico
- Progreso visual durante escaneo
- Cards por grupo de duplicados con scroll horizontal

### 6. Clasificación Vision Framework (TagsViewModel)
- `VNClassifyImageRequest` sobre thumbnails 300×300
- Confidence > 0.3, top 5 tags por foto
- Hasta 500 fotos por escaneo
- Tags en inglés (taxonomía de Vision)

### 7. Grok Vision API (GrokService)
- **Comandos naturales:** interpreta texto del usuario y navega a la sección correcta
  - "mostrá las capturas" → va a PURGE/capturas
  - "buscá duplicados" → va a PURGE/duplicados
  - "clasificá mis fotos" → inicia tagging
- **Clasificación de imágenes:** envía thumbnails 512×512 como JPEG base64
  - Tags en español predefinidos
  - Límite 100 fotos por escaneo
- **Fallback local:** si no hay API key, los comandos se matchean por keywords

---

## Arquitectura

```
View (SwiftUI + iOS 26 Design)
  ↓ observa @Published
ViewModel (@MainActor, ObservableObject)
  ↓ llama métodos
Service (PhotoLibraryService, GrokService)
  ↓ accede
PhotoKit / Vision / Grok HTTP API
```

- `PhotoLibraryService`: `@StateObject` en App root, inyectado con `.environmentObject()`
- ViewModels: `@StateObject` locales por vista
- `GrokService`: actor singleton, thread-safe
- Toda la UI corre en `@MainActor`

---

## Pipeline CI/CD

**Archivo:** `.github/workflows/build.yml`

- **Runner:** `macos-14` (Apple Silicon, Xcode 16)
- **Trigger:** push/PR a `main`, o manual
- **Build:** compila para iOS Simulator sin code signing
- **Archive:** manual, genera `.xcarchive`

---

## Costo Grok API

| Fotos procesadas | Costo aprox |
|-----------------|-------------|
| 100 (default) | ~$0.15-0.30 USD |
| 1,000 | ~$1.50-3.00 USD |

---

## Limitaciones conocidas

1. iOS siempre muestra diálogo de confirmación al eliminar
2. Modo "Limited" no permite crear álbumes ni ver toda la librería
3. Fotos iCloud se descargan bajo demanda
4. dHash detecta duplicados exactos; Hamming distance para similares pendiente
5. Vision tags en inglés
6. Sin persistencia local (SwiftData pendiente)
7. `MeshGradient` requiere iOS 18+ (tu iPhone con iOS 26 lo soporta)
