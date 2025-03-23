const express = require('express');
const cors = require('cors');
const axios = require('axios');
const app = express();
const port = 3000;

app.use(cors());
app.use(express.json());

const perguntas = [
  { id: 1, pergunta: "Qual a capital do Brasil?", correta: "Brasília" },
  { id: 2, pergunta: "Quanto é 2+2?", correta: "4" },
];

// ✅ SUA API KEY DA OPENROUTER
const OPENROUTER_API_KEY = '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';

app.get('/pergunta', (req, res) => {
  const random = perguntas[Math.floor(Math.random() * perguntas.length)];
  res.json(random);
});

app.post('/resposta', async (req, res) => {
  const { id, resposta } = req.body;
  const pergunta = perguntas.find(p => p.id === id);
  if (!pergunta) return res.status(404).json({ correta: false });

  const prompt = `
A resposta correta para a pergunta "${pergunta.pergunta}" é "${pergunta.correta}".
O jogador respondeu: "${resposta}"

Analise se o jogador quis dizer a resposta correta, mesmo com erros de acentuação, digitação ou pontuação.

Responda apenas com: true (se estiver correta) ou false (se estiver incorreta).
`;

  try {
    const completion = await axios.post('https://openrouter.ai/api/v1/chat/completions', {
      model: 'deepseek/deepseek-r1',
      messages: [
        {
          role: 'user',
          content: prompt
        }
      ]
    }, {
      headers: {
        'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'http://localhost', // ou o seu domínio
        'X-Title': 'SeuProjetoRoblox'
      }
    });

    const respostaIA = completion.data.choices[0].message.content.toLowerCase().includes("true");
    res.json({ correta: respostaIA });
  } catch (error) {
    console.error("Erro ao consultar OpenRouter:", error.message);
    res.status(500).json({ correta: false });
  }
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Servidor rodando na porta ${port}`);
});
