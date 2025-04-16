const express = require('express');
const cors = require('cors');
const axios = require('axios');
const mongoose = require('mongoose');
const { Telegraf } = require('telegraf'); // Replace node-telegram-bot-api with telegraf
const Pergunta = require('./models/Pergunta');

const app = express();
const port = 3000;

// Configuração do Telegram com Telegraf
const TELEGRAM_TOKEN = '7924764671:AAF0-GAy21U1yLIG7fVJoMODMrz9LrkmRgk';
const CHAT_ID = '694857164';
const bot = new Telegraf(TELEGRAM_TOKEN);

// Função melhorada para enviar mensagens ao Telegram com garantia de entrega
const sendTelegramMessage = async (chatId, message) => {
  return new Promise((resolve, reject) => {
    try {
      bot.telegram.sendMessage(chatId, message)
        .then(() => {
          console.log(`✅ Mensagem enviada para Telegram: ${message}`);
          resolve(true);
        })
        .catch(error => {
          console.error(`❌ Erro ao enviar mensagem para Telegram: ${error.message}`);
          reject(error);
        });
    } catch (error) {
      console.error(`❌ Erro ao tentar enviar mensagem para Telegram: ${error.message}`);
      reject(error);
    }
  });
};

// Middleware
app.use(cors());
app.use(express.json());

// Variáveis de controle
let perguntas = [];
let perguntasUsadas = [];
let serverStartTime = new Date();
let isServerHealthy = true;

const OPENROUTER_API_KEY = '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';

// Tratamento de erros global
process.on('uncaughtException', async (error) => {
  isServerHealthy = false;
  const errorMsg = `⚠️ ERRO CRÍTICO: O servidor encontrou um erro não tratado: ${error.message}`;
  console.error(errorMsg, error.stack);
  
  try {
    await sendTelegramMessage(CHAT_ID, errorMsg);
    console.log("Notificação de erro crítico enviada.");
  } catch (err) {
    console.error("Falha ao enviar notificação de erro crítico:", err);
  }
  
  // Aguarda 5 segundos para garantir que a mensagem seja enviada antes de encerrar
  setTimeout(() => {
    process.exit(1);
  }, 5000);
});

process.on('unhandledRejection', async (reason, promise) => {
  const errorMsg = `⚠️ AVISO: Promessa rejeitada não tratada: ${reason}`;
  console.error(errorMsg);
  
  try {
    await sendTelegramMessage(CHAT_ID, errorMsg);
  } catch (err) {
    console.error("Falha ao enviar notificação de promessa rejeitada:", err);
  }
});

// Verificação de saúde do servidor a cada 5 minutos
const monitorServerHealth = () => {
  setInterval(async () => {
    try {
      // Verificar conexão com MongoDB
      const isMongoConnected = mongoose.connection.readyState === 1;
      if (!isMongoConnected && isServerHealthy) {
        isServerHealthy = false;
        await sendTelegramMessage(CHAT_ID, "❌ ALERTA: Conexão com MongoDB perdida!");
      } else if (isMongoConnected && !isServerHealthy) {
        isServerHealthy = true;
        await sendTelegramMessage(CHAT_ID, "✅ INFO: Conexão com MongoDB restaurada!");
      }
      
      // Verificar uso de memória
      const memoryUsage = process.memoryUsage();
      const memoryUsageMB = Math.round(memoryUsage.rss / 1024 / 1024);
      if (memoryUsageMB > 500) { // Alerta se usar mais de 500MB
        await sendTelegramMessage(CHAT_ID, `⚠️ ALERTA: Uso de memória alto (${memoryUsageMB}MB)!`);
      }
      
      // Calcular tempo de atividade
      const uptime = Math.floor((new Date() - serverStartTime) / 1000 / 60 / 60); // em horas
      if (uptime % 24 === 0 && uptime > 0) { // Notificar a cada 24 horas
        await sendTelegramMessage(CHAT_ID, `📊 INFO: Servidor ativo há ${uptime} horas.`);
      }
    } catch (err) {
      console.error("❌ Erro no monitoramento de saúde:", err);
      try {
        await sendTelegramMessage(CHAT_ID, `❌ Erro no monitor de saúde: ${err.message}`);
      } catch (telegramErr) {
        console.error("Falha ao enviar notificação de erro de monitoramento:", telegramErr);
      }
    }
  }, 300000); // 5 minutos = 300000ms
};

// Conexão com MongoDB
mongoose.connect('mongodb+srv://24950092:W7e3HGBYuh1X5jps@game.c3vnt2d.mongodb.net/PERGUNTAS?retryWrites=true&w=majority&appName=GAME', {
  useNewUrlParser: true,
  useUnifiedTopology: true
})
.then(async () => {
  console.log("✅ Conectado ao MongoDB com sucesso!");
  try {
    await sendTelegramMessage(CHAT_ID, "✅ Servidor iniciado e conectado ao MongoDB com sucesso!");
    isServerHealthy = true;

    perguntasUsadas = [];
    perguntas = [];

    const todas = await Pergunta.find();
    console.log(`📚 Total de perguntas no banco: ${todas.length}`);
    await sendTelegramMessage(CHAT_ID, `📚 Total de perguntas no banco: ${todas.length}`);
    console.log("🔁 Perguntas usadas resetadas no início do servidor.");
    
    // Iniciar monitoramento de saúde após conexão bem-sucedida
    monitorServerHealth();
  } catch (err) {
    console.error("❌ Erro ao inicializar servidor:", err);
    console.error("❌ Erro ao buscar perguntas:", err);
    try {
      await sendTelegramMessage(CHAT_ID, `❌ Erro ao buscar perguntas: ${err.message}`);
    } catch (telegramErr) {
      console.error("Falha ao enviar notificação de erro inicial:", telegramErr);
    }
  }
})
.catch(async err => {
  console.error("❌ Erro ao conectar com o MongoDB:", err);
  try {
    await sendTelegramMessage(CHAT_ID, `❌ CRÍTICO: Erro ao conectar com o MongoDB: ${err.message}`);
  } catch (telegramErr) {
    console.error("Falha ao enviar notificação de erro de conexão:", telegramErr);
  }
  isServerHealthy = false;
  
  // Tentar reconectar após 30 segundos
  setTimeout(() => {
    console.log("🔄 Tentando reconectar ao MongoDB...");
    mongoose.connect('mongodb+srv://24950092:W7e3HGBYuh1X5jps@game.c3vnt2d.mongodb.net/PERGUNTAS?retryWrites=true&w=majority&appName=GAME', {
      useNewUrlParser: true,
      useUnifiedTopology: true
    }).catch(async reconnectErr => {
      console.error("❌ Falha na reconexão:", reconnectErr);
      try {
        await sendTelegramMessage(CHAT_ID, `❌ CRÍTICO: Falha na reconexão: ${reconnectErr.message}`);
      } catch (telegramErr) {
        console.error("Falha ao enviar notificação de erro de reconexão:", telegramErr);
      }
      process.exit(1); // Encerrar após falha na reconexão
    });
  }, 30000);
});

// Middleware para registrar requisições e capturar erros
app.use((req, res, next) => {
  const start = Date.now();
  
  // Quando a resposta terminar
  res.on('finish', () => {
    const duration = Date.now() - start;
    const durationMinutes = (duration / 60000).toFixed(2); // Converter para minutos com 2 casas decimais
    const log = `${req.method} ${req.originalUrl} ${res.statusCode} ${durationMinutes} minutos`;
    
    // Registrar requisições lentas (mais de 5 segundos = 0.083 minutos)
    if (duration > 5000) {
      console.warn(`⚠️ Requisição lenta: ${log}`);
      sendTelegramMessage(CHAT_ID, `⚠️ Requisição lenta detectada: ${log}`).catch(console.error);
    }
  });
  
  next();
});

// Sorteia uma pergunta
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

    // Enviar resposta automaticamente para o Telegram
    await sendTelegramMessage(CHAT_ID, `📝 NOVA PERGUNTA: "${sorteada.pergunta}"\n🔑 RESPOSTA: "${sorteada.correta}"`);

    res.json(perguntas[0]);
  } catch (err) {
    console.error("❌ Erro ao buscar pergunta:", err.message);
    sendTelegramMessage(CHAT_ID, `❌ Erro ao buscar pergunta: ${err.message}`).catch(console.error);
    res.status(500).json({ erro: "Erro ao buscar pergunta." });
  }
});

// Verifica a resposta
app.post('/resposta', async (req, res) => {
  const { resposta } = req.body;

  if (!perguntas.length) {
    return res.status(404).json({ correta: false, erro: "Nenhuma pergunta ativa." });
  }

  const pergunta = perguntas[0];

  const prompt = `
A resposta correta para a pergunta "${pergunta.pergunta}" é "${pergunta.correta}".
O jogador respondeu: "${resposta}"

Verifique se a resposta do jogador está correta, se tiver erros de acentuação ou pontuação, tudo bem! Mas se a resposta contiver mais de 2 palavras, considere um erro.

Responda apenas com: true (se estiver correta) ou false (se estiver incorreta).
`;

  // Criar uma flag para notificar lentidão
  let notificadoLentidao = false;

  // Timer para detectar lentidão (40 segundos)
  const lentidaoTimer = setTimeout(() => {
    notificadoLentidao = true;
    // Envia resposta ao cliente avisando sobre a lentidão
    res.json({ 
      aviso: "Estamos processando sua resposta. A IA está demorando mais que o normal, por favor aguarde...",
      processando: true 
    });
    
    // Registra no console e notifica via Telegram
    console.warn("⚠️ IA demorando mais de 40 segundos para processar resposta!");
    sendTelegramMessage(CHAT_ID, `⚠️ ALERTA: IA demorando mais de 40 segundos para processar resposta!`).catch(console.error);
  }, 40000);

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
      },
      timeout: 60000 // Aumentado para 60 segundos para dar chance à IA responder
    });

    // Limpa o timer de lentidão
    clearTimeout(lentidaoTimer);

    // Se já enviamos resposta de lentidão, não enviar nova resposta
    if (notificadoLentidao) {
      return;
    }

    const texto = completion.data?.choices?.[0]?.message?.content?.toLowerCase() || '';
    const acertou = texto.includes("true");

    // Enviar resultado para o Telegram
    await sendTelegramMessage(CHAT_ID, `🎮 RESPOSTA DO JOGADOR: "${resposta}"\n${acertou ? '✅ CORRETA!' : '❌ INCORRETA!'}`);

    if (acertou) {
      perguntasUsadas.push(pergunta.id);
      perguntas = [];

      const total = await Pergunta.countDocuments();

      if (perguntasUsadas.length >= total) {
        try {
          await sendTelegramMessage(CHAT_ID, "⚠️ Todas as perguntas foram respondidas! Reiniciando o servidor...");
          setTimeout(() => {
            process.exit(0);
          }, 2000);
        } catch (err) {
          console.error("Falha ao enviar notificação de reinício:", err);
          process.exit(0);
        }
      }
    }

    res.json({ correta: acertou });

  } catch (error) {
    // Limpa o timer de lentidão
    clearTimeout(lentidaoTimer);
    
    // Se já enviamos resposta de lentidão, não enviar nova resposta de erro
    if (notificadoLentidao) {
      return;
    }
    
    console.error("❌ Erro ao consultar IA:", error.message);
    sendTelegramMessage(CHAT_ID, `❌ Erro ao consultar IA: ${error.message}`).catch(console.error);
    res.status(500).json({ correta: false, erro: "Erro ao processar resposta." });
  }
});

// Gera dica ofensiva
app.get('/dica', async (req, res) => {
  if (!perguntas.length) {
    return res.status(404).json({ erro: "Nenhuma pergunta ativa para gerar dica." });
  }

  const pergunta = perguntas[0];

  const prompt = `
A pergunta é: "${pergunta.pergunta}"
A resposta correta é: "${pergunta.correta}"

Crie uma dica que ajude o jogador a encontrar a resposta correta. Porém seja o mais grosso possível, ofenda o jogador, tire sarro da cara dele. A dica deve ter no máximo 2 frases e ser muito grosseira.

Atenção:
- NÃO revele a resposta.
- A dica deve ter no máximo 2 frases.
- Seja Muito Grosso com o jogador.
- Nunca fale a mesma dica duas vezes seguidas.

Responda apenas com a dica.
`;

  // Criar uma flag para notificar lentidão
  let notificadoLentidao = false;

  // Timer para detectar lentidão (40 segundos)  
  const lentidaoTimer = setTimeout(() => {
    notificadoLentidao = true;
    // Envia resposta ao cliente avisando sobre a lentidão
    res.json({ 
      aviso: "Estamos processando sua dica. A IA está demorando mais que o normal, por favor aguarde...",
      processando: true 
    });
    
    // Registra no console e notifica via Telegram
    console.warn("⚠️ IA demorando mais de 40 segundos para gerar dica!");
    sendTelegramMessage(CHAT_ID, `⚠️ ALERTA: IA demorando mais de 40 segundos para gerar dica!`).catch(console.error);
  }, 40000);

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
      },
      timeout: 60000 // Aumentado para 60 segundos para dar chance à IA responder
    });

    // Limpa o timer de lentidão
    clearTimeout(lentidaoTimer);

    // Se já enviamos resposta de lentidão, não enviar nova resposta
    if (notificadoLentidao) {
      return;
    }

    const dica = completion.data?.choices?.[0]?.message?.content?.trim();
    
    // Enviar dica para o Telegram
    await sendTelegramMessage(CHAT_ID, `💡 DICA SOLICITADA: "${dica}"`);
    
    res.json({ dica });

  } catch (error) {
    // Limpa o timer de lentidão
    clearTimeout(lentidaoTimer);
    
    // Se já enviamos resposta de lentidão, não enviar nova resposta de erro
    if (notificadoLentidao) {
      return;
    }
    
    console.error("❌ Erro ao gerar dica:", error.message);
    sendTelegramMessage(CHAT_ID, `❌ Erro ao gerar dica: ${error.message}`).catch(console.error);
    res.status(500).json({ erro: "Erro ao gerar dica." });
  }
});

// Rota protegida por senha para visualizar a resposta atual
app.get('/admin/resposta', async (req, res) => {
  const { senha } = req.query;
  
  // Senha simples para proteger a rota
  if (senha !== 'admin123') {
    return res.status(401).json({ erro: 'Acesso negado. Senha incorreta.' });
  }
  
  if (!perguntas.length) {
    return res.status(404).json({ erro: "Nenhuma pergunta ativa." });
  }
  
  try {
    await sendTelegramMessage(CHAT_ID, `⚠️ ALERTA: Alguém acessou a resposta via painel admin!`);
    
    res.json({
      pergunta: perguntas[0].pergunta,
      resposta: perguntas[0].correta
    });
  } catch (err) {
    console.error("❌ Erro ao acessar resposta:", err.message);
    res.status(500).json({ erro: "Erro ao acessar resposta." });
  }
});

// Reinicia o jogo
app.post('/reiniciar', async (req, res) => {
  perguntasUsadas = [];
  perguntas = [];

  const todas = await Pergunta.find();
  console.log("♻️ Perguntas reiniciadas manualmente.");
  try {
    await sendTelegramMessage(CHAT_ID, `♻️ Jogo reiniciado manualmente. Perguntas disponíveis: ${todas.length}`);
  } catch (err) {
    console.error("Falha ao enviar notificação de reinício manual:", err);
  }

  res.json({ mensagem: 'Partida reiniciada. Perguntas liberadas novamente.' });
});

// Status do jogo
app.get('/status', async (req, res) => {
  try {
    const total = await Pergunta.countDocuments();
    const usadas = perguntasUsadas.length;
    const restantes = total - usadas;
    
    // Adicionar informações de saúde do servidor
    const uptime = Math.floor((new Date() - serverStartTime) / 1000 / 60); // em minutos
    const memoryUsage = Math.round(process.memoryUsage().rss / 1024 / 1024); // em MB

    try {
      await sendTelegramMessage(CHAT_ID, `📊 STATUS: ${usadas}/${total} perguntas usadas. Restantes: ${restantes}`);
    } catch (err) {
      console.error("Falha ao enviar notificação de status:", err);
    }

    res.json({
      totalPerguntas: total,
      perguntasUsadas: usadas,
      perguntasRestantes: restantes,
      serverHealth: {
        uptime: `${uptime} minutos`,
        memory: `${memoryUsage} MB`,
        mongoConnection: mongoose.connection.readyState === 1 ? 'Conectado' : 'Desconectado'
      }
    });
  } catch (err) {
    console.error("❌ Erro ao obter status:", err.message);
    sendTelegramMessage(CHAT_ID, `❌ Erro ao obter status: ${err.message}`).catch(console.error);
    res.status(500).json({ erro: "Erro ao obter status." });
  }
});

// Rota simples para verificação de saúde
app.get('/health', (req, res) => {
  const mongoStatus = mongoose.connection.readyState === 1 ? 'connected' : 'disconnected';
  
  if (mongoStatus === 'connected' && isServerHealthy) {
    res.status(200).json({ 
      status: 'ok',
      uptime: `${Math.floor((new Date() - serverStartTime) / 1000 / 60)} minutos`,
      mongo: mongoStatus
    });
  } else {
    res.status(503).json({ 
      status: 'unhealthy',
      uptime: `${Math.floor((new Date() - serverStartTime) / 1000 / 60)} minutos`,
      mongo: mongoStatus
    });
  }
});

// Tratamento de erros para rotas não encontradas
app.use((req, res) => {
  res.status(404).json({ erro: 'Rota não encontrada' });
});

// Tratamento global de erros
app.use(async (err, req, res, next) => {
  const errorMsg = `❌ Erro interno do servidor: ${err.message}`;
  console.error(errorMsg);
  
  try {
    await sendTelegramMessage(CHAT_ID, errorMsg);
  } catch (telegramErr) {
    console.error("Falha ao enviar notificação de erro interno:", telegramErr);
  }
  
  res.status(500).json({ erro: 'Erro interno do servidor' });
});

// Inicia o servidor
const server = app.listen(port, '0.0.0.0', async () => {
  console.log(`🚀 Servidor rodando em http://localhost:${port}`);
  try {
    await sendTelegramMessage(CHAT_ID, `🚀 Servidor rodando em http://localhost:${port}`);
  } catch (err) {
    console.error("Falha ao enviar notificação de inicialização:", err);
  }
});

// Flag para evitar envios duplicados na finalização
let isShuttingDown = false;

// Tratamento para desligamento gracioso
const gracefulShutdown = async (signal) => {
  if (isShuttingDown) {
    console.log("Processo de desligamento já em andamento, ignorando sinal repetido.");
    return;
  }
  
  isShuttingDown = true;
  console.log(`⚠️ Sinal ${signal} recebido. Iniciando encerramento...`);
  
  try {
    // Tentar enviar a notificação primeiro
    console.log("Enviando notificação de encerramento para Telegram...");
    await sendTelegramMessage(CHAT_ID, `⚠️ Servidor sendo encerrado (sinal ${signal})`);
    console.log("✅ Notificação de encerramento enviada com sucesso!");
  } catch (err) {
    console.error("❌ Falha ao enviar notificação de encerramento:", err);
  }
  
  // Agora proceder com o encerramento
  console.log("Fechando servidor HTTP...");
  server.close(async () => {
    console.log('Servidor HTTP fechado.');
    
    // Fecha a conexão com MongoDB
    try {
      await mongoose.connection.close();
      console.log('Conexão MongoDB fechada.');
      try {
        await sendTelegramMessage(CHAT_ID, `📴 Servidor encerrado corretamente.`);
        console.log("✅ Notificação final enviada com sucesso!");
      } catch (err) {
        console.error("❌ Falha ao enviar notificação final:", err);
      }
      process.exit(0);
    } catch (err) {
      console.error('Erro ao fechar conexão MongoDB:', err);
      try {
        await sendTelegramMessage(CHAT_ID, `❌ Erro ao encerrar servidor: ${err.message}`);
      } catch (telegramErr) {
        console.error("Falha ao enviar notificação de erro de encerramento:", telegramErr);
      }
      process.exit(1);
    }
  });
  
  // Força o encerramento após 10 segundos se não conseguir desligar corretamente
  setTimeout(() => {
    console.error('Timeout de desligamento gracioso. Forçando encerramento.');
    process.exit(1);
  }, 10000);
};

// Captura sinais de encerramento de forma síncrona primeiro
process.on('SIGTERM', () => {
  console.log("SIGTERM recebido");
  gracefulShutdown('SIGTERM');
});

process.on('SIGINT', () => {
  console.log("SIGINT recebido (Ctrl+C)");
  gracefulShutdown('SIGINT');
});

// Para dar tempo de mandar a msg para o telegram depois do Ctrl+C
process.stdin.resume();
