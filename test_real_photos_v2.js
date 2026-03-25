const https = require('https');
const fs = require('fs');
const path = require('path');

const API_KEY = "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";

const PROMPT = `Analizá esta foto y generá los 15 tags más importantes para poder encontrarla o agruparla en una búsqueda. Todos los tags en español. Solo respondé con un JSON: {"tags": ["tag1", ...]}`;

const PHOTO_DIR = path.join(__dirname, 'Fotify', 'fotos');

const PHOTO_NAMES = [
  "Selfie con gorra",
  "Costanera/paseo",
  "Pesas en casa",
  "Pastel de papa",
  "Nene con alas",
  "Pileta hotel",
  "Autopista tránsito"
];

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
      max_tokens: 800,
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
          const usage = json.usage;
          resolve({content, usage});
        } catch(e) {
          resolve({content: 'ERROR: ' + data.substring(0, 300), usage: null});
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

  const allResults = [];

  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    const name = PHOTO_NAMES[i] || file;
    const filePath = path.join(PHOTO_DIR, file);
    const imageData = fs.readFileSync(filePath);
    const base64 = imageData.toString('base64');

    const {content, usage} = await callGroq(base64);

    let tags = [];
    let raw = content;
    try {
      let jsonStr = content;
      const start = content.indexOf('{');
      const end = content.lastIndexOf('}');
      if (start >= 0 && end > start) {
        jsonStr = content.substring(start, end + 1);
      }
      const parsed = JSON.parse(jsonStr);
      tags = parsed.tags || [];
    } catch(e) {
      // JSON truncated or malformed
    }

    allResults.push({name, tags, raw, usage});
  }

  // Print full results
  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║           RESULTADOS DE INDEXACIÓN - 7 FOTOS REALES        ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  for (const r of allResults) {
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("📷 " + r.name);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    if (r.tags.length > 0) {
      console.log("Tags (" + r.tags.length + "):");
      r.tags.forEach((tag, i) => {
        console.log("  " + (i+1) + ". " + tag);
      });
    } else {
      console.log("RAW RESPONSE (JSON no parseado):");
      console.log(r.raw);
    }
    if (r.usage) {
      console.log("\nTokens: prompt=" + r.usage.prompt_tokens + " completion=" + r.usage.completion_tokens + " total=" + r.usage.total_tokens);
    }
    console.log("");
  }

  // Search simulation
  console.log("\n╔══════════════════════════════════════════════════════════════╗");
  console.log("║                    SIMULACIÓN DE BÚSQUEDAS                 ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  const queries = [
    "gorra", "selfie", "barba", "tatuaje", "auriculares", "celular", "teléfono", "iPhone",
    "paseo", "costanera", "parque", "farolas",
    "pesas", "gimnasio", "fitness", "casa", "hogar",
    "comida", "pastel", "carne", "cena",
    "nene", "niño", "alas", "bosque",
    "pileta", "piscina", "hotel", "vacaciones",
    "autopista", "tránsito", "tráfico", "auto", "ruta",
    "exterior", "interior", "persona", "hombre"
  ];

  for (const q of queries) {
    const matches = allResults.filter(r =>
      r.tags.some(tag => tag.toLowerCase().includes(q.toLowerCase()))
    );
    const icon = matches.length > 0 ? "✅" : "❌";
    const fotos = matches.map(m => m.name).join(", ");
    console.log(icon + " \"" + q + "\" → " + matches.length + "/7" + (matches.length > 0 ? " [" + fotos + "]" : ""));
  }
}

run();
