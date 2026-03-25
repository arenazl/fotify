const https = require('https');
const fs = require('fs');
const path = require('path');

const API_KEY = "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";

const PROMPT = `Analizá esta foto y generá todos los tags que sean útiles para buscarla después. Incluí todo lo que veas: personas (género, edad aproximada, ropa, accesorios, pelo, barba), objetos, animales, colores dominantes, lugar (interior/exterior, tipo), clima, momento del día, actividad, emociones, marcas visibles, texto visible, tipo de foto (selfie, paisaje, retrato, etc).
Respondé SOLO con un JSON: {"tags": ["tag1", "tag2", ...]}
Cuantos más tags mejor. Mínimo 15 tags por foto. Todo en español.`;

const PHOTO_DIR = path.join(__dirname, 'Fotify', 'fotos');

function callGroq(base64) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: "meta-llama/llama-4-scout-17b-16e-instruct",
      messages: [{
        role: "user",
        content: [
          {type: "text", text: PROMPT},
          {type: "image_url", image_url: {url: "data:image/jpeg;base64," + base64}}
        ]
      }],
      max_tokens: 400,
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
          resolve(json.choices[0].message.content);
        } catch(e) {
          resolve('ERROR: ' + data.substring(0, 300));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function run() {
  const files = fs.readdirSync(PHOTO_DIR).filter(f => f.endsWith('.jpeg') || f.endsWith('.jpg'));
  console.log("Found " + files.length + " photos\n");

  const allResults = [];

  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    const filePath = path.join(PHOTO_DIR, file);
    const imageData = fs.readFileSync(filePath);
    const base64 = imageData.toString('base64');
    const sizeKB = Math.round(base64.length / 1024);

    console.log("=== FOTO " + (i+1) + " (" + sizeKB + "KB base64) ===");

    const result = await callGroq(base64);
    let tags = [];
    try {
      // Try to parse JSON from response
      let jsonStr = result;
      const start = result.indexOf('{');
      const end = result.lastIndexOf('}');
      if (start >= 0 && end > start) {
        jsonStr = result.substring(start, end + 1);
      }
      const parsed = JSON.parse(jsonStr);
      tags = parsed.tags || [];
      console.log("Tags (" + tags.length + "): " + tags.join(", "));
    } catch(e) {
      console.log("Raw: " + result.substring(0, 300));
    }

    allResults.push({file, tags});
    console.log("");
  }

  // Now simulate searches
  console.log("\n========== SEARCH TESTS ==========\n");

  const queries = [
    "gorra",
    "selfie",
    "paseo",
    "exterior",
    "pesas",
    "gimnasio",
    "comida",
    "nene",
    "niño",
    "pileta",
    "piscina",
    "autopista",
    "tránsito",
    "persona",
    "casa",
    "barba",
    "celular",
    "auriculares",
    "tatuaje"
  ];

  for (const query of queries) {
    const matches = allResults.filter(r =>
      r.tags.some(tag => tag.toLowerCase().includes(query.toLowerCase()))
    );
    const status = matches.length > 0 ? "FOUND" : "MISS ";
    console.log(status + " | \"" + query + "\" → " + matches.length + "/" + allResults.length +
      (matches.length > 0 ? " [" + matches.map(m => "foto" + (allResults.indexOf(m)+1)).join(", ") + "]" : ""));
  }
}

run();
