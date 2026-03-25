const https = require('https');
const API_KEY = "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";

// Tags reales generados por el prompt simple
const PHOTOS = {
  "Selfie con gorra": ["hombre", "selfie", "telefono", "sombrero", "camiseta", "tatuaje", "espejo", "pared", "cuadrado", "casual"],
  "Costanera/paseo": ["camino", "paseo", "urbano", "parque", "jardín", "césped", "farolas", "cielo azul", "nubes", "paisaje urbano"],
  "Pesas en casa": ["barra de pesas", "pesas", "gimnasio en casa", "jardín", "terraza", "muebles de jardín", "sala de estar", "comedor", "decoración de interiores", "fitness en casa"],
  "Pastel de papa": ["comida", "pastel", "pastel de papas", "comida casera", "plato", "carne", "papas", "salmag", "comida argentina", "pastel de carne"],
  "Nene con alas": ["alas", "azul", "bosque", "colores", "fantasia", "niño", "pájaro", "rojo", "verde", "vuelo"],
  "Pileta hotel": ["piscina", "alberca", "pileta", "agua", "azul", "verde", "arboles", "sillas", "descanso", "verano"],
  "Autopista transito": ["carretera", "tráfico", "vehículos", "conduciendo", "cielo", "nubes", "árboles", "guarda rail", "autos", "ruta"]
};

const SEARCH_PROMPT = `El usuario busca fotos con: "QUERY"
Generá las palabras clave para buscar en los tags de las fotos. Incluí sinónimos, variantes sin tildes y regionalismos.
Solo respondé con un JSON: {"search": ["palabra1", "palabra2", ...]}`;

function callGroq(query) {
  return new Promise((resolve, reject) => {
    const prompt = SEARCH_PROMPT.replace("QUERY", query);
    const body = JSON.stringify({
      model: "llama-3.3-70b-versatile",
      messages: [{role: "user", content: prompt}],
      max_tokens: 200,
      temperature: 0.1
    });
    const req = https.request({
      hostname: 'api.groq.com', path: '/openai/v1/chat/completions', method: 'POST',
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + API_KEY}
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          const content = json.choices[0].message.content;
          const s = content.indexOf('{'), e = content.lastIndexOf('}');
          if (s >= 0 && e > s) {
            const parsed = JSON.parse(content.substring(s, e + 1));
            resolve(parsed.search || parsed.tags || []);
          } else resolve([]);
        } catch(err) { resolve([]); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function searchPhotos(searchTerms) {
  const results = [];
  for (const [name, tags] of Object.entries(PHOTOS)) {
    const match = searchTerms.some(term =>
      tags.some(tag => tag.toLowerCase().includes(term.toLowerCase()) || term.toLowerCase().includes(tag.toLowerCase()))
    );
    if (match) results.push(name);
  }
  return results;
}

async function run() {
  const queries = [
    "gorra",
    "pileta",
    "nene",
    "autopista",
    "comida casera",
    "fotos en la calle",
    "ejercicio",
    "selfie",
    "foto de un chico",
    "vacaciones",
    "tránsito",
    "foto con tatuaje",
    "pastel de papa",
    "lugar para caminar",
    "auto en la ruta",
    "foto de un nene en el bosque",
    "agua",
    "deporte",
    "foto de comida argentina"
  ];

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║              TEST DE BÚSQUEDA CON SINÓNIMOS                ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  let pass = 0, fail = 0;

  for (const q of queries) {
    const searchTerms = await callGroq(q);
    const matches = searchPhotos(searchTerms);
    const icon = matches.length > 0 ? "✅" : "❌";

    console.log(icon + " \"" + q + "\"");
    console.log("   Groq expandió a: " + searchTerms.join(", "));
    console.log("   Resultados: " + (matches.length > 0 ? matches.join(", ") : "NINGUNO"));
    console.log("");

    if (matches.length > 0) pass++; else fail++;
  }

  console.log("═══════════════════════════════════════");
  console.log("RESULTADO: " + pass + "/" + (pass + fail) + " búsquedas encontraron fotos");
}

run();
