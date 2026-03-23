---
name: Feedback de comunicación y proceso
description: Cómo trabajar con Lucas - errores a evitar
type: feedback
---

- NO dar respuestas largas. Ir al grano.
- NO proponer soluciones sin verificarlas primero.
- Validar TODO antes de mandar al usuario (URLs, JSON, formato).
- Cuando algo no funciona, no tirar soluciones al azar — investigar la causa real.
- El proceso de AltStore source JSON requiere: campos legacy a nivel app (version, versionDate, downloadURL, size), appPermissions con arrays de objetos {name, usageDescription}, iconURL obligatorio y funcional.
- raw.githubusercontent.com cachea 5 minutos.
- Git en Windows corrompe binarios (.ipa) si no hay .gitattributes con `*.ipa binary`.
- No confundir Groq (groq.com, LLama) con Grok (xAI). Lucas usa Groq.

**Why:** El usuario se frustró múltiples veces porque mandé soluciones sin validar, di respuestas contradictorias sobre sideloading, y confundí Groq con Grok.

**How to apply:** Siempre validar URLs y JSON antes de pushear. Comparar con formato oficial de AltStore. No asumir — verificar.
