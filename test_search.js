const https = require('https');

const API_KEY = "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";

const SEARCH_PROMPT = `Sos el motor de búsqueda de Fotify. Las fotos están indexadas con campos: personas, lugar, objetos, escena, actividad, texto.

El usuario busca: "QUERY"

Respondé SOLO con este JSON (sin markdown):
{"filters": [{"field": "campo", "values": ["sinonimo1", "sinonimo2"]}], "message": "respuesta"}

Reglas:
- field: personas, lugar, objetos, escena, actividad, texto
- Si busca personas, usá field personas con values ["not_empty"]
- Podés usar múltiples filtros. Usá OR (múltiples fields con mismos values) cuando no estés seguro en qué campo está.
- values es un ARRAY con la palabra + sinónimos + variantes sin tildes + gerundios + plurales
  Ejemplo: noche → values: ["noche", "nocturno", "oscuro", "nocturna"]
  Ejemplo: montaña → values: ["montaña", "montana", "monte", "sierra", "cerro"]
  Ejemplo: jugar → values: ["jugando", "juego", "jugar", "juegan"]
  Ejemplo: niños → values: ["niño", "nino", "niña", "nina", "chico", "nene", "niños", "ninos"]
- Si un concepto puede estar en varios campos, usá el que tenga más sentido. Si no estás seguro, priorizá: escena > objetos > lugar > actividad
- Para búsquedas simples de un solo concepto, usá UN solo filtro en el campo más probable
  Ejemplo: "comida" → UN filtro en objetos: ["comida", "plato", "platos", "alimento"]
  Ejemplo: "capturas de pantalla" → UN filtro en escena: ["captura", "screenshot", "pantalla"]`;

const DB = [
  {personas:"hombre, mujer",lugar:"interior casa",objetos:"sillon, mesa, televisor",escena:"hogar nocturno",actividad:"mirando television",texto:""},
  {personas:"",lugar:"exterior playa",objetos:"perro, arena, olas",escena:"perro en playa",actividad:"corriendo",texto:""},
  {personas:"mujer",lugar:"interior oficina",objetos:"laptop, escritorio, cafe",escena:"trabajo",actividad:"trabajando",texto:""},
  {personas:"hombre, nino",lugar:"exterior parque",objetos:"pelota, arboles",escena:"juego en parque",actividad:"jugando al futbol",texto:""},
  {personas:"",lugar:"interior cocina",objetos:"platos de comida, sarten, verduras",escena:"comida preparada",actividad:"cocinando",texto:""},
  {personas:"grupo",lugar:"exterior calle",objetos:"autos, edificios, carteles",escena:"ciudad",actividad:"caminando",texto:""},
  {personas:"",lugar:"exterior montana",objetos:"rio, rocas, arboles, nieve",escena:"paisaje natural",actividad:"ninguna",texto:""},
  {personas:"mujer",lugar:"interior restaurante",objetos:"plato de sushi, palitos, vaso",escena:"cena",actividad:"comiendo sushi",texto:""},
  {personas:"",lugar:"interior",objetos:"pantalla de telefono, iconos de apps",escena:"captura de pantalla",actividad:"ninguna",texto:""},
  {personas:"hombre",lugar:"exterior playa",objetos:"tabla de surf, arena",escena:"deporte acuatico",actividad:"surfeando",texto:""}
];

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
      hostname: 'api.groq.com',
      path: '/openai/v1/chat/completions',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + API_KEY
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          const content = json.choices[0].message.content;
          resolve(JSON.parse(content));
        } catch(e) {
          resolve(null);
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function matchFilters(photo, filters) {
  return filters.every(f => {
    const val = (photo[f.field] || "").toLowerCase();
    if (f.values.includes("not_empty")) return val.length > 0;
    return f.values.some(v => val.includes(v.toLowerCase()));
  });
}

async function runTests() {
  const queries = [
    "fotos con personas",
    "perro en la playa",
    "fotos dentro de casas",
    "paisajes de montaña",
    "fotos en la oficina",
    "fotos de niños jugando",
    "fotos de noche",
    "fotos en restaurantes",
    "comida",
    "capturas de pantalla"
  ];

  let pass = 0, fail = 0;

  for (const q of queries) {
    const result = await callGroq(q);
    if (!result || !result.filters) {
      console.log("ERROR | \"" + q + "\" → no response");
      fail++;
      continue;
    }

    const matches = DB.filter(p => matchFilters(p, result.filters));
    const filtersStr = result.filters.map(f => f.field + ":" + f.values.join("|")).join(" + ");

    if (matches.length > 0) {
      console.log("PASS  | \"" + q + "\" → " + matches.length + " results | " + filtersStr);
      matches.forEach(m => console.log("        → " + m.escena + " | " + m.lugar));
      pass++;
    } else {
      console.log("FAIL  | \"" + q + "\" → 0 results | " + filtersStr);
      fail++;
    }
  }

  console.log("\n=== " + pass + "/" + (pass+fail) + " passed ===");
}

runTests();
