const https = require('https');
const API_KEY = "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";

const PHOTOS = {
  "Selfie con gorra": ["hombre","selfie","espejo","telefono","sombrero","gorra","camiseta","tatuaje","musculos","fitness","gimnasio","deporte","actividad fisica","sudor","concentrado","mirada baja","tecnologia","moda","estilo","urbano"],
  "Costanera/paseo": ["camino","paseo","sendero","jardín","parque","césped","farolas","alumbrado","urbano","paisaje","arquitectura","infraestructura","espacio","aire libre","día","cielo","azul","nubes","sombra","pavimento"],
  "Pesas en casa": ["barra","pesas","gimnasio","jardín","terraza","sala de estar","comedor","muebles","deporte","fitness","interior","hogar","patio","ventana","paisajismo","arquitectura","diseño","barra de pesas","entrenamiento","rojo","pesas rojas"],
  "Pastel de papa": ["comida","plato","pastel","pastel de papas","carne","molido","papas","salsa","comida casera","rico","delicioso","verduras","cena","almuerzo","familiar","cocina","tradicional","casero","sabroso","tarta","torta","tortas"],
  "Nene con alas": ["alitas","azul","bosque","colores","divertido","fotografia","infantil","joven","niño","pajaros","rojo","verde","verano","vibrante","infancia","feliz","sonriente","alegre","fantasia","arte"],
  "Pileta hotel": ["piscina","alberca","agua","azul","cielo","nubes","arboles","sillas","descanso","verano","soleado","dia","exterior","lugar de vacaciones","hotel","resort","piscina exterior","relax","diversión","espacio abierto"],
  "Autopista transito": ["carretera","tráfico","vehículos","conduciendo","cielo","nubes","árboles","guarda rail","vans","autos","camino","paisaje","urbano","día","azul","verde","fotografía desde auto","transporte","movimiento","congestión vehicular"]
};

const SEARCH_PROMPT = `El usuario busca fotos con: "QUERY"
Extraé el concepto principal de lo que busca e ignorá palabras como "fotos de", "fotos con", "foto de", "mostrame".
Generá las palabras clave para buscar en los tags de las fotos indexadas. Incluí sinónimos, variantes sin tildes, regionalismos y algún error de ortografía común.
SIEMPRE respondé con al menos 5 palabras. Nunca devuelvas un array vacío.
Solo respondé con un JSON: {"search": ["palabra1", "palabra2", ...]}`;

const query = process.argv[2] || "aparatos de gimnasio";

function callGroq(q) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: "llama-3.3-70b-versatile",
      messages: [{role: "user", content: SEARCH_PROMPT.replace("QUERY", q)}],
      max_tokens: 200, temperature: 0.1
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
          const parsed = JSON.parse(content.substring(s, e + 1));
          resolve(parsed.search || parsed.tags || []);
        } catch(err) { resolve([]); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function run() {
  const terms = await callGroq(query);
  console.log("Query: \"" + query + "\"");
  console.log("Expandido a: " + terms.join(", "));

  const results = [];
  for (const [name, tags] of Object.entries(PHOTOS)) {
    const match = terms.some(term =>
      tags.some(tag => tag.toLowerCase().includes(term.toLowerCase()) || term.toLowerCase().includes(tag.toLowerCase()))
    );
    if (match) results.push(name);
  }
  console.log("Resultados: " + (results.length > 0 ? results.join(", ") : "NINGUNO"));
}

run();
