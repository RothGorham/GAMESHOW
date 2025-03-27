const express = require('express');
const cors = require('cors');
const axios = require('axios');
const mongoose = require('mongoose');
const Pergunta = require('./models/Pergunta');

const app = express();
const port = 3000;

app.use(cors());
app.use(express.json());

mongoose.connect('mongodb+srv://24950092:W7e3HGBYuh1X5jps@game.c3vnt2d.mongodb.net/PERGUNTAS?retryWrites=true&w=majority&appName=GAME')
  .then(() => console.log("✅ Conectado ao MongoDB"))
  .catch(err => console.error("❌ Erro ao conectar com o MongoDB:", err));

// Variável de pergunta atual
let perguntas = [];

// SUA API KEY
const OPENROUTER_API_KEY = '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';

// 🔄 Sorteia uma pergunta do MongoDB e salva na variável
app.get('/pergunta', async (req, res) => {
  try {
    const todas = await Pergunta.find();
    if (!todas.length) return res.status(404).json({ erro: 'Sem perguntas no banco.' });

    const sorteada = todas[Math.floor(Math.random() * todas.length)];

    // Atualiza a variável no formato antigo
    perguntas = [
      {
        id: 1,
        pergunta: sorteada.pergunta,
        correta: sorteada.correta
      }
    ];

    res.json(perguntas[0]);
  } catch (err) {
    console.error("❌ Erro ao buscar pergunta:", err.message);
    res.status(500).json({ erro: "Erro ao buscar pergunta." });
  }
});

// ✅ Verifica resposta usando a variável perguntas[0]
app.post('/resposta', async (req, res) => {
  const { resposta } = req.body;

  if (!perguntas.length) {
    return res.status(404).json({ correta: false, erro: "Nenhuma pergunta ativa." });
  }

  const pergunta = perguntas[0];

  const prompt = `
A resposta correta para a pergunta "${pergunta.pergunta}" é "${pergunta.correta}".
O jogador respondeu: "${resposta}"

Analise se o jogador quis dizer a resposta correta, mesmo com erros de acentuação, digitação ou pontuação.

Responda apenas com: true (se estiver correta) ou false (se estiver incorreta).
`;

  try {
    const completion = await axios.post('https://openrouter.ai/api/v1/chat/completions', {
      model: 'deepseek/deepseek-chat-v3-0324:free',
      messages: [{ role: 'user', content: prompt }]
    }, {
      headers: {
        'Authorization': `Bearer ${OPENROUTER_API_KEY}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'http://localhost',
        'X-Title': 'SeuProjetoRoblox'
      }
    });

    const texto = completion.data?.choices?.[0]?.message?.content?.toLowerCase() || '';
    const acertou = texto.includes("true");

    if (acertou) {
      perguntas = []; // limpa a pergunta
    }

    res.json({ correta: acertou });

  } catch (error) {
    console.error("❌ Erro ao consultar IA:", error.message);
    res.status(500).json({ correta: false });
  }
});

app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Servidor rodando em http://localhost:${port}`);
});
