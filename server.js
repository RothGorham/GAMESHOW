const express = require('express');
const cors = require('cors');
const axios = require('axios');
const mongoose = require('mongoose');
const Pergunta = require('./models/Pergunta');

const app = express();
const port = 3000;

app.use(cors());
app.use(express.json());

// ✅ Variáveis para controle
let perguntas = [];
let perguntasUsadas = [];

const OPENROUTER_API_KEY = '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';

// ✅ Conectar ao MongoDB
mongoose.connect('mongodb+srv://24950092:W7e3HGBYuh1X5jps@game.c3vnt2d.mongodb.net/PERGUNTAS?retryWrites=true&w=majority&appName=GAME', {
  useNewUrlParser: true,
  useUnifiedTopology: true
})
.then(async () => {
  console.log("✅ Conectado ao MongoDB com sucesso!");

  perguntasUsadas = [];
  perguntas = [];

  try {
    const todas = await Pergunta.find();
    console.log(`📚 Total de perguntas no banco: ${todas.length}`);
    console.log("🔁 Perguntas usadas resetadas no início do servidor.");
  } catch (err) {
    console.error("❌ Erro ao buscar perguntas:", err);
  }
})
.catch(err => {
  console.error("❌ Erro ao conectar com o MongoDB:", err);
});

// 🔄 Sorteia uma pergunta que ainda não foi usada
app.get('/pergunta', async (req, res) => {
  try {
    const todas = await Pergunta.find();
    const naoUsadas = todas.filter(p => !perguntasUsadas.includes(p._id.toString()));

    if (!naoUsadas.length) {
      return res.status(404).json({ erro: 'Todas as perguntas já foram usadas. Reinicie a partida.' });
    }

    const sorteada = naoUsadas[Math.floor(Math.random() * naoUsadas.length)];

    perguntas = [
      {
        id: sorteada._id.toString(),
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

// ✅ Verifica a resposta do jogador
app.post('/resposta', async (req, res) => {
  const { resposta } = req.body;

  if (!perguntas.length) {
    return res.status(404).json({ correta: false, erro: "Nenhuma pergunta ativa." });
  }
;
  const pergunta = perguntas[0];

  const prompt = `
A resposta correta para a pergunta "${pergunta.pergunta}" é "${pergunta.correta}".
O jogador respondeu: "${resposta}"

Verifique se a resposta do jogador está correta. Se a resposta contiver mais de 2 palavras, considere um erro. porem se tiver erros de acentuação, digitação ou pontuação.

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
      perguntasUsadas.push(pergunta.id);
      perguntas = [];

      const total = await Pergunta.countDocuments();

      if (perguntasUsadas.length >= total) {
        console.log("⚠️ Todas as perguntas foram respondidas! Reiniciando o servidor...");

        setTimeout(() => {
          process.exit(0); // Requer PM2 ou gerenciador de processos
        }, 2000);
      }
    }

    res.json({ correta: acertou });

  } catch (error) {
    console.error("❌ Erro ao consultar IA:", error.message);
    res.status(500).json({ correta: false });
  }
});

// 🧠 Gera dica para pergunta ativa
app.get('/dica', async (req, res) => {
  if (!perguntas.length) {
    return res.status(404).json({ erro: "Nenhuma pergunta ativa para gerar dica." });
  }

  const pergunta = perguntas[0];

  const prompt = `
A pergunta é: "${pergunta.pergunta}"
A resposta correta é: "${pergunta.correta}"

Crie uma dica sutil que ajude o jogador a encontrar a resposta correta. A dica deve ser em forma de pergunta indireta ou sugestiva, como por exemplo: "Já pensou em algo que usamos para medir o tempo?" ou "Que tal lembrar da fórmula da área de um quadrado?"

Atenção:
- NÃO revele a resposta.
- A dica deve ter no máximo 2 frases.
- Seja Grosso com o jogador.

Responda apenas com a dica.
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

    const dica = completion.data?.choices?.[0]?.message?.content?.trim();

    res.json({ dica });

  } catch (error) {
    console.error("❌ Erro ao gerar dica:", error.message);
    res.status(500).json({ erro: "Erro ao gerar dica." });
  }
});

// 🔁 Reinicia o jogo (zera perguntas usadas)
app.post('/reiniciar', async (req, res) => {
  perguntasUsadas = [];
  perguntas = [];

  const todas = await Pergunta.find();
  console.log("♻️ Perguntas reiniciadas manualmente.");
  console.log(`📚 Total de perguntas disponíveis após reinício: ${todas.length}`);

  res.json({ mensagem: 'Partida reiniciada. Perguntas liberadas novamente.' });
});

// 📊 Rota para saber status das perguntas
app.get('/status', async (req, res) => {
  try {
    const total = await Pergunta.countDocuments();
    const usadas = perguntasUsadas.length;
    const restantes = total - usadas;

    res.json({
      totalPerguntas: total,
      perguntasUsadas: usadas,
      perguntasRestantes: restantes
    });
  } catch (err) {
    console.error("❌ Erro ao obter status:", err.message);
    res.status(500).json({ erro: "Erro ao obter status." });
  }
});

// 🚀 Inicia o servidor
app.listen(port, '0.0.0.0', () => {
  console.log(`🚀 Servidor rodando em http://localhost:${port}`);
});
