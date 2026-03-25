const https = require('https');
const API_KEY = "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";

const PROMPT = `Analizá esta foto y generá todos los tags que sean útiles para buscarla después. Incluí todo lo que veas: personas (género, edad aproximada, ropa, accesorios, pelo), objetos, animales, colores dominantes, lugar (interior/exterior, tipo), clima, momento del día, actividad, emociones, marcas visibles, texto visible, tipo de foto (selfie, paisaje, retrato, etc).
Respondé SOLO con un JSON: {"tags": ["tag1", "tag2", ...]}
Cuantos más tags mejor. Mínimo 15 tags por foto. Todo en español.`;

const PHOTOS = [
  {label: "Selfie con gorra", url: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=300"},
  {label: "Paseo/costanera", url: "https://images.unsplash.com/photo-1476842634003-7dcca8f832de?w=300"},
  {label: "Gym en casa", url: "https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=300"},
  {label: "Comida casera", url: "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=300"},
  {label: "Nene en parque", url: "https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=300"},
  {label: "Pileta hotel", url: "https://images.unsplash.com/photo-1576013551627-0cc20b96c2a7?w=300"},
  {label: "Autopista transito", url: "https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?w=300"},
];

function callGroq(imageUrl) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: "meta-llama/llama-4-scout-17b-16e-instruct",
      messages: [{
        role: "user",
        content: [
          {type: "text", text: PROMPT},
          {type: "image_url", image_url: {url: imageUrl}}
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
          resolve('ERROR: ' + data.substring(0, 200));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function run() {
  for (const photo of PHOTOS) {
    console.log("=== " + photo.label.toUpperCase() + " ===");
    const result = await callGroq(photo.url);
    try {
      const parsed = JSON.parse(result);
      console.log("Tags (" + parsed.tags.length + "):", parsed.tags.join(", "));
    } catch(e) {
      console.log("Raw:", result);
    }
    console.log("");
  }
}

run();
