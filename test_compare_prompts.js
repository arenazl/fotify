const https = require('https');
const fs = require('fs');
const path = require('path');

const API_KEY = "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";

const PROMPT_SIMPLE = `Analizá esta foto y generá los 10 tags más importantes para poder encontrarla o agruparla en una búsqueda. Solo respondé con un JSON: {"tags": ["tag1", ...]}`;

const PROMPT_DETALLADO = `Analizá esta foto y generá todos los tags que sean útiles para buscarla después. Incluí todo lo que veas: personas (género, edad aproximada, ropa, accesorios, pelo, barba), objetos, animales, colores dominantes, lugar (interior/exterior, tipo), clima, momento del día, actividad, emociones, marcas visibles, texto visible, tipo de foto (selfie, paisaje, retrato, etc).
Respondé SOLO con un JSON: {"tags": ["tag1", "tag2", ...]}
Máximo 10 tags. Los más relevantes. Todo en español.`;

const PHOTO_DIR = path.join(__dirname, 'Fotify', 'fotos');
const PHOTO_NAMES = [
  "Selfie con gorra",
  "Costanera/paseo",
  "Pesas en casa",
  "Pastel de papa",
  "Nene con alas",
  "Pileta hotel",
  "Autopista transito"
];

function callGroq(base64, prompt) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: "meta-llama/llama-4-scout-17b-16e-instruct",
      messages: [{
        role: "user",
        content: [
          {type: "text", text: prompt},
          {type: "image_url", image_url: {url: "data:image/jpeg;base64," + base64}}
        ]
      }],
      max_tokens: 300,
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
          let jsonStr = content;
          const s = content.indexOf('{'), e = content.lastIndexOf('}');
          if (s >= 0 && e > s) jsonStr = content.substring(s, e + 1);
          const parsed = JSON.parse(jsonStr);
          resolve(parsed.tags || []);
        } catch(err) { resolve([]); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function run() {
  const files = fs.readdirSync(PHOTO_DIR).filter(f => f.endsWith('.jpeg'));

  for (let i = 0; i < files.length; i++) {
    const base64 = fs.readFileSync(path.join(PHOTO_DIR, files[i])).toString('base64');
    const name = PHOTO_NAMES[i] || files[i];

    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("FOTO: " + name);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    const tagsSimple = await callGroq(base64, PROMPT_SIMPLE);
    console.log("SIMPLE:    " + tagsSimple.join(", "));

    const tagsDetallado = await callGroq(base64, PROMPT_DETALLADO);
    console.log("DETALLADO: " + tagsDetallado.join(", "));

    // What's in DETALLADO that SIMPLE misses
    const onlyDetallado = tagsDetallado.filter(t => !tagsSimple.some(s => s.toLowerCase() === t.toLowerCase()));
    const onlySimple = tagsSimple.filter(t => !tagsDetallado.some(s => s.toLowerCase() === t.toLowerCase()));
    if (onlyDetallado.length > 0) console.log("SOLO DETALLADO: " + onlyDetallado.join(", "));
    if (onlySimple.length > 0) console.log("SOLO SIMPLE:    " + onlySimple.join(", "));
    console.log("");
  }
}

run();
