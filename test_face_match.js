const https = require('https');
const API_KEY = "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";

function callGroq(url1, url2) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: "meta-llama/llama-4-scout-17b-16e-instruct",
      messages: [{
        role: "user",
        content: [
          {type: "text", text: "Son la misma persona en estas dos fotos? Responde solo con JSON: {\"match\": true} o {\"match\": false}"},
          {type: "image_url", image_url: {url: url1}},
          {type: "image_url", image_url: {url: url2}}
        ]
      }],
      max_tokens: 50,
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
          resolve(json.choices[0].message.content);
        } catch(e) { resolve('ERROR: ' + data.substring(0, 200)); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function run() {
  // Test 1: Same person (same photo different crop)
  console.log("Test 1: Misma persona (dos fotos similares)");
  let r = await callGroq(
    "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200",
    "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=300"
  );
  console.log("  Resultado: " + r);

  // Test 2: Different people
  console.log("\nTest 2: Personas distintas");
  r = await callGroq(
    "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200",
    "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200"
  );
  console.log("  Resultado: " + r);

  // Test 3: Man vs woman
  console.log("\nTest 3: Hombre vs mujer");
  r = await callGroq(
    "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200",
    "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200"
  );
  console.log("  Resultado: " + r);
}

run();
