-- Serviços
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Comunicacao cliente-servidor
local remote = Instance.new("RemoteEvent")
remote.Name = "NotificarJogador"
remote.Parent = ReplicatedStorage

-- Debug function
local function debugLog(message)
	print("🔍 [DEBUG]: " .. message)
end

-- Sons no ReplicatedStorage
local function criarSons()
	debugLog("Criando sons...")
	local somMensagem = Instance.new("Sound")
	somMensagem.Name = "SomMensagem"
	somMensagem.SoundId = "rbxassetid://115672426899732"
	somMensagem.Volume = 0.5
	somMensagem.Parent = ReplicatedStorage

	local somAcerto = Instance.new("Sound")
	somAcerto.Name = "somAcerto"
	somAcerto.SoundId = "rbxassetid://109582532086060"
	somAcerto.Volume = 0.5
	somAcerto.Parent = ReplicatedStorage

	local somErro = Instance.new("Sound")
	somErro.Name = "SomErro"
	somErro.SoundId = "rbxassetid://124105429067328"
	somErro.Volume = 0.5
	somErro.Parent = ReplicatedStorage
end

criarSons()

-- sem isso nao roda preciso do ngrok ~sempre lembrar~
local BASE_URL = "https://f4fa-179-153-34-87.ngrok-free.app"

-- Rotas específicas
local PERGUNTA_URL = BASE_URL .. "/pergunta"
local RESPOSTA_URL = BASE_URL .. "/resposta"
local DICA_URL = BASE_URL .. "/dica"
local REINICIAR_URL = BASE_URL .. "/reiniciar"


-- Tabelas
local perguntasAtuais = {}
local jogadorEmEspera = {}
local debitos = {}
local debitosAjuda = {}
local debitosErro = {}
local debitosPulo = {}
local respostasTemporarias = {} -- Armazena respostas aguardando confirmação
local jogadorEsperandoConfirmacao = {} -- Jogadores esperando confirmação
local jogadorTerminouIntroducao = {} -- Controle de jogadores que terminaram a introdução
local tentativasCPF = {} -- Contador de tentativas de CPF
local tentativasSenha = {} -- Contador de tentativas de senha
local maxTentativas = 3 -- Número máximo de tentativas

-- Tabela de respostas ofensivas para quando o jogador não quer salvar
local respostasOfensivas = {
	"Tá certo… melhor não passar vergonha mesmo.",
	"Decisão sábia. Com esse desempenho, nem o sistema te aceita.",
	"Eu também teria vergonha de salvar esse fracasso.",
	"Evitar o banco foi a única coisa inteligente que você fez hoje.",
	"Você jogou ou foi só um surto coletivo?"
}

-- Global state management for statistics saving
local EstadoSalvamento = {
	jogadores = {}, -- Table to track saving state per player

	iniciar = function(self, player)
		self.jogadores[player.UserId] = {
			esperandoCPF = false,
			cpfDigitado = nil,
			tentativasCPF = 0,
			tentativasSenha = 0
		}
	end,

	limpar = function(self, player)
		self.jogadores[player.UserId] = nil
	end
}

-- Atualizar dinheiro
local function atualizarDinheiro(player, novoValor)
	player:SetAttribute("Dinheiro", novoValor)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local dinheiroValor = leaderstats:FindFirstChild("Dinheiro")
		if dinheiroValor then
			dinheiroValor.Value = novoValor
		end
	end
end

-- Função para verificar credenciais com o servidor
local function verificarCredenciais(cpf, senha)
	local success, response = pcall(function()
		return HttpService:PostAsync(
			BASE_URL .. "/verificar-aluno",
			HttpService:JSONEncode({
				cpf = cpf,
				senha = senha
			}),
			Enum.HttpContentType.ApplicationJson
		)
	end)

	if success then
		return HttpService:JSONDecode(response)
	else
		return { sucesso = false, mensagem = "Erro ao verificar credenciais" }
	end
end

-- Improved statistics display function
local function exibirEstatisticasFinais(player)
	local acertos = player:GetAttribute("Acertos") or 0
	local erros = player:GetAttribute("Erros") or 0
	local ajudas = player:GetAttribute("Ajuda") or 0
	local pulos = player:GetAttribute("Pulos") or 0
	local dinheiro = player:GetAttribute("Dinheiro") or 0

	-- Calculate actual expenses
	local gastoErro = debitosErro[player.UserId] or 0
	local gastoAjuda = debitosAjuda[player.UserId] or 0
	local gastoPulo = debitosPulo[player.UserId] or 0
	local totalGasto = gastoErro + gastoAjuda + gastoPulo

	-- Format currency values
	local function formatarMoeda(valor)
		return string.format("R$ %d", valor)
	end

	-- Build detailed statistics message
	local mensagem = string.format([[
📊 RESUMO FINAL 📊
✅ Acertos: %d | ❌ Erros: %d
💡 Dicas: %d | 🔄 Pulos: %d

[Resultado]: 💰 BALANÇO FINANCEIRO 💰
Total ganho: %s
Total gasto: %s
└─ Erros: %s
└─ Dicas: %s
└─ Pulos: %s

[Resultado]: 💵 SALDO FINAL: %s 💵]], 
		acertos, erros, ajudas, pulos,
		formatarMoeda(dinheiro + totalGasto),
		formatarMoeda(totalGasto),
		formatarMoeda(gastoErro),
		formatarMoeda(gastoAjuda),
		formatarMoeda(gastoPulo),
		formatarMoeda(dinheiro)
	)

	remote:FireClient(player, "Resultado", mensagem)

	-- Initialize saving state
	EstadoSalvamento:iniciar(player)

	task.wait(2)
	remote:FireClient(player, "Resultado", "Deseja salvar suas estatísticas? Digite 'sim!' para salvar ou 'não!' para encerrar.")

	-- Handle player response
	local connection
	connection = player.Chatted:Connect(function(msg)
		local estado = EstadoSalvamento.jogadores[player.UserId]
		if not estado then return end

		if not estado.esperandoCPF and not estado.cpfDigitado then
			processarRespostaSalvamento(player, msg, connection)
		elseif estado.esperandoCPF and not estado.cpfDigitado then
			processarCPF(player, msg)
		elseif estado.cpfDigitado then
			processarSenha(player, estado.cpfDigitado, msg)
			-- Cleanup after processing
			EstadoSalvamento:limpar(player)
			connection:Disconnect()
		end
	end)
end

-- Improved response processing
local function processarRespostaSalvamento(player, msg, connection)
	local estado = EstadoSalvamento.jogadores[player.UserId]
	if not estado then return end

	if msg:lower() == "sim!" then
		estado.esperandoCPF = true
		remote:FireClient(player, "Resultado", "Digite seu CPF (apenas números):")
	elseif msg:lower() == "não!" or msg:lower() == "nao!" then
		-- Get offensive message from server
		local success, response = pcall(function()
			return HttpService:PostAsync(
				BASE_URL .. "/gerar-mensagem",
				HttpService:JSONEncode({ tipo = "recusar" }),
				Enum.HttpContentType.ApplicationJson
			)
		end)

		if success then
			local resultado = HttpService:JSONDecode(response)
			remote:FireClient(player, "Resultado", resultado.mensagem)
		else
			remote:FireClient(player, "Resultado", "👋 Até a próxima, fracassado!")
		end

		-- Cleanup
		EstadoSalvamento:limpar(player)
		connection:Disconnect()
	else
		remote:FireClient(player, "Resultado", "⚠️ Digite 'sim!' para salvar ou 'não!' para encerrar.")
	end
end

-- Improved CPF processing with retry tracking
local function processarCPF(player, cpf)
	local estado = EstadoSalvamento.jogadores[player.UserId]
	if not estado then return end

	if not validarCPF(cpf) then
		estado.tentativasCPF = estado.tentativasCPF + 1

		if estado.tentativasCPF >= maxTentativas then
			remote:FireClient(player, "Resultado", "❌ Número máximo de tentativas excedido. CPF inválido.")
			EstadoSalvamento:limpar(player)
			return
		end

		remote:FireClient(player, "Resultado", string.format(
			"❌ CPF inválido. Tentativa %d/%d. Digite novamente (apenas números):", 
			estado.tentativasCPF, maxTentativas
			))
		return
	end

	-- Store CPF and proceed to password
	estado.cpfDigitado = cpf
	estado.esperandoCPF = false
	remote:FireClient(player, "Resultado", "Digite sua senha:")
end

-- Função para processar senha
local function processarSenha(player, cpf, senha)
	local estado = EstadoSalvamento.jogadores[player.UserId]
	if not estado then return end

	local resultado = verificarCredenciais(cpf, senha)
	if resultado.sucesso then
		-- Salvar estatísticas
		local success, response = pcall(function()
			-- Obter estatísticas diretamente do player
			local acertos = player:GetAttribute("Acertos") or 0
			local erros = player:GetAttribute("Erros") or 0
			local ajudas = player:GetAttribute("Ajuda") or 0
			local pulos = player:GetAttribute("Pulos") or 0
			local dinheiro = player:GetAttribute("Dinheiro") or 0

			return HttpService:PostAsync(
				BASE_URL .. "/salvar-estatisticas",
				HttpService:JSONEncode({
					cpf = cpf,
					senha = senha,
					estatisticas = {
						acertos = acertos,
						erros = erros,
						ajudas = ajudas,
						pulos = pulos,
						dinheiroFinal = dinheiro,
						data = os.date("%Y-%m-%d %H:%M:%S")
					}
				}),
				Enum.HttpContentType.ApplicationJson
			)
		end)

		if success then
			local resposta = HttpService:JSONDecode(response)
			if resposta.sucesso then
				remote:FireClient(player, "Resultado", "✅ Estatísticas salvas com sucesso!")
			else
				remote:FireClient(player, "Resultado", "❌ " .. (resposta.mensagem or "Erro ao salvar estatísticas"))
			end
		else
			remote:FireClient(player, "Resultado", "❌ Erro ao salvar estatísticas")
		end
	else
		estado.tentativasSenha = (estado.tentativasSenha or 0) + 1

		if estado.tentativasSenha >= maxTentativas then
			remote:FireClient(player, "Resultado", "❌ Senha incorreta. Número máximo de tentativas excedido.")
			EstadoSalvamento:limpar(player)
			return
		end

		-- Obter mensagem ofensiva para credenciais inválidas
		local success, response = pcall(function()
			return HttpService:PostAsync(
				BASE_URL .. "/gerar-mensagem",
				HttpService:JSONEncode({ tipo = "credenciais_invalidas" }),
				Enum.HttpContentType.ApplicationJson
			)
		end)

		if success then
			local mensagemErro = HttpService:JSONDecode(response)
			remote:FireClient(player, "Resultado", mensagemErro.mensagem)
		else
			remote:FireClient(player, "Resultado", "❌ CPF ou senha incorretos, seu incompetente!")
		end

		-- Pedir nova senha
		remote:FireClient(player, "Resultado", string.format(
			"Digite sua senha novamente (tentativa %d/%d):", 
			estado.tentativasSenha, maxTentativas
			))
	end
end

-- Função para verificar conexão com o servidor
local function verificarConexaoServidor()
	local success, response = pcall(function()
		return HttpService:GetAsync(BASE_URL .. "/status")
	end)

	if success then
		local status = HttpService:JSONDecode(response)
		print("📡 Status do servidor:", status.status)
		print("⏱️ Tempo de atividade:", status.uptime, "minutos")
		return true
	else
		warn("❌ Erro ao verificar conexão com o servidor:", response)
		return false
	end
end

-- pergunta do servidor
local function enviarPergunta(player)
	-- Verificar se o jogador terminou a introdução antes de enviar a pergunta
	if not jogadorTerminouIntroducao[player.UserId] then
		warn("❌ Tentativa de enviar pergunta antes do jogador terminar a introdução")
		return
	end

	-- Verificar conexão com o servidor
	if not verificarConexaoServidor() then
		remote:FireClient(player, "Resultado", "❌ Erro de conexão com o servidor. Tentando reconectar...")
		task.wait(5) -- Aguarda 5 segundos antes de tentar novamente
		if not verificarConexaoServidor() then
			remote:FireClient(player, "Resultado", "❌ Servidor indisponível. Tente novamente mais tarde.")
			return
		end
	end

	-- Contador regressivo de 5 segundos
	for i = 5, 1, -1 do
		remote:FireClient(player, "Resultado", "⏳ Preparando pergunta em " .. i .. " segundos...")
		task.wait(1)
	end

	local success, response = pcall(function()
		print("📤 Solicitando nova pergunta do servidor")
		return HttpService:GetAsync(PERGUNTA_URL)
	end)

	if success then
		print("📥 Resposta recebida do servidor:", response)
		local pergunta = HttpService:JSONDecode(response)
		if pergunta.erro then
			warn("❌ Erro do servidor:", pergunta.erro)
			remote:FireClient(player, "Resultado", "❌ " .. pergunta.erro)
			return
		end

		perguntasAtuais[player.UserId] = pergunta
		player:SetAttribute("MensagemRecebida", "valorX")

		task.wait(0.5)

		-- Enviar apenas uma vez como resultado formatado
		remote:FireClient(player, "Resultado", "\n❓ NOVA PERGUNTA ❓\n" .. pergunta.pergunta)
		print("✅ Pergunta enviada para o jogador:", pergunta.pergunta)
	else
		warn("❌ Erro ao buscar pergunta:", response)
		remote:FireClient(player, "Resultado", "❌ Erro ao buscar pergunta. Tentando novamente...")
		task.wait(2)
		enviarPergunta(player) -- Tenta novamente
	end
end

-- Função para verificar resposta com o servidor
local function verificarResposta(player, mensagem)
	-- Verificar se o jogador terminou a introdução
	if not jogadorTerminouIntroducao[player.UserId] then
		warn("❌ Jogador tentou responder antes de terminar a introdução")
		return
	end

	if jogadorEmEspera[player.UserId] then
		warn("⚠️ Jogador tentou responder enquanto outra requisição está em andamento")
		remote:FireClient(player, "Resultado", "⏳ Já estamos processando algo, aguarde.")
		return
	end

	jogadorEmEspera[player.UserId] = true
	remote:FireClient(player, "Resultado", "⏳ ChatGPT está analisando sua resposta...")

	local pergunta = perguntasAtuais[player.UserId]
	if not pergunta then
		warn("❌ Tentativa de verificar resposta sem pergunta ativa")
		remote:FireClient(player, "Resultado", "❌ Erro: Nenhuma pergunta ativa.")
		jogadorEmEspera[player.UserId] = false
		return
	end

	local dados = { id = pergunta.id, resposta = mensagem }
	local success, respostaServer = pcall(function()
		print("📤 Enviando resposta para o servidor:", mensagem)
		return HttpService:PostAsync(
			RESPOSTA_URL,
			HttpService:JSONEncode(dados),
			Enum.HttpContentType.ApplicationJson
		)
	end)

	if success then
		print("📥 Resposta recebida do servidor:", respostaServer)
		local resultado = HttpService:JSONDecode(respostaServer)

		if resultado.correta then
			print("✅ Resposta correta!")
			local recompensa = math.random(10000, 50000)
			local total = player:GetAttribute("Dinheiro") + recompensa
			atualizarDinheiro(player, total)
			player:SetAttribute("PerguntasRespondidas", player:GetAttribute("PerguntasRespondidas") + 1)
			player:SetAttribute("Acertos", player:GetAttribute("Acertos") + 1)
			remote:FireClient(player, "Resultado", "✅ Resposta correta!")
			player:SetAttribute("MensagemRecebida", "acerto")
			task.wait(2)

			local respondidas = player:GetAttribute("PerguntasRespondidas")
			if respondidas >= 1 then
				-- Estatísticas finais reais
				local acertos = player:GetAttribute("Acertos")
				local erros = player:GetAttribute("Erros")
				local ajudas = player:GetAttribute("Ajuda")
				local pulos = player:GetAttribute("Pulos")
				local recompensaMedia = math.floor((player:GetAttribute("Dinheiro") + (debitos[player.UserId] or 0)) / math.max(acertos, 1))
				local totalGanho = acertos * recompensaMedia

				local gastoErro = debitosErro[player.UserId] or 0
				local gastoAjuda = debitosAjuda[player.UserId] or 0
				local gastoPulo = debitosPulo[player.UserId] or 0
				local totalGasto = gastoErro + gastoAjuda + gastoPulo

				local saldoFinal = math.max(0, totalGanho - totalGasto)

				-- Exibir estatísticas de forma organizada usando a nova função
				exibirEstatisticasFinais(player)
			else
				enviarPergunta(player)
			end
		else
			print("❌ Resposta incorreta")
			player:SetAttribute("Erros", player:GetAttribute("Erros") + 1)
			local valorDebitoErro = math.random(20000, 100000)
			local novoSaldo = math.max(0, player:GetAttribute("Dinheiro") - valorDebitoErro)
			debitos[player.UserId] = (debitos[player.UserId] or 0) + valorDebitoErro
			debitosErro[player.UserId] = (debitosErro[player.UserId] or 0) + valorDebitoErro
			atualizarDinheiro(player, novoSaldo)

			remote:FireClient(player, "Resultado", "❌ Resposta incorreta!")
			player:SetAttribute("MensagemRecebida", "erro")
			task.wait(2)

			-- Reenvia a mesma pergunta
			local pergunta = perguntasAtuais[player.UserId]
			if pergunta then
				remote:FireClient(player, "Pergunta", pergunta.pergunta)
			end
		end
	else
		warn("❌ Erro ao consultar IA:", respostaServer)
		remote:FireClient(player, "Resultado", "❌ Erro ao verificar resposta.")
	end

	jogadorEmEspera[player.UserId] = false
end

-- Função revisada para criar a introdução do jogo com tempo fixo de 8 segundos por mensagem
local function criarIntroducaoParaJogador(player)
	-- Criar GUI para mensagens de introdução
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "IntroducaoGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player:WaitForChild("PlayerGui")

	-- Fundo preto para melhor visualização
	local fundoPreto = Instance.new("Frame")
	fundoPreto.Name = "FundoPreto"
	fundoPreto.Size = UDim2.new(1, 0, 1, 0)
	fundoPreto.BackgroundColor3 = Color3.new(0, 0, 0)
	fundoPreto.BackgroundTransparency = 0
	fundoPreto.ZIndex = 5
	fundoPreto.Active = true -- Bloqueia interações com elementos abaixo
	fundoPreto.Parent = screenGui

	-- Frame principal para as mensagens (mais centralizado e maior)
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0.8, 0, 0.6, 0)
	mainFrame.Position = UDim2.new(0.1, 0, 0.2, 0)
	mainFrame.BackgroundTransparency = 0.2
	mainFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
	mainFrame.BorderSizePixel = 4
	mainFrame.BorderColor3 = Color3.new(0.8, 0, 0)
	mainFrame.ZIndex = 10
	mainFrame.Parent = screenGui

	-- Arredondar cantos do frame principal
	local cornerRadius = Instance.new("UICorner")
	cornerRadius.CornerRadius = UDim.new(0.02, 0)
	cornerRadius.Parent = mainFrame

	-- Texto para exibir as mensagens
	local mensagemTexto = Instance.new("TextLabel")
	mensagemTexto.Name = "MensagemTexto"
	mensagemTexto.Size = UDim2.new(0.9, 0, 0.8, 0)
	mensagemTexto.Position = UDim2.new(0.05, 0, 0.1, 0)
	mensagemTexto.BackgroundTransparency = 1
	mensagemTexto.Font = Enum.Font.GothamBold
	mensagemTexto.TextColor3 = Color3.new(1, 1, 1)
	mensagemTexto.TextSize = 36  -- Texto maior
	mensagemTexto.TextWrapped = true
	mensagemTexto.TextYAlignment = Enum.TextYAlignment.Center
	mensagemTexto.TextXAlignment = Enum.TextXAlignment.Center
	mensagemTexto.TextStrokeTransparency = 0.5
	mensagemTexto.TextStrokeColor3 = Color3.new(0, 0, 0)
	mensagemTexto.ZIndex = 11
	mensagemTexto.Parent = mainFrame

	-- Som de introdução
	local somIntroducao = Instance.new("Sound")
	somIntroducao.Name = "SomIntroducao"
	somIntroducao.SoundId = "rbxassetid://9125181580"
	somIntroducao.Volume = 0.8
	somIntroducao.Parent = screenGui
	somIntroducao:Play()

	-- Desativar controles do jogador durante a introdução
	local caractere = player.Character
	if caractere then
		local humanoid = caractere:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
		end
	end

	local mensagens = {
		{texto = "🩸💀 SEJA BEM-VINDO À ILHA DA ÚLTIMA RESPOSTA 💀🩸", cor = Color3.new(1, 0, 0)},
		{texto = "Este jogo foi inspirado no Show do Milhão, mas com alguns detalhes... levemente aprimorados", cor = Color3.new(1, 1, 1)},
		{texto = "💰 Quer ganhar dinheiro?\nAperte a tecla \";\" para abrir o chat e responder às perguntas.", cor = Color3.new(1, 0.8, 0)},
		{texto = "🎯 REGRAS SÃO SIMPLES:\n\nResponda certo. Ganhe grana.\nErrou? Vai pagar por isso.", cor = Color3.new(0, 1, 1)},
		{texto = "⚠️ PRESTE ATENÇÃO:\n\nCada erro, cada dica, cada pergunta pulada...\nDEBITA o seu saldo.\n\nSem choro. 😢", cor = Color3.new(1, 0.6, 0)},
		{texto = "🆘 PRECISA DE AJUDA?\n\nDigite \"ajuda!\"\n\nQUER PULAR?\n\nDigite \"pula!\"\n\nMas tudo aqui tem preço, campeão.", cor = Color3.new(0, 1, 0.6)},
		{texto = "⏳ O JOGO COMEÇA EM 5 SEGUNDOS...\n\n💀 BOA SORTE. VOCÊ VAI PRECISAR.", cor = Color3.new(1, 0, 0)}
	}

	-- Função para mostrar efeito de digitação mais eficiente
	local function mostrarComEfeitoDigitacao(texto, cor)
		mensagemTexto.Text = ""
		mensagemTexto.TextColor3 = cor

		-- Calcular tempo por caractere para que caiba no tempo destinado (8 segundos no total)
		-- Reservamos 6 segundos para digitação e 2 segundos para leitura
		local tempoTotalDigitacao = 6 -- segundos
		local tempoLeitura = 2 -- segundos
		local tempoPorCaractere = tempoTotalDigitacao / #texto

		-- Efeito sonoro para nova mensagem
		local somMensagem = Instance.new("Sound")
		somMensagem.SoundId = "rbxassetid://255881176"
		somMensagem.Volume = 0.3
		somMensagem.Parent = screenGui
		somMensagem:Play()
		game:GetService("Debris"):AddItem(somMensagem, 2)

		-- Adicionar efeito de digitação
		for i = 1, #texto do
			mensagemTexto.Text = string.sub(texto, 1, i)

			-- Som de digitação leve a cada 5 caracteres
			if i % 5 == 0 then
				local somDigitacao = Instance.new("Sound")
				somDigitacao.SoundId = "rbxassetid://4681278859"
				somDigitacao.Volume = 0.1
				somDigitacao.Parent = screenGui
				somDigitacao:Play()
				game:GetService("Debris"):AddItem(somDigitacao, 1)
			end

			task.wait(tempoPorCaractere)
		end

		-- Tempo de leitura após concluir a digitação
		task.wait(tempoLeitura)
	end

	-- Exibir cada mensagem na sequência com tempo fixo
	for i, mensagem in ipairs(mensagens) do
		mostrarComEfeitoDigitacao(mensagem.texto, mensagem.cor)

		-- Efeito de fade para a próxima mensagem
		for alpha = 0, 1, 0.1 do
			mensagemTexto.TextTransparency = alpha
			task.wait(0.03)
		end

		mensagemTexto.TextTransparency = 0
	end

	-- Som de início
	local somInicio = Instance.new("Sound")
	somInicio.SoundId = "rbxassetid://1584273566"
	somInicio.Volume = 1
	somInicio.Parent = screenGui
	somInicio:Play()

	-- Efeito de fade-out gradual
	for i = 1, 10 do
		mainFrame.BackgroundTransparency = 0.2 + (i * 0.08)
		fundoPreto.BackgroundTransparency = i/10
		mensagemTexto.TextTransparency = i/10
		task.wait(0.1)
	end

	-- Remover GUI após a sequência
	task.wait(1)
	screenGui:Destroy()

	-- Restaurar controles do jogador
	if caractere then
		local humanoid = caractere:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16
			humanoid.JumpPower = 50
		end
	end

	-- Marcar que o jogador concluiu a introdução
	jogadorTerminouIntroducao[player.UserId] = true

	-- Iniciar o jogo enviando a primeira pergunta
	task.wait(1)
	enviarPergunta(player)
end

-- Função para validar CPF
local function validarCPF(cpf)
	cpf = cpf:gsub("[^%d]", "") -- Remove caracteres não numéricos
	if #cpf ~= 11 then return false end

	-- Verifica se todos os dígitos são iguais
	local primeiro = cpf:sub(1,1)
	if cpf:match("^" .. primeiro:rep(11) .. "$") then return false end

	-- Cálculo do primeiro dígito verificador
	local soma = 0
	for i = 1, 9 do
		soma = soma + tonumber(cpf:sub(i,i)) * (11 - i)
	end
	local resto = soma % 11
	local dv1 = resto < 2 and 0 or 11 - resto

	-- Cálculo do segundo dígito verificador
	soma = 0
	for i = 1, 10 do
		soma = soma + tonumber(cpf:sub(i,i)) * (12 - i)
	end
	resto = soma % 11
	local dv2 = resto < 2 and 0 or 11 - resto

	return cpf:sub(10,11) == dv1 .. dv2
end

-- Função para obter mensagem do servidor
local function obterMensagemServidor(tipo)
	local success, response = pcall(function()
		return HttpService:PostAsync(
			BASE_URL .. "/gerar-mensagem",
			HttpService:JSONEncode({ tipo = tipo }),
			Enum.HttpContentType.ApplicationJson
		)
	end)

	if success then
		local resultado = HttpService:JSONDecode(response)
		return resultado.mensagem
	else
		return "Erro ao obter mensagem do servidor"
	end
end

-- Função para enviar estatísticas para o servidor
local function enviarEstatisticas(player, cpf, senha)
	local dados = {
		cpf = cpf,
		senha = senha,
		estatisticas = {
			acertos = player:GetAttribute("Acertos"),
			erros = player:GetAttribute("Erros"),
			ajudas = player:GetAttribute("Ajuda"),
			pulos = player:GetAttribute("Pulos"),
			dinheiroFinal = player:GetAttribute("Dinheiro"),
			data = os.date("%Y-%m-%d %H:%M:%S")
		}
	}

	local success, response = pcall(function()
		return HttpService:PostAsync(
			BASE_URL .. "/salvar-estatisticas",
			HttpService:JSONEncode(dados),
			Enum.HttpContentType.ApplicationJson
		)
	end)

	if success then
		local resultado = HttpService:JSONDecode(response)
		remote:FireClient(player, "Resultado", resultado.mensagem)
	else
		remote:FireClient(player, "Resultado", "Erro ao salvar estatísticas")
	end
end

-- Função para coletar dados do aluno
local function coletarDadosAluno(player)
	remote:FireClient(player, "Resultado", "Deseja salvar suas estatísticas? Digite 'sim!'")

	player.Chatted:Connect(function(msg)
		if msg:lower() == "sim!" then
			remote:FireClient(player, "Resultado", "Digite seu CPF:")

			player.Chatted:Connect(function(cpf)
				remote:FireClient(player, "Resultado", "Digite sua senha:")

				player.Chatted:Connect(function(senha)
					enviarEstatisticas(player, cpf, senha)
				end)
			end)
		end
	end)
end

-- Quando jogador entra
Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local dinheiro = Instance.new("IntValue")
	dinheiro.Name = "Dinheiro"
	dinheiro.Value = 0
	dinheiro.Parent = leaderstats

	player:SetAttribute("Dinheiro", 0)
	player:SetAttribute("PerguntasRespondidas", 0)
	player:SetAttribute("Acertos", 0)
	player:SetAttribute("Erros", 0)
	player:SetAttribute("Pulos", 0)
	player:SetAttribute("Ajuda", 0)
	player:SetAttribute("MensagemRecebida", "")
	debitos[player.UserId] = 0
	debitosErro[player.UserId] = 0
	debitosAjuda[player.UserId] = 0
	debitosPulo[player.UserId] = 0
	jogadorEsperandoConfirmacao[player.UserId] = false
	jogadorTerminouIntroducao[player.UserId] = false -- Inicializa como falso

	HttpService:PostAsync(REINICIAR_URL,
		HttpService:JSONEncode({ jogadorId = tostring(player.UserId) }),
		Enum.HttpContentType.ApplicationJson
	)

	-- Iniciar sequência de introdução
	task.wait(3) -- Tempo para o jogador carregar completamente
	criarIntroducaoParaJogador(player)

	if not player:GetAttribute("ConectadoAoChat") then
		player:SetAttribute("ConectadoAoChat", true)

		player.Chatted:Connect(function(msg)
			-- Ignorar mensagens de chat se a introdução não terminou
			if not jogadorTerminouIntroducao[player.UserId] then
				return
			end

			local pergunta = perguntasAtuais[player.UserId]
			if not pergunta then return end

			if msg:lower() == "ajuda!" or msg:lower() == "help!" then
				if jogadorEmEspera[player.UserId] then
					remote:FireClient(player, "Resultado", "⏳ Já estamos processando algo, aguarde.")
					return
				end

				if jogadorEsperandoConfirmacao[player.UserId] then
					remote:FireClient(player, "Resultado", "⚠️ Você tem uma resposta pendente para confirmar. Digite 'sim!' para confirmar ou 'não!' para cancelar.")
					return
				end

				jogadorEmEspera[player.UserId] = true
				remote:FireClient(player, "Resultado", "💡 Gerando uma dica para te ajudar...")

				local success, respostaDica = pcall(function()
					return HttpService:GetAsync(DICA_URL)
				end)

				if success then
					local somOriginal = ReplicatedStorage:FindFirstChild("SomMensagem")
					if somOriginal then
						local somClone = somOriginal:Clone()
						somClone.Parent = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
						somClone:Play()
						game:GetService("Debris"):AddItem(somClone, 5)
					end

					task.wait(0.5) 

					local dica = HttpService:JSONDecode(respostaDica)
					remote:FireClient(player, "Resultado", "💬 Dica: " .. dica.dica)
					player:SetAttribute("Ajuda", player:GetAttribute("Ajuda") + 1)

					local valorDebitoAjuda = math.random(5000, 20000)
					local novoSaldo = math.max(0, player:GetAttribute("Dinheiro") - valorDebitoAjuda)
					debitos[player.UserId] = (debitos[player.UserId] or 0) + valorDebitoAjuda
					debitosAjuda[player.UserId] = (debitosAjuda[player.UserId] or 0) + valorDebitoAjuda
					atualizarDinheiro(player, novoSaldo)
				else
					warn("Erro ao obter dica:", respostaDica)
					remote:FireClient(player, "Resultado", "❌ Erro ao gerar dica.")
				end

				jogadorEmEspera[player.UserId] = false
				return
			end

			if msg:lower() == "pular!" then
				if jogadorEmEspera[player.UserId] then
					remote:FireClient(player, "Resultado", "⏳ Já estamos processando algo, aguarde.")
					return
				end

				if jogadorEsperandoConfirmacao[player.UserId] then
					remote:FireClient(player, "Resultado", "⚠️ Você tem uma resposta pendente para confirmar. Digite 'sim!' para confirmar ou 'não!' para cancelar.")
					return
				end

				jogadorEmEspera[player.UserId] = true
				remote:FireClient(player, "Resultado", "🔁 Pulando a pergunta atual...")

				player:SetAttribute("Pulos", player:GetAttribute("Pulos") + 1)
				local valorDebito = math.random(0, 10000)
				local novoSaldo = math.max(0, player:GetAttribute("Dinheiro") - valorDebito)
				debitos[player.UserId] = (debitos[player.UserId] or 0) + valorDebito
				debitosPulo[player.UserId] = (debitosPulo[player.UserId] or 0) + valorDebito
				atualizarDinheiro(player, novoSaldo)

				task.wait(1)
				enviarPergunta(player)
				jogadorEmEspera[player.UserId] = false
				return
			end

			-- Processar confirmações
			if jogadorEsperandoConfirmacao[player.UserId] then
				if msg:lower() == "sim!" then
					jogadorEsperandoConfirmacao[player.UserId] = false
					verificarResposta(player, respostasTemporarias[player.UserId])
					return
				elseif msg:lower() == "não!" or msg:lower() == "nao!" then
					jogadorEsperandoConfirmacao[player.UserId] = false
					remote:FireClient(player, "Resultado", "🔄 Responda novamente à pergunta.")
					task.wait(1)
					local pergunta = perguntasAtuais[player.UserId]
					if pergunta then
						remote:FireClient(player, "Pergunta", pergunta.pergunta)
					end
					return
				else
					remote:FireClient(player, "Resultado", "⚠️ Você tem uma resposta pendente para confirmar. Digite 'sim!' para confirmar ou 'não!' para cancelar.")
					return
				end
			end

			-- Considera como resposta e pede confirmação
			if not jogadorEmEspera[player.UserId] and not jogadorEsperandoConfirmacao[player.UserId] then
				respostasTemporarias[player.UserId] = msg
				jogadorEsperandoConfirmacao[player.UserId] = true
				remote:FireClient(player, "Resultado", "🤔 Sua resposta é: \"" .. msg .. "\"\nTem certeza? Digite 'sim' para confirmar ou 'não' para responder novamente.")
			end
		end)
	end
end)

-- Configuração do cliente (remoto)
remote.OnServerEvent:Connect(function(player, tipo, conteudo)
	if tipo == "ConfirmarResposta" then
		-- Verificar se o jogador terminou a introdução
		if not jogadorTerminouIntroducao[player.UserId] then
			return
		end

		if conteudo:lower() == "sim" then
			verificarResposta(player, respostasTemporarias[player.UserId])
		else
			remote:FireClient(player, "Resultado", "🔄 Responda novamente à pergunta.")
			local pergunta = perguntasAtuais[player.UserId]
			if pergunta then
				task.wait(1)
				remote:FireClient(player, "Pergunta", pergunta.pergunta)
			end
		end 
	end
end)
