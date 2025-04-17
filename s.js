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
let reinicializacaoEmAndamento = false;
let ultimaReinicializacao = 0;

const OPENROUTER_API_KEY = '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';

// Função para encerrar o servidor com notificação
const encerrarServidor = async (motivo) => {
  try {
    const mensagem = `🔴 SERVIDOR ENCERRANDO!\nMotivo: ${motivo}\nTempo de atividade: ${Math.floor((new Date() - serverStartTime) / 1000 / 60)} minutos`;
    await sendTelegramMessage(CHAT_ID, mensagem);
    console.log(mensagem);
  } catch (err) {
    console.error("Erro ao enviar notificação de encerramento:", err);
  } finally {
    process.exit(0);
  }
};

// Tratamento de sinais de encerramento
process.on('SIGINT', () => encerrarServidor('Sinal SIGINT recebido (Ctrl+C)'));
process.on('SIGTERM', () => encerrarServidor('Sinal SIGTERM recebido'));
process.on('SIGQUIT', () => encerrarServidor('Sinal SIGQUIT recebido'));

// Tratamento de erros não capturados
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
    encerrarServidor('Erro não tratado detectado');
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

// Função para normalizar texto (remover acentos e converter para minúsculas)
const normalizarTexto = (texto) => {
  return texto
    .toLowerCase()
    .trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
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
    const durationMinutes = (duration / 60000).toFixed(2);
    const log = `${req.method} ${req.originalUrl} ${res.statusCode} ${durationMinutes} minutos`;
    
    // Registrar requisições lentas (mais de 5 segundos = 0.083 minutos)
    if (duration > 5000) {
      console.warn(`⚠️ Requisição lenta: ${log}`);
      sendTelegramMessage(CHAT_ID, `⚠️ Requisição lenta detectada: ${log}`).catch(console.error);
    }
    
    // Log detalhado para debug
    console.log(`📡 Resposta enviada: ${log}`);
    console.log(`📦 Corpo da resposta:`, res.body);
  });
  
  next();
});

// Rota para verificar status do servidor
app.get('/status', (req, res) => {
  res.json({
    status: 'online',
    uptime: Math.floor((new Date() - serverStartTime) / 1000 / 60),
    perguntasAtivas: perguntas.length,
    perguntasUsadas: perguntasUsadas.length
  });
});

// Sorteia uma pergunta
app.get('/pergunta', async (req, res) => {
  try {
    console.log('📝 Recebida requisição para nova pergunta');
    const todas = await Pergunta.find();
    const naoUsadas = todas.filter(p => !perguntasUsadas.includes(p._id.toString()));

    if (!naoUsadas.length) {
      console.log('⚠️ Todas as perguntas já foram usadas');
      return res.status(404).json({ erro: 'Todas as perguntas já foram usadas. Reinicie a partida.' });
    }

    const sorteada = naoUsadas[Math.floor(Math.random() * naoUsadas.length)];
    console.log(`🎲 Pergunta sorteada: ${sorteada.pergunta}`);

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

  // Função para verificar se a resposta está correta, tolerando erros de acentuação
  const verificarResposta = (respostaJogador, respostaCorreta) => {
    // Normaliza ambas as strings (remove acentos, converte para minúsculas, remove espaços extras)
    const respostaJogadorNormalizada = normalizarTexto(respostaJogador);
    const respostaCorretaNormalizada = normalizarTexto(respostaCorreta);
    
    // Verifica se contém mais de 2 palavras
    const palavras = respostaJogadorNormalizada.split(/\s+/).filter(p => p.length > 0);
    if (palavras.length > 2) {
      return false; // Mais de 2 palavras, considerado incorreto conforme regra
    }
    
    // Compara as strings normalizadas
    return respostaJogadorNormalizada === respostaCorretaNormalizada;
  };

  // Criar uma flag para controlar se já respondemos ao cliente
  let respondido = false;
  let tentativas = 0;
  const maxTentativas = 2; // Número máximo de tentativas

  // Função para fazer a requisição à IA ou usar verificação local
  const processarResposta = async () => {
    tentativas++;
    
    try {
      console.log(`Tentativa ${tentativas} de processar resposta...`);
      
      // Primeiro, tentar usar nossa própria validação
      const resultado = verificarResposta(resposta, pergunta.correta);
      const acertou = resultado;
      
      // Se for a primeira tentativa, tentar consultar a IA para casos mais complexos
      if (tentativas === 1) {
        console.log("Tentando confirmação com IA...");
        
        const prompt = `
A resposta correta para a pergunta "${pergunta.pergunta}" é "${pergunta.correta}".
O jogador respondeu: "${resposta}"

Verifique se a resposta do jogador está correta, se tiver erros de acentuação ou pontuação, tudo bem! Mas se a resposta contiver mais de 2 palavras, considere um erro.

Responda apenas com: true (se estiver correta) ou false (se estiver incorreta).
`;
        
        // Criar um AbortController para poder cancelar a requisição se demorar demais
        const controller = new AbortController();
        
        // Timer para cancelar a requisição após 20 segundos
        const timeoutId = setTimeout(() => {
          controller.abort();
          console.warn("⚠️ Requisição à IA cancelada após 20 segundos");
          sendTelegramMessage(CHAT_ID, "⚠️ ALERTA: Requisição à IA cancelada após 20 segundos").catch(console.error);
        }, 20000);

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
            signal: controller.signal,
            timeout: 25000 // Um pouco maior que o AbortController para dar chance ao cancelamento
          });

          // Limpar o timer se a requisição foi bem-sucedida
          clearTimeout(timeoutId);

          const texto = completion.data?.choices?.[0]?.message?.content?.toLowerCase() || '';
          const acertouIA = texto.includes("true");
          
          // Se houver discrepância entre nossa verificação e a IA, registrar
          if (acertou !== acertouIA) {
            console.log(`⚠️ Discrepância na verificação: Nossa função diz ${acertou}, IA diz ${acertouIA}`);
            await sendTelegramMessage(CHAT_ID, 
              `⚠️ DISCREPÂNCIA: Para resposta "${resposta}"\n` +
              `Verificação local: ${acertou ? "CORRETA" : "INCORRETA"}\n` +
              `Verificação IA: ${acertouIA ? "CORRETA" : "INCORRETA"}\n` +
              `Resposta esperada: "${pergunta.correta}"`
            );
          }
          
          // Usamos o resultado da IA se disponível
          console.log(`Usando resultado da IA: ${acertouIA}`);
          
          // Enviar resultado para o Telegram
          await sendTelegramMessage(CHAT_ID, `🎮 RESPOSTA DO JOGADOR: "${resposta}"\n${acertouIA ? '✅ CORRETA!' : '❌ INCORRETA!'}`);
          
          if (acertouIA) {
            perguntasUsadas.push(pergunta.id);
            perguntas = [];

            const total = await Pergunta.countDocuments();

            if (perguntasUsadas.length >= total) {
              try {
                await sendTelegramMessage(CHAT_ID, "⚠️ Todas as perguntas foram respondidas! Reiniciando o servidor...");
                setTimeout(() => {
                  encerrarServidor('Todas as perguntas foram respondidas');
                }, 2000);
              } catch (err) {
                console.error("Falha ao enviar notificação de reinício:", err);
                encerrarServidor('Erro ao reiniciar servidor');
              }
            }
          }
          
          // Só responde se ainda não foi respondido
          if (!respondido) {
            respondido = true;
            res.json({ correta: acertouIA });
          }
          
          return true; // Processamento bem-sucedido
        } catch (iaError) {
          // Se a IA falhar, usamos nossa própria verificação como fallback
          console.error(`❌ Erro ao consultar IA: ${iaError.message}`);
          clearTimeout(timeoutId);
          
          // Se for um erro de timeout, tentaremos novamente
          const isCancelled = iaError.name === 'AbortError' || iaError.code === 'ECONNABORTED' || 
                          (iaError.message && iaError.message.includes('timeout'));
                          
          if (isCancelled && tentativas < maxTentativas) {
            console.log(`🔄 Iniciando nova tentativa...`);
            // Informar o cliente que estamos tentando novamente apenas na primeira falha
            if (tentativas === 1 && !respondido) {
              respondido = true;
              res.json({ 
                aviso: "Estamos processando sua resposta. A IA está demorando mais que o normal, aguarde enquanto tentamos novamente...",
                processando: true 
              });
            }
            return false; // Sinaliza que devemos tentar novamente
          }
          
          // Se não for timeout ou já tentamos o máximo, usamos nossa verificação
          console.log(`Usando verificação local devido a falha da IA: ${resultado}`);
        }
      }
      
      // Se a IA falhou ou é a segunda tentativa, usar nossa própria verificação
      // Enviar resultado para o Telegram
      if (!respondido) {
        await sendTelegramMessage(CHAT_ID, 
          `🎮 RESPOSTA DO JOGADOR: "${resposta}"\n` +
          `${acertou ? '✅ CORRETA!' : '❌ INCORRETA!'}\n` +
          `(Verificação local)`
        );
        
        if (acertou) {
          perguntasUsadas.push(pergunta.id);
          perguntas = [];

          const total = await Pergunta.countDocuments();

          if (perguntasUsadas.length >= total) {
            try {
              await sendTelegramMessage(CHAT_ID, "⚠️ Todas as perguntas foram respondidas! Reiniciando o servidor...");
              setTimeout(() => {
                encerrarServidor('Todas as perguntas foram respondidas');
              }, 2000);
            } catch (err) {
              console.error("Falha ao enviar notificação de reinício:", err);
              encerrarServidor('Erro ao reiniciar servidor');
            }
          }
        }
        
        respondido = true;
        res.json({ 
          correta: acertou,
          verificacao: "local" // Indicar que usamos verificação local
        });
      }
      
      return true; // Processamento concluído
      
    } catch (error) {
      console.error(`❌ Erro ao processar resposta (tentativa ${tentativas}):`, error.message);
      sendTelegramMessage(CHAT_ID, `❌ Erro ao processar resposta (tentativa ${tentativas}): ${error.message}`).catch(console.error);
      
      // Se ainda não atingimos o máximo de tentativas, podemos tentar novamente
      if (tentativas < maxTentativas) {
        console.log(`🔄 Iniciando nova tentativa...`);
        return false; // Sinaliza que devemos tentar novamente
      }
      
      // Se chegamos aqui, já tentamos o máximo de vezes
      // Se ainda não respondemos ao cliente, responder com verificação local
      if (!respondido) {
        respondido = true;
        
        // Usar nossa verificação local como última instância
        const resultado = verificarResposta(resposta, pergunta.correta);
        
        await sendTelegramMessage(CHAT_ID, 
          `🎮 RESPOSTA DO JOGADOR: "${resposta}"\n` +
          `${resultado ? '✅ CORRETA!' : '❌ INCORRETA!'}\n` +
          `(Verificação local de fallback após erros)`
        );
        
        if (resultado) {
          perguntasUsadas.push(pergunta.id);
          perguntas = [];
        }
        
        res.json({ 
          correta: resultado,
          verificacao: "local_fallback"
        });
      }
      
      return true; // Não tentar novamente
    }
  };

  // Primeira chamada à função de processamento
  let resultado = await processarResposta();
  
  // Loop de tentativas se o processamento falhar
  while (!resultado && tentativas < maxTentativas) {
    resultado = await processarResposta();
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

  // Criar uma flag para controlar se já respondemos ao cliente
  let respondido = false;
  let tentativas = 0;
  const maxTentativas = 2; // Número máximo de tentativas

  // Função para fazer a requisição à IA
  const fazerRequisicaoIA = async () => {
    tentativas++;
    
    try {
      console.log(`Tentativa ${tentativas} de gerar dica...`);
      
      // Criar um AbortController para poder cancelar a requisição se demorar demais
      const controller = new AbortController();
      
      // Timer para cancelar a requisição após 20 segundos
      const timeoutId = setTimeout(() => {
        controller.abort();
        console.warn(`⚠️ Requisição à IA para dica cancelada após 20 segundos (tentativa ${tentativas})`);
        sendTelegramMessage(CHAT_ID, `⚠️ ALERTA: Requisição à IA para dica cancelada após 20 segundos (tentativa ${tentativas})`).catch(console.error);
      }, 20000);

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
        signal: controller.signal,
        timeout: 25000 // Um pouco maior que o AbortController para dar chance ao cancelamento
      });

      // Limpar o timer se a requisição foi bem-sucedida
      clearTimeout(timeoutId);

      const dica = completion.data?.choices?.[0]?.message?.content?.trim();
      
      // Enviar dica para o Telegram
      await sendTelegramMessage(CHAT_ID, `💡 DICA SOLICITADA: "${dica}"`);
      
      // Só responde se ainda não foi respondido
      if (!respondido) {
        respondido = true;
        res.json({ dica });
      }

      return true; // Requisição bem-sucedida
    } catch (error) {
      // Verifica se foi um erro de timeout ou abort
      const isCancelled = error.name === 'AbortError' || error.code === 'ECONNABORTED' || 
                          (error.message && error.message.includes('timeout'));
      
      console.error(`❌ Erro ao gerar dica (tentativa ${tentativas}):`, error.message);
      sendTelegramMessage(CHAT_ID, `❌ Erro ao gerar dica (tentativa ${tentativas}): ${error.message}`).catch(console.error);
      
      // Se foi cancelado e ainda não atingimos o máximo de tentativas, podemos tentar novamente
      if (isCancelled && tentativas < maxTentativas) {
        console.log(`🔄 Iniciando nova tentativa para dica...`);
        // Informar o cliente que estamos tentando novamente apenas na primeira falha
        if (tentativas === 1 && !respondido) {
          respondido = true;
          res.json({ 
            aviso: "Estamos processando sua dica. A IA está demorando mais que o normal, aguarde enquanto tentamos novamente...",
            processando: true 
          });
        }
        return false; // Sinaliza que devemos tentar novamente
      }
      
      // Se chegamos aqui, ou não foi timeout ou já tentamos o máximo de vezes
      // Se ainda não respondemos ao cliente, responder com erro
      if (!respondido) {
        respondido = true;
        
        // Se foi erro de timeout, gerar dica criativa baseada na resposta
        if (isCancelled) {
          console.log("⚠️ Gerando dica baseada na resposta após falhas consecutivas");
          
          // Função para gerar dica baseada na resposta
          const gerarDicaCriativa = (pergunta, resposta) => {
            resposta = resposta.toLowerCase().trim();
            // Extrair características da resposta para usar na dica
            const caracteristicas = [];
            
            // Comprimento da palavra
            caracteristicas.push(`tem ${resposta.length} letras`);
            
            // Primeira letra
            caracteristicas.push(`começa com a letra "${resposta[0].toUpperCase()}"`);
            
            // Se contém vogais ou mais consoantes
            const vogais = (resposta.match(/[aeiouáàâãéèêíìîóòôõúùû]/gi) || []).length;
            const consoantes = resposta.length - vogais;
            if (vogais > consoantes) {
              caracteristicas.push("tem mais vogais que consoantes");
            } else if (consoantes > vogais) {
              caracteristicas.push("tem mais consoantes que vogais");
            }
            
            // Se tiver espaço, indica que tem mais de uma palavra
            if (resposta.includes(' ')) {
              const palavras = resposta.split(' ').filter(p => p.length > 0);
              caracteristicas.push(`é composta por ${palavras.length} palavras`);
            }
            
            // Escolher duas características aleatórias para usar na dica
            const caracteristicasEscolhidas = [];
            while (caracteristicasEscolhidas.length < 2 && caracteristicas.length > 0) {
              const indice = Math.floor(Math.random() * caracteristicas.length);
              caracteristicasEscolhidas.push(caracteristicas[indice]);
              caracteristicas.splice(indice, 1);
            }
            
            // Insultos variados para adicionar na dica
            const insultos = [
              "seu cérebro de minhoca",
              "seu idiota",
              "cabeça de vento",
              "zero de QI",
              "seu incompetente",
              "anta destreinada",
              "fracassado mental",
              "jumento digital"
            ];
            
            // Escolher um insulto aleatório
            const insulto = insultos[Math.floor(Math.random() * insultos.length)];
            
            // Formar a dica com uma das características e um insulto
            if (caracteristicasEscolhidas.length === 2) {
              return `A resposta ${caracteristicasEscolhidas[0]}, ${insulto}! E ainda por cima ${caracteristicasEscolhidas[1]}. Consegue acertar agora ou vai continuar provando sua burrice?`;
            } else if (caracteristicasEscolhidas.length === 1) {
              return `Vou te dar uma dica bem óbvia, ${insulto}: a resposta ${caracteristicasEscolhidas[0]}. Se não acertar agora, desista!`;
            } else {
              return `Use esse seu cérebro microscópico, ${insulto}! A resposta é muito mais simples do que você imagina!`;
            }
          };
          
          const dicaCriativa = gerarDicaCriativa(pergunta.pergunta, pergunta.correta);
          
          await sendTelegramMessage(CHAT_ID, 
            `⚠️ DICA AUTOMÁTICA CRIATIVA após falha da IA!\n` +
            `💡 DICA GERADA: "${dicaCriativa}"`
          );
          
          res.json({ 
            dica: dicaCriativa,
            aviso: "Dica gerada automaticamente devido a problemas técnicos com a IA."
          });
        } else {
          res.status(500).json({ erro: "Erro ao gerar dica." });
        }
      }
      
      return true; // Não tentar novamente
    }
  };

  // Primeira chamada à função de requisição
  let resultado = await fazerRequisicaoIA();
  
  // Loop de tentativas se a requisição falhar por timeout
  while (!resultado && tentativas < maxTentativas) {
    resultado = await fazerRequisicaoIA();
  }
});

// Rota para reiniciar o servidor
app.post('/reiniciar', async (req, res) => {
  try {
    // Verificar se já está em processo de reinicialização
    if (reinicializacaoEmAndamento) {
      return res.status(429).json({ 
        erro: "Uma reinicialização já está em andamento. Por favor, aguarde.",
        tempoRestante: Math.max(0, 5 - Math.floor((Date.now() - ultimaReinicializacao) / 1000))
      });
    }

    // Verificar tempo desde a última reinicialização
    const tempoDesdeUltimaReinicializacao = Date.now() - ultimaReinicializacao;
    if (tempoDesdeUltimaReinicializacao < 5000) { // 5 segundos
      return res.status(429).json({ 
        erro: "Aguarde 5 segundos entre as reinicializações.",
        tempoRestante: Math.ceil((5000 - tempoDesdeUltimaReinicializacao) / 1000)
      });
    }

    // Marcar início da reinicialização
    reinicializacaoEmAndamento = true;
    ultimaReinicializacao = Date.now();

    // Notificar início da reinicialização
    await sendTelegramMessage(CHAT_ID, "🔄 Iniciando reinicialização do servidor...");

    // Resetar variáveis
    perguntas = [];
    perguntasUsadas = [];

    // Buscar novas perguntas do banco
    const todas = await Pergunta.find();
    console.log(`📚 Total de perguntas no banco: ${todas.length}`);
    await sendTelegramMessage(CHAT_ID, `📚 Total de perguntas no banco: ${todas.length}`);

    // Marcar fim da reinicialização
    reinicializacaoEmAndamento = false;

    res.json({ 
      mensagem: "Servidor reinicializado com sucesso!",
      totalPerguntas: todas.length
    });
  } catch (err) {
    console.error("❌ Erro ao reiniciar servidor:", err);
    reinicializacaoEmAndamento = false;
    
    try {
      await sendTelegramMessage(CHAT_ID, `❌ Erro ao reiniciar servidor: ${err.message}`);
    } catch (telegramErr) {
      console.error("Falha ao enviar notificação de erro de reinicialização:", telegramErr);
    }
    
    res.status(500).json({ 
      erro: "Erro ao reiniciar servidor.",
      detalhes: err.message
    });
  }
});

// Iniciar o servidor
app.listen(port, () => {
  console.log(`✅ Servidor rodando na porta ${port}`);
});



