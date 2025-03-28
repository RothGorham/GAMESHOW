const mongoose = require('mongoose');

const perguntaSchema = new mongoose.Schema({
  pergunta: String,
  correta: String
});

module.exports = mongoose.model('Pergunta', perguntaSchema, 'GAME'); // 'GAME' é o nome da coleção no banco
