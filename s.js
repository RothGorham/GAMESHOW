const express = require('express');
const cors = require('cors');
const axios = require('axios');
const mongoose = require('mongoose');
const { Telegraf } = require('telegraf'); // Replace node-telegram-bot-api with telegraf
const bcrypt = require('bcryptjs');
const Aluno = require('./models/Aluno');

const app = express();
const port = process.env.PORT || 3000;

// Configuração do Telegram com Telegraf
const TELEGRAM_TOKEN = '7924764671:AAF0-GAy21U1yLIG7fVJoMODMrz9LrkmRgk';
const CHAT_ID = '694857164';
const bot = new Telegraf(TELEGRAM_TOKEN);

// Inicializar o bot
bot.launch()
  .then(() => {
    console.log('🤖 Bot do Telegram inicializado com sucesso!');
    sendTelegramMessage(CHAT_ID, '🤖 Bot do Telegram inicializado com sucesso!')
      .catch(err => console.error('Erro ao enviar mensagem de inicialização:', err));
  })
  .catch(err => {
    console.error('❌ Erro ao inicializar bot do Telegram:', err);
  });

// Enable graceful stop
process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));

// Schema para estatísticas dos alunos
const estatisticasSchema = new mongoose.Schema({
    acertos: { type: Number, required: true },
    erros: { type: Number, required: true },
    ajudas: { type: Number, required: true },
    pulos: { type: Number, required: true },
    dinheiroFinal: { type: Number, required: true },
    data: { type: Date, required: true }
}, { _id: false });

// Schema para usuários (alunos)
const usuarioSchema = new mongoose.Schema({
    nome: { 
        type: String,
        required: true
    },
    cpf: { 
        type: String, 
        required: true, 
        unique: true,
        validate: {
            validator: function(v) {
                return /^\d{11}$/.test(v);
            },
            message: props => `${props.value} não é um CPF válido!`
        }
    },
    senha: { 
        type: String, 
        required: true,
        minlength: 6
    },
    estatisticas: [estatisticasSchema],
    dataCadastro: { 
        type: Date, 
        default: Date.now 
    }
}, { collection: 'usuarios' });

// Schema para perguntas
const perguntaSchema = new mongoose.Schema({
    pergunta: String,
    correta: String
}, { collection: 'GAME' });

// Conexões com MongoDB
const alunosConnection = mongoose.createConnection('mongodb+srv://24950092:W7e3HGBYuh1X5jps@game.c3vnt2d.mongodb.net/ALUNOS?retryWrites=true&w=majority&appName=GAME');
const perguntasConnection = mongoose.createConnection('mongodb+srv://24950092:W7e3HGBYuh1X5jps@game.c3vnt2d.mongodb.net/PERGUNTAS?retryWrites=true&w=majority&appName=GAME');

// Modelos
const Usuario = alunosConnection.model('Usuario', usuarioSchema);
const Pergunta = perguntasConnection.model('Pergunta', perguntaSchema);

// Função para enviar mensagem para o Telegram
async function sendTelegramMessage(chatId, message) {
  console.log('📤 Tentando enviar mensagem para o Telegram:', message);
  
  try {
    const result = await bot.telegram.sendMessage(chatId, message, { parse_mode: 'HTML' });
    console.log('✅ Mensagem enviada com sucesso:', result.message_id);
    return result;
  } catch (error) {
    console.error('❌ Erro ao enviar mensagem para o Telegram:', error.message);
    
    // Tentar novamente após 5 segundos
    console.log('🔄 Tentando enviar novamente em 5 segundos...');
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    try {
      const retryResult = await bot.telegram.sendMessage(chatId, message, { parse_mode: 'HTML' });
      console.log('✅ Mensagem enviada com sucesso na segunda tentativa:', retryResult.message_id);
      return retryResult;
    } catch (retryError) {
      console.error('❌ Erro na segunda tentativa de envio:', retryError.message);
      throw retryError;
    }
  }
}

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
    .toLowerCase() // Converte para minúsculas
    .trim() // Remove espaços no início e fim
    .normalize("NFD") // Normaliza caracteres Unicode
    .replace(/[\u0300-\u036f]/g, "") // Remove acentos
    .replace(/[^a-z0-9\s]/g, "") // Remove caracteres especiais, mantém apenas letras, números e espaços
    .replace(/\s+/g, " "); // Substitui múltiplos espaços por um único espaço
};

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

  // Criar uma flag para controlar se já respondemos ao cliente
  let respondido = false;
  let tentativas = 0;
  const maxTentativas = 2; // Número máximo de tentativas

  // Função para fazer a requisição à IA
  const processarResposta = async () => {
    tentativas++;
    
    try {
      console.log(`Tentativa ${tentativas} de processar resposta...`);
      
      const prompt = `
A resposta correta para a pergunta "${pergunta.pergunta}" é "${pergunta.correta}".
O jogador respondeu: "${resposta}"

IMPORTANTE: Ignore diferenças de maiúsculas/minúsculas e acentuação.
Por exemplo:
- "FE" é igual a "fe" ou "Fe" ou "fE"
- "João" é igual a "joao" ou "JOAO"
- "café" é igual a "cafe" ou "CAFE"

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
        timeout: 25000
      });

      // Limpar o timer se a requisição foi bem-sucedida
      clearTimeout(timeoutId);

      const texto = completion.data?.choices?.[0]?.message?.content?.toLowerCase() || '';
      const acertou = texto.includes("true");
      
      // Enviar resultado para o Telegram
      await sendTelegramMessage(CHAT_ID, 
        `🎮 RESPOSTA DO JOGADOR: "${resposta}"\n` +
        `${acertou ? '✅ CORRETA!' : '❌ INCORRETA!'}\n` +
        `Resposta esperada: "${pergunta.correta}"`
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

      // Só responde se ainda não foi respondido
      if (!respondido) {
        respondido = true;
        res.json({ correta: acertou });
      }
      
      return true; // Processamento bem-sucedido

    } catch (error) {
      console.error(`❌ Erro ao processar resposta (tentativa ${tentativas}):`, error.message);
      
      // Se for um erro de timeout, tentaremos novamente
      const isCancelled = error.name === 'AbortError' || error.code === 'ECONNABORTED' || 
                       (error.message && error.message.includes('timeout'));
                       
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
      
      // Se chegamos aqui, já tentamos o máximo de vezes
      if (!respondido) {
        respondido = true;
        res.status(500).json({ erro: "Erro ao verificar resposta." });
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

// Rota para gerar mensagem via IA
app.post('/gerar-mensagem', async (req, res) => {
    try {
        const { tipo } = req.body;
        let mensagem = "";

        if (tipo === "recusar") {
            const respostasOfensivas = [
                "Tá certo... melhor não passar vergonha mesmo.",
                "Decisão sábia. Com esse desempenho, nem o sistema te aceita.",
                "Eu também teria vergonha de salvar esse fracasso.",
                "Evitar o banco foi a única coisa inteligente que você fez hoje.",
                "Você jogou ou foi só um surto coletivo?"
            ];
            mensagem = respostasOfensivas[Math.floor(Math.random() * respostasOfensivas.length)];
        } else if (tipo === "credenciais_invalidas") {
            const respostasCredenciais = [
                "Não sabe nem digitar as próprias credenciais? Impressionante.",
                "CPF ou senha incorretos. Tente usar o cérebro dessa vez.",
                "Errou as credenciais? Deve ser difícil mesmo lembrar números.",
                "Credenciais erradas. Mas com esse QI, não me surpreende."
            ];
            mensagem = respostasCredenciais[Math.floor(Math.random() * respostasCredenciais.length)];
        }

        res.json({ mensagem });
    } catch (err) {
        console.error("Erro ao gerar mensagem:", err);
        res.status(500).json({ erro: "Erro ao gerar mensagem" });
    }
});

// Rota para salvar estatísticas
app.post('/salvar-estatisticas', async (req, res) => {
    try {
        const { cpf, senha, estatisticas } = req.body;
        
        if (!cpf || !senha || !estatisticas) {
            return res.json({
                sucesso: false,
                mensagem: "Dados incompletos"
            });
        }

        const aluno = await Aluno.findOne({ cpf: cpf.replace(/[^\d]/g, '') });
        
        if (!aluno) {
            return res.json({
                sucesso: false,
                mensagem: "Aluno não encontrado"
            });
        }

        const senhaCorreta = await aluno.verificarSenha(senha);
        if (!senhaCorreta) {
            return res.json({
                sucesso: false,
                mensagem: "Senha incorreta"
            });
        }

        aluno.estatisticas.push({
            ...estatisticas,
            data: new Date()
        });

        await aluno.save();
        
        return res.json({
            sucesso: true,
            mensagem: "Estatísticas salvas com sucesso"
        });

    } catch (error) {
        console.error("Erro ao salvar estatísticas:", error);
        return res.json({
            sucesso: false,
            mensagem: "Erro ao salvar estatísticas"
        });
    }
});

// Rota para verificar CPF
app.post('/verificar-cpf', async (req, res) => {
    try {
        const { cpf } = req.body;

        if (!cpf || cpf.replace(/[^\d]/g, '').length !== 11) {
            return res.json({ 
                sucesso: false, 
                mensagem: "CPF inválido" 
            });
        }

        const aluno = await Aluno.findOne({ cpf: cpf.replace(/[^\d]/g, '') });

        if (aluno) {
            return res.json({ 
                sucesso: true, 
                mensagem: "CPF encontrado",
                nome: aluno.nome
            });
        } else {
            return res.json({ 
                sucesso: false, 
                mensagem: "CPF não encontrado" 
            });
        }

    } catch (error) {
        console.error("Erro ao verificar CPF:", error);
        return res.json({ 
            sucesso: false, 
            mensagem: "Erro ao verificar CPF" 
        });
    }
});

// Rota para verificar credenciais
app.post('/verificar-aluno', async (req, res) => {
    try {
        const { cpf, senha } = req.body;

        if (!cpf || !senha) {
            return res.json({ 
                sucesso: false, 
                mensagem: "CPF e senha são obrigatórios" 
            });
        }

        const aluno = await Aluno.findOne({ cpf: cpf.replace(/[^\d]/g, '') });

        if (!aluno) {
            return res.json({ 
                sucesso: false, 
                mensagem: "CPF não encontrado" 
            });
        }

        const senhaCorreta = await aluno.verificarSenha(senha);
        if (!senhaCorreta) {
            return res.json({ 
                sucesso: false, 
                mensagem: "Senha incorreta" 
            });
        }

        return res.json({ 
            sucesso: true, 
            mensagem: "Login realizado com sucesso",
            nome: aluno.nome
        });

    } catch (error) {
        console.error("Erro ao verificar credenciais:", error);
        return res.json({ 
            sucesso: false, 
            mensagem: "Erro ao verificar credenciais" 
        });
    }
});

// Inicializar servidor após conectar aos bancos
Promise.all([
    alunosConnection.asPromise(),
    perguntasConnection.asPromise()
]).then(async () => {
    console.log("✅ Conectado aos bancos de dados com sucesso!");
    
    try {
        // Verificar conexão com banco de ALUNOS
        const totalAlunos = await Usuario.countDocuments();
        console.log(`👥 Total de alunos cadastrados: ${totalAlunos}`);
        
        // Verificar conexão com banco de PERGUNTAS
        const totalPerguntas = await Pergunta.countDocuments();
        console.log(`📚 Total de perguntas no banco: ${totalPerguntas}`);
        
        await sendTelegramMessage(CHAT_ID, 
            `✅ Servidor iniciado!\n` +
            `👥 Alunos cadastrados: ${totalAlunos}\n` +
            `📚 Perguntas disponíveis: ${totalPerguntas}`
        );
        
        // Resetar controles de perguntas
        perguntasUsadas = [];
        perguntas = [];
        
        // Iniciar o servidor HTTP
        app.listen(port, () => {
            console.log(`🚀 Servidor rodando na porta ${port}`);
        });
    } catch (err) {
        console.error("❌ Erro ao inicializar servidor:", err);
        process.exit(1);
    }
}).catch(err => {
    console.error("❌ Erro ao conectar aos bancos de dados:", err);
    process.exit(1);
});



